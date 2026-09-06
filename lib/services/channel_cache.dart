import 'dart:async';
import 'package:flutter/foundation.dart';
import '../main.dart' show log;
import '../models/channel_index.dart';
import '../models/channel_detail.dart';
import 'data_service.dart';

/// Singleton in-memory cache za index + sve channel detaile.
/// go_router kreira novi HomeScreen za svaku navigaciju — cache prezivljava.
final channelCache = ChannelCache();

class ChannelCache extends ChangeNotifier {
  ChannelIndex? _index;
  final Map<String, ChannelDetail> _cache = {};
  int _loaded = 0;
  int _total = 0;
  bool _done = false;
  bool _prefetching = false;

  int get loaded => _loaded;
  int get total => _total;
  bool get done => _done;

  /// Cacheirani index — null ako jos nije ucitan.
  ChannelIndex? get index => _index;

  /// Kanali u redoslijedu koji naslovnica prikazuje (aktivni sort mode ili
  /// spremljeni shuffle). Null dok se prvi put ne izračuna.
  ///
  /// **Zašto ovdje, a ne u `_HomeScreenState`:** do 6.9.2026. je redoslijed
  /// živio u State-u naslovnice, pa je pri svakom povratku bio `null` →
  /// `_ChannelGridView` je crtao SKELETON u prvom frameu i tek nakon
  /// `addPostFrameCallback` + async čitanja prefa dobio prave kanale. Podaci su
  /// bili u ovom singletonu, ali *izračunati redoslijed* nije — pa je naslovnica
  /// nakon Backa uvijek prolazila kroz skeleton, i visina joj je rasla u više
  /// asinkronih skokova. To je razlog zbog kojeg nikakvo vraćanje scroll
  /// pozicije nije moglo pogoditi metu: meta se pomicala ispod njega.
  List<ChannelSummary>? _orderedChannels;
  List<ChannelSummary>? get orderedChannels => _orderedChannels;

  /// Zapamti izračunati redoslijed. Ne notifira — pozivatelj je naslovnica koja
  /// ionako radi `setState` u istom potezu, a notifikacija bi ovdje značila
  /// rebuild svakog slušatelja cachea bez promjene podataka.
  void setOrderedChannels(List<ChannelSummary> channels) {
    _orderedChannels = channels;
  }

  /// Poništi zapamćeni redoslijed — zove se kad se promijeni sort mode.
  void invalidateOrder() {
    _orderedChannels = null;
  }

  /// Ucitaj index (samo jednom, cacheira se).
  Future<ChannelIndex> loadIndex() async {
    if (_index != null) return _index!;
    _index = await ChannelService.loadIndex();
    return _index!;
  }

  /// Dohvati cached channel detail — null ako jos nije ucitan.
  ChannelDetail? get(String channelId) => _cache[channelId];

  /// Look up square avatar URL za kanal po imenu (match info.json `channel`
  /// polje s index.json `name` poljem). Null ako index nije ucitan ili
  /// match nije nadjen. Koristeno za media notification artwork.
  String? avatarSquareForChannelName(String name) {
    final idx = _index;
    if (idx == null) return null;
    for (final c in idx.channels) {
      if (c.name == name) return c.avatarSquare;
    }
    return null;
  }

  /// Look up naš interni channel id (npr. `muzevni_budite`) po imenu kanala
  /// (match info.json `channel` ↔ index.json `name`). NB: ovo NIJE YouTube
  /// UC… id koji živi u `info.channelId` — naša `/c/:slug` ruta očekuje naš
  /// id (s `_`). Null ako index nije učitan ili nema matcha. Koristi se za
  /// breadcrumb na episode screenu.
  String? channelIdForName(String name) {
    final idx = _index;
    if (idx == null) return null;
    for (final c in idx.channels) {
      if (c.name == name) return c.id;
    }
    return null;
  }

  /// Ucitaj channel detail (cache-first, network fallback).
  Future<ChannelDetail> loadChannel(String channelId) async {
    final cached = _cache[channelId];
    if (cached != null) return cached;
    final detail = await ChannelService.loadChannel(channelId);
    _cache[channelId] = detail;
    return detail;
  }

