/// Persistira korisnikov odabir prikaza titlova (CC) u video playeru.
///
/// Web: localStorage (SharedPreferences puca u dart2js release buildu).
/// Native: SharedPreferences.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import 'local_prefs.dart';

const String subtitlesEnabledKey = 'subtitles_enabled';

Future<bool?> loadSubtitlesPref() async {
  if (kIsWeb) {
    final raw = getLocalStorageString(subtitlesEnabledKey);
    if (raw == null) return null;
    return raw == 'true';
  }
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(subtitlesEnabledKey);
}

Future<void> saveSubtitlesPref(bool value) async {
  if (kIsWeb) {
    setLocalStorageString(subtitlesEnabledKey, value.toString());
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(subtitlesEnabledKey, value);
}
