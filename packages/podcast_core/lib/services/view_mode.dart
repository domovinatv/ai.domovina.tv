/// Persistira korisnikov odabir izmedju jednostavnog (/m/) i detaljnog (/v/)
/// prikaza epizode. Cita ga HomeScreen za default rute, a episode ekrani ga
/// upisuju kad korisnik prebaci nacin prikaza preko AppBar toggle-a.
///
/// Web: localStorage (SharedPreferences puca u dart2js release buildu).
/// Native: SharedPreferences.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import 'local_prefs.dart';

const String simpleModeKey = 'simple_mode';

Future<bool?> loadSimpleModePref() async {
  if (kIsWeb) {
    final raw = getLocalStorageString(simpleModeKey);
    if (raw == null) return null;
    return raw == 'true';
  }
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(simpleModeKey);
}

Future<void> saveSimpleModePref(bool value) async {
  if (kIsWeb) {
    setLocalStorageString(simpleModeKey, value.toString());
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(simpleModeKey, value);
}