  /// Svi ucitani video zapisi iz svih kanala (za globalni search).
  List<({String channelId, String channelName, ChannelVideo video})>
      get allVideos {
    final result =
        <({String channelId, String channelName, ChannelVideo video})>[];
    for (final detail in _cache.values) {
      for (final video in detail.videos) {
        result.add((
          channelId: detail.id,
          channelName: detail.name,
          video: video,
        ));
      }
    }
    return result;
  }

  /// Nadi epizodu po video ID-u medju VEC ucitanim kanalima. Null ako kanal
  /// koji je nosi jos nije u cacheu — za to sluzi [findVideoAsync].
  ({String channelId, String channelName, ChannelVideo video})? findVideo(
    String videoId,
  ) {
    for (final detail in _cache.values) {
      for (final video in detail.videos) {
        if (video.id == videoId) {
          return (
            channelId: detail.id,
            channelName: detail.name,
            video: video,
          );
        }
      }
    }
    return null;
  }

  /// Isto, ali dohvati kanale dok epizoda ne bude nadena.
  ///
  /// Zasto uopce: epizoda kojoj `info.json` jos nije na CDN-u ("u redu
  /// cekanja") postoji ISKLJUCIVO u channel listingu, pa je to jedini izvor
  /// naslova i kanala za nju. Na hladan deep-link `/v/<id>` cache je prazan.
  ///
  /// Kanali se obilaze poredani po datumu zadnje epizode (najsvjeziji prvo):
  /// epizoda bez `info.json`-a je po definiciji tek pristigla, pa je gotovo
  /// uvijek u prvoj sacici kanala. Trazenje staje cim je nade — puni prefetch
  /// svih 48 kanala se dogodi samo za ID koji ne postoji nigdje.
  Future<({String channelId, String channelName, ChannelVideo video})?>
      findVideoAsync(String videoId) async {
    final cached = findVideo(videoId);
    if (cached != null) return cached;

    final ChannelIndex idx;
    try {
      idx = await loadIndex();
    } catch (e) {
      log('ChannelCache.findVideoAsync: index failed: $e');
      return null;
    }

    final ordered = List<ChannelSummary>.from(idx.channels)
      ..sort((a, b) => (b.latestVideo?.date ?? '')
          .compareTo(a.latestVideo?.date ?? ''));

    const batchSize = 6;
    for (var i = 0; i < ordered.length; i += batchSize) {
      final batch = ordered.skip(i).take(batchSize);
      await Future.wait(batch.map((c) => _loadOne(c.id)), eagerError: false);
      final hit = findVideo(videoId);
      if (hit != null) return hit;
    }
    return null;
  }

  /// Prefetchaj sve kanale iz indexa u pozadini.
  /// Noop ako je vec u tijeku ili zavrseno.
  Future<void> prefetchAll(List<ChannelSummary> channels) async {
    if (_prefetching || _done) return;
    _prefetching = true;
    _total = channels.length;
    _loaded = _cache.length; // vec ucitani se broje
    _done = false;
    notifyListeners();

    log('ChannelCache: prefetching ${channels.length} channels...');

    const batchSize = 6;
    for (var i = 0; i < channels.length; i += batchSize) {
      final batch = channels.skip(i).take(batchSize);
      await Future.wait(
        batch.map((ch) => _loadOne(ch.id)),
        eagerError: false,
      );
    }

    _done = true;
    _prefetching = false;
    log('ChannelCache: done, ${_cache.length}/$_total cached');
    notifyListeners();
  }

  Future<void> _loadOne(String channelId) async {
    if (_cache.containsKey(channelId)) {
      _loaded++;
      notifyListeners();
      return;
    }
    try {
      final detail = await ChannelService.loadChannel(channelId);
      _cache[channelId] = detail;
    } catch (e) {
      log('ChannelCache: failed $channelId: $e');
    }
    _loaded++;
    notifyListeners();
  }
}
