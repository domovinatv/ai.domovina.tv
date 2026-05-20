/// Favoriti — lokalni set episode ID-eva. Jasno označeno kao on-device.
/// Backend swap koristi `domovina_ai.favorites` s owner_id (account scope).
library;

import 'dart:convert';
import 'package:flutter/foundation.dart' show ChangeNotifier, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'local_prefs.dart';

const _kKey = 'favorites_v1';

class FavoritesService extends ChangeNotifier {
  static final FavoritesService instance = FavoritesService._();
  FavoritesService._();

  final Set<String> _set = {};
  bool _loaded = false;

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
    return wasAdded;
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
