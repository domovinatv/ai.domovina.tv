/// Favoriti — dual-write: localStorage (offline-first cache) + Supabase
/// `domovina_ai.favorites` za signed-in usere. Anonymous korisnici ostaju
/// samo lokalno (trigger ne kreira personal account dok ne urade
/// linkIdentity → tek tada mogu pisati u favorites tablicu).
library;

import 'dart:convert';
import 'package:flutter/foundation.dart' show ChangeNotifier, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../main.dart' show log;
import 'local_prefs.dart';

const _kKey = 'favorites_v1';

class FavoritesService extends ChangeNotifier {
  static final FavoritesService instance = FavoritesService._();
  FavoritesService._();

  final Set<String> _set = {};
  bool _loaded = false;

  /// Cache personal account ID — lookup je eager pri prvom remote pisanju,
  /// invalidira se na sign-out.
  String? _personalAccountId;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final raw = await _read();
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        _set.addAll(list.cast<String>());
      } catch (_) {}
    }
    _loaded = true;
  }

  Future<bool> isFavorite(String episodeId) async {
    await _ensureLoaded();
    return _set.contains(episodeId);
  }

  Future<List<String>> all() async {
    await _ensureLoaded();
    return _set.toList();
  }

  Future<bool> toggle(String episodeId) async {
    await _ensureLoaded();
    final wasAdded = !_set.contains(episodeId);
    if (wasAdded) {
      _set.add(episodeId);
    } else {
      _set.remove(episodeId);
    }
    await _persist();
    notifyListeners();

    // Fire-and-forget remote sync — UI ne čeka. Anonymous korisnici ne pišu.
    unawaited(_syncRemote(episodeId, wasAdded));
    return wasAdded;
  }

  Future<void> _syncRemote(String episodeId, bool isFavorite) async {
    try {
      final client = sb.Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null || user.isAnonymous) return;

      final ownerId = await _personalAccountIdFor(user.id);
      if (ownerId == null) {
        // Personal account još nije kreiran (trigger čeka da
        // is_anonymous postane false). Lokalni save je dovoljan.
        return;
      }

      final fav = client.schema('domovina_ai').from('favorites');
      if (isFavorite) {
        await fav.upsert({
          'owner_id': ownerId,
          'episode_id': episodeId,
          'created_by': user.id,
        }, onConflict: 'owner_id,episode_id');
      } else {
        await fav
            .delete()
            .eq('owner_id', ownerId)
            .eq('episode_id', episodeId);
      }
    } catch (e) {
      log('favorites remote sync failed: $e');
    }
  }

  Future<String?> _personalAccountIdFor(String userId) async {
    if (_personalAccountId != null) return _personalAccountId;
    try {
      final row = await sb.Supabase.instance.client
          .from('accounts')
          .select('id')
          .eq('primary_owner_user_id', userId)
          .eq('is_personal_account', true)
          .maybeSingle();
      _personalAccountId = row?['id'] as String?;
      return _personalAccountId;
    } catch (e) {
      log('personal account lookup failed: $e');
      return null;
    }
  }

  /// Reset cache (npr. na sign-out).
  void resetAccountCache() {
    _personalAccountId = null;
  }

  /// Backfill: gurni sve lokalne favorite u Supabase za danog user-a.
  /// Trigger: AuthService detektira non-anonymous user-a (npr. nakon
  /// linkIdentity ili re-login). Anonymous users ne piše remote favorite
  /// (per FavoritesService dizajnu — vidi _syncRemote) pa svaki anon→permanent
  /// flow treba ovaj backfill. Gate flag u localStorage per user_id.
  ///
  /// Idempotent: upsert s onConflict=owner_id,episode_id.
  Future<void> migrateToSupabase(String userId) async {
    final flagKey = 'favorites_migrated_$userId';
    if (await _readFlag(flagKey)) return;

    await _ensureLoaded();
    final episodeIds = _set.toList();
    if (episodeIds.isEmpty) {
      await _writeFlag(flagKey);
      return;
    }

    try {
      final ownerId = await _personalAccountIdFor(userId);
      if (ownerId == null) {
        // Personal account jos nije kreiran (trigger ceka da is_anonymous
        // postane false + propagation lag). Ne markiraj kao migrated —
        // sljedeci session ce ponovo pokusati.
        log('favorites migrate skipped: no personal account yet');
        return;
      }

      final rows = episodeIds.map((id) => {
            'owner_id': ownerId,
            'episode_id': id,
            'created_by': userId,
          }).toList();

      await sb.Supabase.instance.client
          .schema('domovina_ai')
          .from('favorites')
          .upsert(rows, onConflict: 'owner_id,episode_id');

      await _writeFlag(flagKey);
      log('favorites: migrated ${episodeIds.length} local entries for $userId');
    } catch (e) {
      log('favorites migrate failed (will retry next session): $e');
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

  Future<void> _persist() async {
    final raw = jsonEncode(_set.toList());
    if (kIsWeb) {
      setLocalStorageString(_kKey, raw);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, raw);
  }

  Future<String?> _read() async {
    if (kIsWeb) return getLocalStorageString(_kKey);
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kKey);
  }
}

/// `unawaited` helper — explicit fire-and-forget.
void unawaited(Future<void> _) {}
