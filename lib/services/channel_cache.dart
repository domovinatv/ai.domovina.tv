import 'dart:async';
import 'package:flutter/foundation.dart';
import '../main.dart' show log;
import '../models/channel_index.dart';
import '../models/channel_detail.dart';
import 'data_service.dart';

/// Singleton in-memory cache svih channel detaila.
/// Prefetch nakon sto se index ucita — svi kanali se downlodaju paralelno.
/// Navigacija na kanal postaje instant jer su podaci vec u memoriji.
/// Singleton jer go_router kreira novi HomeScreen za svaku navigaciju.
final channelCache = ChannelCache();

class ChannelCache extends ChangeNotifier {
  final Map<String, ChannelDetail> _cache = {};
  int _loaded = 0;
  int _total = 0;
  bool _done = false;

  /// Koliko je kanala ucitano / ukupno.
  int get loaded => _loaded;
  int get total => _total;
  bool get done => _done;

  /// Dohvati cached channel detail — null ako jos nije ucitan.
  ChannelDetail? get(String channelId) => _cache[channelId];

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

  bool _prefetching = false;

  /// Prefetchaj sve kanale iz indexa u pozadini.
  /// Noop ako je vec u tijeku ili zavrseno.
  Future<void> prefetchAll(List<ChannelSummary> channels) async {
    if (_prefetching || _done) return;
    _prefetching = true;
    _total = channels.length;
    _loaded = 0;
    _done = false;
    notifyListeners();

    log('ChannelCache: prefetching ${channels.length} channels...');

    // Paralelno ali s concurrency limitom da ne bombardiramo CDN
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
    log('ChannelCache: done, $_loaded/$_total cached');
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
