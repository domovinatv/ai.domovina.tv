/// Favoriti — dual-write: localStorage (offline-first cache) + Supabase
/// `domovina_ai.favorites` za signed-in usere. Anonymous korisnici ostaju
/// samo lokalno (trigger ne kreira personal account dok ne urade
/// linkIdentity → tek tada mogu pisati u favorites tablicu).
///
/// Zapis nosi **vrijeme spremanja** i denormalizirani naslov/kanal, da rail na
/// naslovnici i `/favorites` ekran mogu odmah crtati (najnoviji prvi) i bez
/// učitanog `channelCache`-a. Kanonski izvor metapodataka i dalje je katalog —
/// denorm je samo fallback.
library;

import 'dart:convert';
import 'package:flutter/foundation.dart'
    show ChangeNotifier, kIsWeb, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../main.dart' show log;
import 'local_prefs.dart';

/// v1 = gola JSON lista episode ID-eva (bez vremena). Čita se samo pri migraciji.
const _kKeyV1 = 'favorites_v1';

/// v2 = JSON lista objekata `{id, addedAt?, title?, channel?}`.
const _kKey = 'favorites_v2';

/// Jedan spremljeni favorit.
///
/// [addedAt] je null za zapise migrirane iz v1 formata (nikad nisu imali
/// vrijeme) — takvi idu na kraj liste, iza svega s poznatim vremenom.
class FavoriteEntry {
  final String episodeId;
  final DateTime? addedAt;

  /// Denorm cache — vrijedi samo dok katalog nema svježiji podatak.
  final String? title;
  final String? channelName;

  const FavoriteEntry({
    required this.episodeId,
    this.addedAt,
    this.title,
    this.channelName,
  });

  FavoriteEntry copyWith({
    DateTime? addedAt,
    String? title,
    String? channelName,
  }) =>
      FavoriteEntry(
        episodeId: episodeId,
        addedAt: addedAt ?? this.addedAt,
        title: title ?? this.title,
        channelName: channelName ?? this.channelName,
      );

  Map<String, dynamic> toJson() => {
        'id': episodeId,
        if (addedAt != null) 'addedAt': addedAt!.toIso8601String(),
        if (title != null) 'title': title,
        if (channelName != null) 'channel': channelName,
      };

  static FavoriteEntry? fromJson(dynamic raw) {
    // v1 zapis je goli string — podnosimo ga i unutar v2 liste.
    if (raw is String) {
      return raw.isEmpty ? null : FavoriteEntry(episodeId: raw);
    }
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    DateTime? added;
    final ts = raw['addedAt'];
    if (ts is String) added = DateTime.tryParse(ts);
    return FavoriteEntry(
      episodeId: id,
      addedAt: added,
      title: raw['title'] as String?,
      channelName: raw['channel'] as String?,
    );
  }
}

class FavoritesService extends ChangeNotifier {
  static final FavoritesService instance = FavoritesService._();
  FavoritesService._();

  /// Insertion-ordered (LinkedHashMap je Dart default) — čuva redoslijed
  /// legacy zapisa bez vremena.
  final Map<String, FavoriteEntry> _byId = {};
  bool _loaded = false;

