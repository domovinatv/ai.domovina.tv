/// Per-episode jezik za prikaz AI-generiranog sadrzaja.
///
/// HR = original (uvijek dostupan). EN = paralelni prijevod iz pipeline-a,
/// dostupan samo kad `summary.en.json`/`article.en.json` postoje na CDN-u.
///
/// Audio uvijek ostaje hrvatski — toggle utjece samo na tekst.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
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

/// Zapamti izbor jezika sadržaja.
///
/// Osvježava i `PreferredEpisodeLanguage` — inače bi singleton do restarta
/// aplikacije nosio staru vrijednost, pa bi share link s kartice u railu i
/// dalje nudio prethodni jezik. Pet call-siteova piše preferenciju; da je
/// osvježavanje na njima, prvi novi bi ga zaboravio.
Future<void> savePreferredLanguage(EpisodeLanguage lang) async {
  PreferredEpisodeLanguage.instance._adopt(lang);
  await _writePreferredLanguage(lang);
}

Future<void> _writePreferredLanguage(EpisodeLanguage lang) async {
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

/// Preferirani jezik sadržaja, dostupan **sinkrono**.
///
/// `loadPreferredLanguage()` je Future, pa ga mjesta koja moraju odlučiti
/// odmah — a ne u `initState` — ne mogu koristiti. Konkretno: „Kopiraj
/// poveznicu" na kartici epizode u railu, gdje nema `EpisodeLanguageScope`
/// jer kartica nije unutar episode ekrana.
///
/// Isti oblik kao `PlaybackSpeed`: lazy `init()`, `_loaded` guard protiv utrke
/// između čitanja i settera. Na webu je čitanje ionako sinkrono
/// (`localStorage`), pa je vrijednost točna i bez `init()`; na nativeu je
/// `SharedPreferences` async, zato `main()` zove `init()` prije `runApp`.
class PreferredEpisodeLanguage extends ChangeNotifier {
  PreferredEpisodeLanguage._();
  static final PreferredEpisodeLanguage instance = PreferredEpisodeLanguage._();

  EpisodeLanguage? _value;
  bool _loaded = false;
  Future<void>? _loading;

  /// Korisnikov izbor, ili null ako nikad nije birao (pozivatelj defaultira
  /// na HR). Null i „izabrao HR" se NE smiju stopiti: prvo znači „ne znamo",
  /// drugo je odluka.
  EpisodeLanguage? get value {
    if (kIsWeb && !_loaded) {
      // Web: sinkrono čitanje, nema razloga čekati init().
      final raw = getLocalStorageString(_kPreferredLangKey);
      _value = raw == 'en'
          ? EpisodeLanguage.en
          : (raw == 'hr' ? EpisodeLanguage.hr : null);
      _loaded = true;
      return _value;
    }
    unawaited(init());
    return _value;
  }

  /// Učitaj spremljenu vrijednost. Idempotentno — višestruki pozivi dijele
  /// isti Future.
  Future<void> init() => _loading ??= _load();

  Future<void> _load() async {
    final v = await loadPreferredLanguage();
    // Utrka: `remember()` je stigao prije nego se čitanje vratilo.
    if (_loaded) return;
    _loaded = true;
    if (v == _value) return;
    _value = v;
    notifyListeners();
  }

  /// Zapamti korisnikov izbor (i u memoriji i u storageu).
  Future<void> remember(EpisodeLanguage lang) async {
    _adopt(lang);
    await _writePreferredLanguage(lang);
  }

  /// Preuzmi vrijednost u memoriju bez pisanja u storage. Postavlja `_loaded`
  /// da čitanje u letu ne pregazi korisnikov svjež izbor.
  void _adopt(EpisodeLanguage lang) {
    _loaded = true;
    _loading ??= Future<void>.value();
    if (_value == lang) return;
    _value = lang;
    notifyListeners();
  }

  /// Samo za testove — vrati singleton u „ništa nije učitano".
  @visibleForTesting
  void resetForTest() {
    _value = null;
    _loaded = false;
    _loading = null;
  }
}
