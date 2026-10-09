import 'dart:async';
import 'package:flutter/foundation.dart';
import '../main.dart' show log;
import '../models/channel_index.dart';
import '../models/channel_detail.dart';
import '../models/home_snapshot.dart';
import '../models/search_corpus.dart';
import 'data_service.dart';

/// Singleton in-memory cache za index + sve channel detaile.
/// go_router kreira novi HomeScreen za svaku navigaciju — cache prezivljava.
final channelCache = ChannelCache();

/// Epizoda s kontekstom kanala (isti oblik kao `FeedVideo` u `home_feed.dart`).
typedef FeedVideoRecord = ({
  String channelId,
  String channelName,
  ChannelVideo video,
});

/// Koliko listinga kanala se dohvaća istovremeno. Preglednik ionako drži do 6
/// HTTP/1.1 veza po hostu; preko HTTP/2 je to umjereno ograničenje da prefetch
/// ne zagrabi svu propusnost sporoj vezi kojoj trebaju i slike.
const _kPrefetchConcurrency = 6;

/// Kanali poredani po datumu zadnje epizode, najsvježiji prvo. Kanal bez
/// `latest_video` ide na kraj. Stabilno (ne mijenja ulaznu listu).
List<ChannelSummary> byFreshness(List<ChannelSummary> channels) =>
    List<ChannelSummary>.from(channels)
      ..sort((a, b) =>
          (b.latestVideo?.date ?? '').compareTo(a.latestVideo?.date ?? ''));

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
    // Spremljeni index stiže odmah; noviji (novi kanal, nova zadnja epizoda)
    // zamijeni ga kad revalidacija završi. Redoslijed naslovnice se tada NE
    // preračunava ispod korisnika — novi poredak vrijedi od sljedećeg ulaska.
    _index = await ChannelService.loadIndex(onUpdate: (fresh) {
      _index = fresh;
      _total = fresh.channels.length;
      notifyListeners();
    });
    return _index!;
  }

  HomeSnapshot? _homeSnapshot;
  Future<HomeSnapshot?>? _homeSnapshotFuture;

  /// `home.json` ako je stigao; `null` dok nije ili ako ga nema.
  HomeSnapshot? get homeSnapshot => _homeSnapshot;

  /// Učitaj `home.json` (jednom). Kad stigne, notificira — hero i railovi
  /// naslovnice tada ne čekaju listinge. Vidi [feedVideos].
  Future<HomeSnapshot?> loadHomeSnapshot() {
    return _homeSnapshotFuture ??= () async {
      final snap = await ChannelService.loadHomeSnapshot(onUpdate: (fresh) {
        _homeSnapshot = fresh;
        notifyListeners();
      });
      if (snap != null) {
        _homeSnapshot = snap;
        log('ChannelCache: home.json — ${snap.episodes.length} epizoda');
        notifyListeners();
      } else {
        log('ChannelCache: home.json nedostupan — puni listinzi');
      }
      return snap;
    }();
  }

  /// Bazen epizoda za hero i railove naslovnice: `home.json` ∪ učitani
  /// listinzi, bez duplikata. Zapis iz listinga ima prednost (puniji je).
  /// Bez `home.json` jednako [allVideos].
  List<FeedVideoRecord> get feedVideos {
    final full = allVideos;
    final snap = _homeSnapshot;
    if (snap == null) return full;
    final seen = {for (final v in full) v.video.id};
    return [
      ...full,
      for (final e in snap.episodes)
        if (seen.add(e.video.id))
          (
            channelId: e.channelId,
            channelName: _channelName(e.channelId),
            video: e.video,
          ),
    ];
  }

  String _channelName(String channelId) {
    final idx = _index;
    if (idx != null) {
      for (final c in idx.channels) {
        if (c.id == channelId) return c.name;
      }
    }
    return channelId;
  }

  SearchCorpus? _searchCorpus;
  Future<void>? _searchCorpusFuture;

  /// Učitaj `search.json` (jednom) i nadopuni njime sve učitane listinge;
  /// listinzi koji stignu kasnije nadopunjuju se pri ubacivanju u cache.
  /// Zovu ga ekrani kojima treba tekst epizode (pretraga, sponzorski izlog) —
  /// naslovnica ne. Dok su listinzi v1 (tekst nose sami), `search.json` ne
  /// postoji i ovo je jedan 404 po sesiji.
  Future<void> ensureSearchText() {
    return _searchCorpusFuture ??= () async {
      final corpus = await ChannelService.loadSearchCorpus();
      if (corpus == null) return;
      _applySearchCorpus(corpus);
      log('ChannelCache: search.json — ${corpus.byId.length} epizoda');
    }();
  }

  void _applySearchCorpus(SearchCorpus corpus) {
    _searchCorpus = corpus;
    for (final id in _cache.keys.toList()) {
      _cache[id] = _withSearchText(_cache[id]!);
    }
    notifyListeners();
  }

  /// Postavi `search.json` bez mrežnog dohvata — samo za testove.
  @visibleForTesting
  void seedSearchCorpusForTest(SearchCorpus corpus) {
    _searchCorpusFuture = Future.value();
    _applySearchCorpus(corpus);
  }

  /// [loadChannel] uz tekst za pretragu (sažetak, teme, govornici).
  Future<ChannelDetail> loadChannelWithText(String channelId) async {
    await ensureSearchText();
    return loadChannel(channelId);
  }

  ChannelDetail _withSearchText(ChannelDetail detail) {
    final corpus = _searchCorpus;
    if (corpus == null) return detail;
    return detail.withVideos([
      for (final v in detail.videos)
        if (corpus.byId[v.id] case final t?)
          v.withSearchText(
              abstract: t.abstract, topics: t.topics, speakers: t.speakers)
        else
          v,
    ]);
  }

  /// Novija verzija listinga stigla revalidacijom (vidi `CdnJsonCache`).
  void _replaceChannel(String channelId, ChannelDetail fresh) {
    _cache[channelId] = _withSearchText(fresh);
    notifyListeners();
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
    final detail = _withSearchText(await ChannelService.loadChannel(channelId,
        onUpdate: (fresh) => _replaceChannel(channelId, fresh)));
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
    // Epizoda iz `home.json` čiji listing još nije stigao (npr. kartica na
    // naslovnici prije pozadinskog prefetcha) — `shareLanguageForVideo` i
    // ostali sinkroni pozivatelji ionako žele samo naslov/zastavice.
    for (final e in _homeSnapshot?.episodes ?? const <HomeSnapshotEpisode>[]) {
      if (e.video.id == videoId) {
        return (
          channelId: e.channelId,
          channelName: _channelName(e.channelId),
          video: e.video,
        );
      }
    }
    return null;
  }

  /// Ubaci kanal u cache bez mrežnog dohvata — samo za testove.
  @visibleForTesting
  void seedForTest(ChannelDetail detail) {
    _cache[detail.id] = _withSearchText(detail);
  }

  /// Postavi `home.json` bez mrežnog dohvata — samo za testove.
  @visibleForTesting
  void seedHomeSnapshotForTest(HomeSnapshot snapshot) {
    _homeSnapshot = snapshot;
  }

  /// Postavi index bez mrežnog dohvata — samo za testove.
  @visibleForTesting
  void seedIndexForTest(ChannelIndex index) {
    _index = index;
    _total = index.channels.length;
  }

  /// Isprazni cache — samo za testove (singleton je globalan, pa bi stanje
  /// curilo između test slučajeva).
  @visibleForTesting
  void resetForTest() {
    _cache.clear();
    _index = null;
    _homeSnapshot = null;
    _homeSnapshotFuture = null;
    _searchCorpus = null;
    _searchCorpusFuture = null;
    _loaded = 0;
    _total = 0;
    _done = false;
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

    final ordered = byFreshness(idx.channels);

    const batchSize = 6;
    for (var i = 0; i < ordered.length; i += batchSize) {
      final batch = ordered.skip(i).take(batchSize);
      await Future.wait(batch.map((c) => _loadOne(c.id)), eagerError: false);
      final hit = findVideo(videoId);
      if (hit != null) return hit;
    }
    return null;
  }

  /// Je li listing kanala već u cacheu (uspješno učitan).
  bool isLoaded(String channelId) => _cache.containsKey(channelId);

  /// Prefetchaj sve kanale iz indexa u pozadini.
  /// Noop ako je vec u tijeku ili zavrseno.
  ///
  /// Redoslijed je po svježini (`latest_video.date` iz indexa, najnoviji prvo):
  /// hero i railovi naslovnice grade se od najnovijih epizoda, pa kanali koji
  /// ih nose moraju stići prvi — vidi [HomeFeed.heroPoolComplete].
  ///
  /// Dohvat ide kroz pool od [_kPrefetchConcurrency] aktivnih zahtjeva, a ne u
  /// šestorkama s `Future.wait`: šestorka je čekala svoj najsporiji kanal prije
  /// sljedeće, pa je jedan spori listing blokirao ostalih pet (9 sekvencijalnih
  /// rundi za 50 kanala). U poolu sljedeći kanal kreće čim bilo koji završi.
  Future<void> prefetchAll(List<ChannelSummary> channels) async {
    if (_prefetching || _done) return;
    _prefetching = true;
    _total = channels.length;
    _loaded = _cache.length; // vec ucitani se broje
    _done = false;
    notifyListeners();

    log('ChannelCache: prefetching ${channels.length} channels...');

    final queue = byFreshness(channels).iterator;
    Future<void> worker() async {
      while (queue.moveNext()) {
        await _loadOne(queue.current.id);
      }
    }

    await Future.wait(
      List.generate(_kPrefetchConcurrency, (_) => worker()),
    );

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
      final detail = await ChannelService.loadChannel(channelId,
          onUpdate: (fresh) => _replaceChannel(channelId, fresh));
      _cache[channelId] = _withSearchText(detail);
    } catch (e) {
      log('ChannelCache: failed $channelId: $e');
    }
    _loaded++;
    notifyListeners();
  }
}