  /// Cache personal account ID — lookup je eager pri prvom remote pisanju,
  /// invalidira se na sign-out.
  String? _personalAccountId;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final raw = await _read(_kKey) ?? await _read(_kKeyV1);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        for (final item in list) {
          final entry = FavoriteEntry.fromJson(item);
          if (entry != null) _byId[entry.episodeId] = entry;
        }
      } catch (_) {}
    }
    _loaded = true;
  }

  /// Pozovi jednom iz `main.dart` prije `runApp` ako želiš sinkroni pristup.
  Future<void> init() => _ensureLoaded();

  Future<bool> isFavorite(String episodeId) async {
    await _ensureLoaded();
    return _byId.containsKey(episodeId);
  }

  /// Sinkroni lookup — vrijedi tek nakon [init]/prvog `await`-anog poziva.
  bool isFavoriteSync(String episodeId) => _byId.containsKey(episodeId);

  Future<List<String>> all() async {
    await _ensureLoaded();
    return _byId.keys.toList();
  }

  /// Svi favoriti, **najnoviji prvi**. Zapisi bez vremena (v1 migracija) idu
  /// na kraj, u izvornom redoslijedu spremanja.
  Future<List<FavoriteEntry>> entries() async {
    await _ensureLoaded();
    return entriesSync();
  }

  /// Sinkrona varijanta [entries] — za widgete koji su već pozvali [init]
  /// (ili su se probudili na `notifyListeners`).
  List<FavoriteEntry> entriesSync() {
    final list = _byId.values.toList();
    final index = {
      for (var i = 0; i < list.length; i++) list[i].episodeId: i,
    };
    // List.sort nije stabilan → eksplicitni tie-break po insertion indexu.
    list.sort((a, b) {
      final at = a.addedAt;
      final bt = b.addedAt;
      if (at != null && bt != null) {
        final cmp = bt.compareTo(at);
        if (cmp != 0) return cmp;
      } else if (at != null) {
        return -1;
      } else if (bt != null) {
        return 1;
      }
      return index[a.episodeId]!.compareTo(index[b.episodeId]!);
    });
    return list;
  }

  int get count => _byId.length;

  /// Toggle favorita. [title]/[channelName] su opcionalni denorm podaci —
  /// proslijedi ih kad ih ekran ionako ima (episode screen), da lista
  /// spremljenih radi i prije nego se katalog učita.
  Future<bool> toggle(
    String episodeId, {
    String? title,
    String? channelName,
  }) async {
    await _ensureLoaded();
    final wasAdded = !_byId.containsKey(episodeId);
    if (wasAdded) {
      _byId[episodeId] = FavoriteEntry(
        episodeId: episodeId,
        addedAt: DateTime.now(),
        title: title,
        channelName: channelName,
      );
    } else {
      _byId.remove(episodeId);
    }
    await _persist();
    notifyListeners();

    // Fire-and-forget remote sync — UI ne čeka. Anonymous korisnici ne pišu.
    unawaited(_syncRemote(episodeId, wasAdded));
    return wasAdded;
  }

  /// Ukloni favorit (idempotentno) — za listu spremljenih, gdje je akcija
  /// „makni", ne „prebaci".
  Future<void> remove(String episodeId) async {
    await _ensureLoaded();
    if (_byId.remove(episodeId) == null) return;
    await _persist();
    notifyListeners();
    unawaited(_syncRemote(episodeId, false));
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
    final episodeIds = _byId.keys.toList();
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

      final rows = episodeIds.map((id) {
        final added = _byId[id]?.addedAt;
        return {
          'owner_id': ownerId,
          'episode_id': id,
          'created_by': userId,
          // Vrijeme spremanja s uređaja — bez njega bi backfill sve favorite
          // stisnuo na isti `now()` i uništio redoslijed „najnoviji prvi".
          if (added != null) 'created_at': added.toUtc().toIso8601String(),
        };
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

  /// Povuci favorite s računa u lokalni cache — favorit spremljen na drugom
  /// uređaju inače nikad ne dođe natrag (lokalni zapis je jedini izvor za UI).
  /// Zove se nakon [migrateToSupabase], da se lokalno prvo gurne gore.
  ///
  /// Merge politika: remote se dodaje ako ga lokalno nema; ako ga ima bez
  /// vremena (v1 migracija), preuzima se `created_at` s računa. Lokalno
  /// brisanje se NE poništava jer toggle odmah briše i remote red.
  Future<void> hydrateFromSupabase() async {
    await _ensureLoaded();
    try {
      final client = sb.Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null || user.isAnonymous) return;
      final rows = await client
          .schema('domovina_ai')
          .from('favorites')
          .select('episode_id, created_at');
      var changed = false;
      for (final r in rows) {
        final id = r['episode_id'] as String?;
        if (id == null || id.isEmpty) continue;
        final created = DateTime.tryParse((r['created_at'] as String?) ?? '');
        final local = _byId[id];
        if (local == null) {
          _byId[id] = FavoriteEntry(episodeId: id, addedAt: created);
          changed = true;
        } else if (local.addedAt == null && created != null) {
          _byId[id] = local.copyWith(addedAt: created);
          changed = true;
        }
      }
      if (changed) {
        await _persist();
        notifyListeners();
        log('favorites: hydrated ${rows.length} remote rows');
      }
    } catch (e) {
      log('favorites hydrate failed: $e');
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
    final raw = jsonEncode(_byId.values.map((e) => e.toJson()).toList());
    if (kIsWeb) {
      setLocalStorageString(_kKey, raw);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, raw);
  }

  Future<String?> _read(String key) async {
    if (kIsWeb) return getLocalStorageString(key);
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  /// Test hook: vrati servis u početno stanje.
  @visibleForTesting
  void debugReset() {
    _byId.clear();
    _loaded = false;
    _personalAccountId = null;
  }
}

/// `unawaited` helper — explicit fire-and-forget.
void unawaited(Future<void> _) {}
