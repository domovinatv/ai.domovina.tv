/// Watch progress — uvijek lokalno (per-device, jasno označeno u UI-u).
/// Backend swap dodaje Supabase upsert kad je user.isSignedIn (vidi
/// docs/backend-prompts/07-flutter-swap-mocks.md).
library;

import 'dart:convert';
import 'package:flutter/foundation.dart'
    show ChangeNotifier, TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../main.dart' show log;
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

  /// Lokalni "Continue watching" (offline-first fallback). Real source-of-truth
  /// za logged-in usere je `domovina_ai.v_continue_watching` view — koristi
  /// [continueWatchingRemote] da ga povučeš direktno iz Supabase-a.
  Future<List<WatchProgress>> continueWatching({int limit = 20}) async {
    await init();
    final items = _byEpisode.values
        .where((w) => !w.completed && w.positionSeconds > 30)
        .toList()
      ..sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
    return items.take(limit).toList();
  }

  /// Cross-device "Continue watching" iz Supabase `v_continue_watching` view.
  /// View već filtrira `not completed AND position_seconds > 30` i sortira
  /// po `last_watched_at desc`. Za anonymous usere ovo vraća prazno (jer
  /// nemaju pisanog progresa) — Home carousel može fallback-ati na lokalni
  /// `continueWatching()` u tom slučaju.
  Future<List<WatchProgress>> continueWatchingRemote({int limit = 20}) async {
    try {
      final client = sb.Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return [];
      final rows = await client
          .schema('domovina_ai')
          .from('v_continue_watching')
          .select()
          .limit(limit);
      return rows
          .map<WatchProgress?>((r) => WatchProgress(
                episodeId: r['episode_id'] as String,
                channelId: r['channel_id'] as String?,
                positionSeconds: (r['position_seconds'] as num).toInt(),
                durationSeconds: (r['duration_seconds'] as num).toInt(),
                episodeTitle: r['episode_title'] as String?,
                episodeThumbnailUrl: r['episode_thumbnail_url'] as String?,
                lastWatchedAt: DateTime.parse(r['last_watched_at'] as String),
              ))
          .whereType<WatchProgress>()
          .toList();
    } catch (e) {
      log('continueWatchingRemote failed: $e');
      return [];
    }
  }

  /// Sprema progress odmah lokalno (1×/s gate je u `_onVideoPosition`), plus
  /// debounced upsert u Supabase domovina_ai.watch_progress (5s) tako da
  /// kontinualno gledanje ne radi spam u DB. Dispose flushuje pending upsert.
  ///
  /// Anonymous bring-up mode: trenutno DOPUŠTAMO upsert i za anonymous usere
  /// (RLS to dopušta — anonymous ima auth.uid()). Kasnije u onboarding fazi
  /// možemo gate-irati pisanje samo na permanent usere da ne polutiramo DB
  /// pre-link state-om.
  void scheduleSave({
    required String episodeId,
    required int positionSeconds,
    required int durationSeconds,
    String? channelId,
    String? episodeTitle,
    String? episodeThumbnailUrl,
  }) {
    final wp = WatchProgress(
      episodeId: episodeId,
      channelId: channelId,
      positionSeconds: positionSeconds,
      durationSeconds: durationSeconds,
      episodeTitle: episodeTitle,
      episodeThumbnailUrl: episodeThumbnailUrl,
      lastWatchedAt: DateTime.now(),
    );
    _byEpisode[episodeId] = wp;
    _persistSync();

    // Supabase upsert je debounced 5s — ne želimo spam. flush() pri dispose
    // gurne pending odmah.
    _pendingRemote = wp;
    _scheduleRemoteFlush();
  }

  WatchProgress? _pendingRemote;
  bool _remoteFlushScheduled = false;

  void _scheduleRemoteFlush() {
    if (_remoteFlushScheduled) return;
    _remoteFlushScheduled = true;
    Future.delayed(const Duration(seconds: 5), () async {
      _remoteFlushScheduled = false;
      await _flushRemote();
    });
  }

  Future<void> _flushRemote() async {
    final wp = _pendingRemote;
    if (wp == null) return;
    _pendingRemote = null;
    try {
      final client = sb.Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;
      await client.schema('domovina_ai').from('watch_progress').upsert({
        'user_id': user.id,
        'episode_id': wp.episodeId,
        if (wp.channelId != null) 'channel_id': wp.channelId,
        'position_seconds': wp.positionSeconds,
        'duration_seconds': wp.durationSeconds,
        if (wp.episodeTitle != null) 'episode_title': wp.episodeTitle,
        if (wp.episodeThumbnailUrl != null)
          'episode_thumbnail_url': wp.episodeThumbnailUrl,
        'last_watched_at': wp.lastWatchedAt.toUtc().toIso8601String(),
        'last_device': _detectDevice(),
      }, onConflict: 'user_id,episode_id');
    } catch (e) {
      log('watch_progress upsert failed: $e');
      // Lokalna kopija je već spremljena — pri sljedećem tick-u ćemo
      // pokušati opet.
    }
  }

  /// Forsiraj odmah remote upsert (npr. iz dispose hook-a episode screen-a).
  Future<void> flush() async {
    await _flushRemote();
  }

  /// Backfill: gurni svu lokalnu povijest u Supabase za danog user-a.
  /// Trigger: AuthService detektira non-anonymous user-a i pozove ovo jednom
  /// per user_id (gate flag u localStorage). Idempotent — upsert s
  /// onConflict=user_id,episode_id ne duplicira redove.
  ///
  /// Razlog: anonymous user vec pise u Supabase (per Step 4 caveat) pa je
  /// migracija dupla mostly za:
  ///  1. pre-Supabase-rollout localStorage entries (anonymous nije pisao)
  ///  2. offline period prije nego se anonymous JWT instalirao
  Future<void> migrateToSupabase(String userId) async {
    final flagKey = 'watch_progress_migrated_$userId';
    if (await _readFlag(flagKey)) return; // already migrated for this user

    await init();
    final entries = _byEpisode.values.toList();
    if (entries.isEmpty) {
      await _writeFlag(flagKey);
      return;
    }

    try {
      final client = sb.Supabase.instance.client;
      final rows = entries.map((wp) => {
            'user_id': userId,
            'episode_id': wp.episodeId,
            if (wp.channelId != null) 'channel_id': wp.channelId,
            'position_seconds': wp.positionSeconds,
            'duration_seconds': wp.durationSeconds,
            if (wp.episodeTitle != null) 'episode_title': wp.episodeTitle,
            if (wp.episodeThumbnailUrl != null)
              'episode_thumbnail_url': wp.episodeThumbnailUrl,
            'last_watched_at': wp.lastWatchedAt.toUtc().toIso8601String(),
            'last_device': _detectDevice(),
          }).toList();

      await client
          .schema('domovina_ai')
          .from('watch_progress')
          .upsert(rows, onConflict: 'user_id,episode_id');

      await _writeFlag(flagKey);
      log('watch_progress: migrated ${entries.length} local entries for $userId');
    } catch (e) {
      log('watch_progress migrate failed (will retry next session): $e');
    }
  }

  /// Povuci cijelu `watch_progress` tablicu za ulogiranog usera u lokalni
  /// `_byEpisode` cache. Trigger: AuthService nakon detekcije permanent usera
  /// (uz [migrateToSupabase]). Razlog: resume putanja u episode ekranima čita
  /// SAMO lokalni cache (`getSync`) — bez ovoga pozicija s drugog uređaja ili
  /// nakon force-quita (kad fire-and-forget lokalni zapis nije dospio na disk)
  /// se nikad ne vrati i video kreće od 0.
  ///
  /// Merge politika: noviji `lastWatchedAt` pobjeđuje, da hidratacija ne pregazi
  /// svježiju lokalnu poziciju iz tekuće sesije (koja možda još nije upsertana).
  /// Pozovi POSLIJE [migrateToSupabase] da se lokalna povijest prvo gurne gore.
  Future<void> hydrateFromSupabase() async {
    await init();
    try {
      final client = sb.Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;
      final rows = await client
          .schema('domovina_ai')
          .from('watch_progress')
          .select();
      var changed = false;
      for (final r in rows) {
        final remote = WatchProgress(
          episodeId: r['episode_id'] as String,
          channelId: r['channel_id'] as String?,
          positionSeconds: (r['position_seconds'] as num).toInt(),
          durationSeconds: (r['duration_seconds'] as num).toInt(),
          episodeTitle: r['episode_title'] as String?,
          episodeThumbnailUrl: r['episode_thumbnail_url'] as String?,
          lastWatchedAt: DateTime.parse(r['last_watched_at'] as String),
        );
        final local = _byEpisode[remote.episodeId];
        if (local == null ||
            remote.lastWatchedAt.isAfter(local.lastWatchedAt)) {
          _byEpisode[remote.episodeId] = remote;
          changed = true;
        }
      }
      if (changed) {
        _persistSync();
        notifyListeners();
        log('watch_progress: hydrated ${rows.length} remote rows');
      }
    } catch (e) {
      log('watch_progress hydrate failed: $e');
    }
  }

  Future<bool> _readFlag(String key) async {
    if (kIsWeb) return getLocalStorageString(key) == '1';
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key) == '1';
  }

  Future<void> _writeFlag(String key) async {
    if (kIsWeb) {
      setLocalStorageString(key, '1');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, '1');
  }

  String _detectDevice() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      TargetPlatform.macOS => 'macos',
      _ => 'web',
    };
  }

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
