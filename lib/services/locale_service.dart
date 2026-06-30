/// Persistira korisnikov odabir UI jezika (jezik "chrome-a" aplikacije:
/// gumbi, naslovi, poruke) — ODVOJENO od per-epizoda jezika SADRŽAJA
/// (vidi services/episode_language.dart + widgets/language_toggle_chip.dart,
/// koji bira HR/EN CDN članak/Magisterium).
///
/// Hrvatski je default i izvorni jezik (template ARB). Odabir se sprema lokalno
/// istim mehanizmom kao tema (ThemeController):
/// Web: localStorage (SharedPreferences puca u dart2js release buildu —
/// vidi CLAUDE.md). Native: SharedPreferences.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import 'local_prefs.dart';

const String _localeKey = 'app_locale';

/// Pristup prijevodima IZVAN build contexta (servisi, callbackovi, modeli).
/// U widgetima UVIJEK koristi `AppLocalizations.of(context)` jer prati
/// Localizations scope; ovo je fallback za kod koji nema BuildContext.
AppLocalizations get appStrings =>
    lookupAppLocalizations(LocaleController.instance.locale);

/// Podržani UI jezici. Hrvatski prvi = default fallback.
const List<Locale> kSupportedLocales = [Locale('hr'), Locale('en')];

class LocaleController extends ChangeNotifier {
  LocaleController._();
  static final LocaleController instance = LocaleController._();

  /// Hrvatski po defaultu dok init() ne učita spremljenu vrijednost.
  Locale _locale = const Locale('hr');
  Locale get locale => _locale;
  bool get isEnglish => _locale.languageCode == 'en';

  /// Učitaj spremljeni jezik. Mora se pozvati u main() prije runApp.
  Future<void> init() async {
    final raw = await _read();
    _locale = switch (raw) {
      'en' => const Locale('en'),
      // Novi korisnik (null) ili bilo što drugo → hrvatski.
      _ => const Locale('hr'),
    };
    notifyListeners();
  }

  /// Prebaci HR ↔ EN i spremi.
  Future<void> toggle() => setLocale(
        isEnglish ? const Locale('hr') : const Locale('en'),
      );

  Future<void> setLocale(Locale locale) async {
    if (locale.languageCode == _locale.languageCode) return;
    _locale = Locale(locale.languageCode);
    notifyListeners();
    await _write(_locale.languageCode);
  }

  Future<String?> _read() async {
    if (kIsWeb) return getLocalStorageString(_localeKey);
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_localeKey);
  }

  Future<void> _write(String value) async {
    if (kIsWeb) {
      setLocalStorageString(_localeKey, value);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, value);
  }
}
