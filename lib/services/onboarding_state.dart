/// Tracking koje onboarding momente je korisnik već vidio.
/// localStorage (web) / SharedPreferences (native). Pravi backend swap dodaje
/// upis u `domovina_ai.onboarding_events` za telemetriju.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'local_prefs.dart';

const _kPrefix = 'onb_';
const _kSeenSuffix = '_seen';
const _kDismissedSuffix = '_dismissed';

class OnboardingState {
  static final OnboardingState instance = OnboardingState._();
  OnboardingState._();

  final Map<String, bool> _cache = {};

  Future<bool> hasSeen(String momentId) async {
    final key = '$_kPrefix$momentId$_kSeenSuffix';
    if (_cache.containsKey(key)) return _cache[key]!;
    final v = await _read(key);
    _cache[key] = v;
    return v;
  }

  Future<bool> hasDismissed(String momentId) async {
    final key = '$_kPrefix$momentId$_kDismissedSuffix';
    if (_cache.containsKey(key)) return _cache[key]!;
    final v = await _read(key);
    _cache[key] = v;
    return v;
  }

  Future<void> markSeen(String momentId) async {
    final key = '$_kPrefix$momentId$_kSeenSuffix';
    _cache[key] = true;
    await _write(key, true);
  }

  Future<void> markDismissed(String momentId) async {
    final key = '$_kPrefix$momentId$_kDismissedSuffix';
    _cache[key] = true;
    await _write(key, true);
  }

  Future<void> reset() async {
    _cache.clear();
    final keys = [
      'm1', 'm2', 'm3', 'm4',
    ];
    for (final m in keys) {
      await _write('$_kPrefix$m$_kSeenSuffix', false);
      await _write('$_kPrefix$m$_kDismissedSuffix', false);
    }
  }

  Future<bool> _read(String key) async {
    if (kIsWeb) {
      return getLocalStorageString(key) == 'true';
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? false;
  }

  Future<void> _write(String key, bool value) async {
    if (kIsWeb) {
      setLocalStorageString(key, value.toString());
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }
}
