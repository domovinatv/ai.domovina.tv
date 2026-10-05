/// Persistira korisnikov odabir prikaza titlova (CC) u video playeru.
///
/// Web: localStorage (SharedPreferences puca u dart2js release buildu).
/// Native: SharedPreferences.
library;

import 'package:flutter/foundation.dart' show ValueNotifier, kIsWeb;
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

/// Je li CC uključen — jedno stanje za cijelu aplikaciju.
///
/// Singleton, ne prop ni `State` polje: isti titl crtaju overlay preko slike
/// (i njegova kopija u fullscreen ruti), CC gumb u traci i [SubtitleStrip]
/// ispod playera na mobitelu u portraitu, koji živi IZVAN `EpisodeVideo`.
/// Isto pravilo kao `PlaybackSpeed`/`PlayerMute` (CLAUDE.md, „stanje kontrole
/// ide kroz singleton").
class SubtitlesEnabled extends ValueNotifier<bool> {
  SubtitlesEnabled._() : super(false) {
    loadSubtitlesPref().then((saved) {
      if (saved != null) value = saved;
    });
  }

  static final SubtitlesEnabled instance = SubtitlesEnabled._();

  void toggle() {
    value = !value;
    saveSubtitlesPref(value);
  }
}
