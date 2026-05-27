/// Per-episode jezik za prikaz AI-generiranog sadrzaja.
///
/// HR = original (uvijek dostupan). EN = paralelni prijevod iz pipeline-a,
/// dostupan samo kad `summary.en.json`/`article.en.json` postoje na CDN-u.
///
/// Audio uvijek ostaje hrvatski — toggle utjece samo na tekst.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_prefs.dart';

enum EpisodeLanguage { hr, en }

/// Helper za fallback HR ako EN polje nije popunjeno (parcijalni prijevod).
String pickLang(EpisodeLanguage lang, String hr, String? en) {
  if (lang == EpisodeLanguage.en && en != null && en.isNotEmpty) return en;
  return hr;
}

/// Helper za list polja s istom semantikom.
List<String> pickLangList(
    EpisodeLanguage lang, List<String> hr, List<String>? en) {
  if (lang == EpisodeLanguage.en && en != null && en.isNotEmpty) return en;
  return hr;
}

const _kPreferredLangKey = 'preferred_lang';

/// Sticky pref — vraca null ako korisnik nikad nije birao (defaultaj na HR).
Future<EpisodeLanguage?> loadPreferredLanguage() async {
  String? raw;
  if (kIsWeb) {
    raw = getLocalStorageString(_kPreferredLangKey);
  } else {
    final prefs = await SharedPreferences.getInstance();
    raw = prefs.getString(_kPreferredLangKey);
  }
  if (raw == 'en') return EpisodeLanguage.en;
  if (raw == 'hr') return EpisodeLanguage.hr;
  return null;
}

Future<void> savePreferredLanguage(EpisodeLanguage lang) async {
  final value = lang.name; // 'hr' ili 'en'
  if (kIsWeb) {
    setLocalStorageString(_kPreferredLangKey, value);
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kPreferredLangKey, value);
}

/// InheritedWidget za current EpisodeLanguage — citaju ga svi widgeti
/// koji renderiraju lokalizirani sadrzaj. Re-renderira children kad se
/// jezik mijenja kroz toggle.
class EpisodeLanguageScope extends InheritedWidget {
  final EpisodeLanguage language;
  final bool hasTranslationEn;

  const EpisodeLanguageScope({
    super.key,
    required this.language,
    required this.hasTranslationEn,
    required super.child,
  });

  static EpisodeLanguage of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<EpisodeLanguageScope>();
    return scope?.language ?? EpisodeLanguage.hr;
  }

  static bool hasEnOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<EpisodeLanguageScope>();
    return scope?.hasTranslationEn ?? false;
  }

  @override
  bool updateShouldNotify(EpisodeLanguageScope oldWidget) =>
      oldWidget.language != language ||
      oldWidget.hasTranslationEn != hasTranslationEn;
}
