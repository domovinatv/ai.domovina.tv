/// Watch progress — uvijek lokalno (per-device, jasno označeno u UI-u).
/// Backend swap dodaje Supabase upsert kad je user.isSignedIn (vidi
/// docs/backend-prompts/07-flutter-swap-mocks.md).
library;

import 'dart:async';
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

  Future<void> _ensureLoaded() async {
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

  Future<WatchProgress?> get(String episodeId) async {
    await _ensureLoaded();
    return _byEpisode[episodeId];
  }

  Future<List<WatchProgress>> continueWatching({int limit = 20}) async {
    await _ensureLoaded();
    final items = _byEpisode.values
        .where((w) => !w.completed && w.positionSeconds > 30)
        .toList()
      ..sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
    return items.take(limit).toList();
  }

  /// Debounce upserts (~5s) da ne dolazi do prevelikih write ciklusa kad pravi
  /// backend bude live. U mocku ionako pišemo lokalno ali držimo isti API.
  Timer? _debounce;
  WatchProgress? _pending;

  void scheduleSave({
    required String episodeId,
    required int positionSeconds,
    required int durationSeconds,
    String? channelId,
    String? episodeTitle,
    String? episodeThumbnailUrl,
  }) {
    _pending = WatchProgress(
      episodeId: episodeId,
      channelId: channelId,
      positionSeconds: positionSeconds,
      durationSeconds: durationSeconds,
      episodeTitle: episodeTitle,
      episodeThumbnailUrl: episodeThumbnailUrl,
      lastWatchedAt: DateTime.now(),
    );
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 5), _flush);
  }

  Future<void> flush() async {
    _debounce?.cancel();
    await _flush();
  }

  Future<void> _flush() async {
    if (_pending == null) return;
    await _ensureLoaded();
    _byEpisode[_pending!.episodeId] = _pending!;
    _pending = null;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final list = _byEpisode.values.map((w) => w.toJson()).toList();
    final raw = jsonEncode(list);
    await _write(raw);
  }

  Future<void> clearAll() async {
    _byEpisode.clear();
    await _persist();
    notifyListeners();
  }

  Future<String?> _read() async {
    if (kIsWeb) return getLocalStorageString(_kKey);
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kKey);
  }

  Future<void> _write(String value) async {
    if (kIsWeb) {
      setLocalStorageString(_kKey, value);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, value);
  }
}
