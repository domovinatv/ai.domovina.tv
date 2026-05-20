/// Watch progress — uvijek lokalno (per-device, jasno označeno u UI-u).
/// Backend swap dodaje Supabase upsert kad je user.isSignedIn (vidi
/// docs/backend-prompts/07-flutter-swap-mocks.md).
library;

import 'dart:convert';
import 'package:flutter/foundation.dart' show ChangeNotifier, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'local_prefs.dart';

const _kKey = 'watch_progress_v1';

/// Mirrors `domovina_ai.watch_progress` (v3 schema). Episode title + thumbnail
/// su denorm cache koje skidaju sekundarni CDN fetch za "Continue watching".
class WatchProgress {
  final String episodeId;
  final String? channelId;
  final int positionSeconds;
  final int durationSeconds;
  final String? episodeTitle;
  final String? episodeThumbnailUrl;
  final DateTime lastWatchedAt;

  const WatchProgress({
    required this.episodeId,
    this.channelId,
    required this.positionSeconds,
    required this.durationSeconds,
    this.episodeTitle,
    this.episodeThumbnailUrl,
    required this.lastWatchedAt,
  });

  double get percentComplete =>
      durationSeconds == 0 ? 0 : (positionSeconds / durationSeconds * 100).clamp(0, 100);
  bool get completed => percentComplete >= 90;

  Map<String, dynamic> toJson() => {
        'episodeId': episodeId,
        if (channelId != null) 'channelId': channelId,
        'positionSeconds': positionSeconds,
        'durationSeconds': durationSeconds,
        if (episodeTitle != null) 'episodeTitle': episodeTitle,
        if (episodeThumbnailUrl != null) 'episodeThumbnailUrl': episodeThumbnailUrl,
        'lastWatchedAt': lastWatchedAt.toIso8601String(),
      };

  static WatchProgress? fromJson(Map<String, dynamic> j) {
    try {
      return WatchProgress(
        episodeId: j['episodeId'] as String,
        channelId: j['channelId'] as String?,
        positionSeconds: (j['positionSeconds'] as num).toInt(),
        durationSeconds: (j['durationSeconds'] as num).toInt(),
        episodeTitle: j['episodeTitle'] as String?,
        episodeThumbnailUrl: j['episodeThumbnailUrl'] as String?,
        lastWatchedAt: DateTime.parse(j['lastWatchedAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

class WatchProgressService extends ChangeNotifier {
  static final WatchProgressService instance = WatchProgressService._();
  WatchProgressService._();

  final Map<String, WatchProgress> _byEpisode = {};
  bool _loaded = false;

  /// Pozove se jednom iz `main.dart` prije `runApp`. Garantira da `_byEpisode`
  /// sadrži sve perzistirane progrese prije nego što ih bilo koji screen čita.
  Future<void> init() async {
    if (_loaded) return;
    final raw = await _read();
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        for (final j in list) {
          final wp = WatchProgress.fromJson(j as Map<String, dynamic>);
          if (wp != null) _byEpisode[wp.episodeId] = wp;
        }
      } catch (_) {}
    }
    _loaded = true;
  }

  /// Sinkroni lookup — `init()` mora biti pozvan prije.
  WatchProgress? getSync(String episodeId) => _byEpisode[episodeId];

  Future<WatchProgress?> get(String episodeId) async {
    await init();
    return _byEpisode[episodeId];
  }

  Future<List<WatchProgress>> continueWatching({int limit = 20}) async {
    await init();
    final items = _byEpisode.values
        .where((w) => !w.completed && w.positionSeconds > 30)
        .toList()
      ..sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
    return items.take(limit).toList();
  }

  /// Sprema progress odmah (lokalni mock). `_onVideoPosition` već gate-a poziv
  /// na 1×/s pa nema potrebe za dodatnim debounce-om — fire-and-forget dispose
  /// race iz prethodne implementacije je time eliminiran.
  ///
  /// Pravi backend swap zamijenit će ovo s debounced Supabase upsert-om
  /// (~5s); vidi docs/backend-prompts/07-flutter-swap-mocks.md.
  void scheduleSave({
    required String episodeId,
    required int positionSeconds,
    required int durationSeconds,
    String? channelId,
    String? episodeTitle,
    String? episodeThumbnailUrl,
  }) {
    _byEpisode[episodeId] = WatchProgress(
      episodeId: episodeId,
      channelId: channelId,
      positionSeconds: positionSeconds,
      durationSeconds: durationSeconds,
      episodeTitle: episodeTitle,
      episodeThumbnailUrl: episodeThumbnailUrl,
      lastWatchedAt: DateTime.now(),
    );
    _persistSync();
  }

  /// No-op zadržan zbog backward-compat poziva u dispose-u episode screen-ova.
  Future<void> flush() async {}

  void _persistSync() {
    final list = _byEpisode.values.map((w) => w.toJson()).toList();
    final raw = jsonEncode(list);
    if (kIsWeb) {
      setLocalStorageString(_kKey, raw);
      return;
    }
    // Native: best-effort async (web je kritični path za dispose race).
    SharedPreferences.getInstance().then((p) => p.setString(_kKey, raw));
  }

  Future<void> clearAll() async {
    _byEpisode.clear();
    _persistSync();
    notifyListeners();
  }

  Future<String?> _read() async {
    if (kIsWeb) return getLocalStorageString(_kKey);
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kKey);
  }
}
