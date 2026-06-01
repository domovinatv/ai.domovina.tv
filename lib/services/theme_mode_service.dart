/// Persistira korisnikov odabir izmedju tamne i svijetle teme.
///
/// Default za NOVE korisnike (nema spremljene vrijednosti) je TAMNA tema —
/// editorial dark look izgleda bolje za vecinu sadrzaja. Korisnik moze
/// prebaciti na svijetlu preko sunce/mjesec ikone u home app baru
/// (vidi widgets/theme_toggle_button.dart). Odluka se sprema lokalno.
///
/// Web: localStorage (SharedPreferences puca u dart2js release buildu —
/// vidi CLAUDE.md). Native: SharedPreferences. Isti pattern kao view_mode.dart.
///
/// Android TV ignorira ovo i uvijek forsira dark (vidi main.dart / TvMode).
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_prefs.dart';

const String _themeModeKey = 'theme_mode';

class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  /// Tamna po defaultu dok init() ne ucita spremljenu vrijednost.
  ThemeMode _mode = ThemeMode.dark;
  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  /// Ucitaj spremljenu temu. Mora se pozvati u main() prije runApp.
  Future<void> init() async {
    final raw = await _read();
    _mode = switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      // Novi korisnik (null) ili legacy 'system' → tamna tema po defaultu.
      _ => ThemeMode.dark,
    };
    notifyListeners();
  }

  /// Prebaci tamno ↔ svijetlo i spremi.
  Future<void> toggle() =>
      setMode(isDark ? ThemeMode.light : ThemeMode.dark);

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    await _write(mode == ThemeMode.light ? 'light' : 'dark');
  }

  Future<String?> _read() async {
    if (kIsWeb) return getLocalStorageString(_themeModeKey);
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_themeModeKey);
  }

  Future<void> _write(String value) async {
    if (kIsWeb) {
      setLocalStorageString(_themeModeKey, value);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, value);
  }
}
