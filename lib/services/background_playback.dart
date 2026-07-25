/// Korisnikov prekidač „Reprodukcija u pozadini" (/account).
///
/// Odgovara na jedno pitanje: nastavlja li ono što svira raditi kad app/tab
/// izgubi prvi plan? Uključeno (default) → odlazak u pozadinu ne prekida
/// reprodukciju; isključeno → aktivno pauziramo. Ponašanje je namjerno isto
/// na webu i nativeu.
///
/// Izričitu korisnikovu pauzu ovaj pref NE dira — nju čuva PlaybackIntent
/// (services/playback_intent.dart).
///
/// Web: localStorage (SharedPreferences puca u dart2js release buildu —
/// vidi CLAUDE.md). Native: SharedPreferences. Isti pattern kao
/// theme_mode_service.dart.
///
/// `init()` se smije (i preporučeno je) pozvati iz main() prije runApp, ali
/// NIJE obavezan: prvi pristup `enabled` sam pokrene učitavanje i javi
/// listenerima kad vrijednost stigne.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_prefs.dart';

const String _backgroundPlaybackKey = 'background_playback';
const String _on = 'on';
const String _off = 'off';

class BackgroundPlayback extends ChangeNotifier {
  BackgroundPlayback._();
  static final BackgroundPlayback instance = BackgroundPlayback._();

  /// Uključeno dok se spremljena vrijednost ne učita (bez regresije za
  /// postojeće slušatelje koji nikad nisu dirali prekidač).
  bool _enabled = true;

  /// True čim je vrijednost poznata — bilo iz storagea, bilo iz setEnabled().
  bool _loaded = false;

  Future<void>? _loading;

  /// Smije li reprodukcija preživjeti odlazak u pozadinu.
  ///
  /// Lazy: ako init() nije pozvan, prvi pristup pokrene čitanje u pozadini i
  /// notifyListeners() kad vrijednost stigne. Dotle vraća default (true).
  bool get enabled {
    unawaited(init());
    return _enabled;
  }

  /// Učitaj spremljenu vrijednost. Idempotentno — višestruki pozivi dijele
  /// isti Future.
  Future<void> init() => _loading ??= _load();

  Future<void> setEnabled(bool value) async {
    // Korisnikov odabir pobjeđuje eventualno čitanje u letu.
    _loaded = true;
    _loading ??= Future<void>.value();
    if (value == _enabled) return;
    _enabled = value;
    notifyListeners();
    await _write(value ? _on : _off);
  }

  Future<void> _load() async {
    final raw = await _read();
    // Utrka: setEnabled() je stigao prije nego se čitanje vratilo.
    if (_loaded) return;
    _loaded = true;
    final value = raw == null ? true : raw != _off;
    if (value == _enabled) return;
    _enabled = value;
    notifyListeners();
  }

  Future<String?> _read() async {
    if (kIsWeb) return getLocalStorageString(_backgroundPlaybackKey);
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_backgroundPlaybackKey);
  }

  Future<void> _write(String value) async {
    if (kIsWeb) {
      setLocalStorageString(_backgroundPlaybackKey, value);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_backgroundPlaybackKey, value);
  }
}
