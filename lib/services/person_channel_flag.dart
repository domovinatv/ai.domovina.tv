/// Feature flag za "virtualne kanale" (osoba izgleda i ponaša se kao kanal).
///
/// **Runtime**, ne compile-time — web je jedan bundle za sve korisnike, pa
/// `--dart-define` ne bi mogao upaliti feature samo timu (rollout §7 u
/// `docs/plans/virtualni-kanali.md`).
///
/// - `?vk=1` u URL-u → pali i **pamti** (sljedeći put ne treba parametar).
/// - `?vk=0` → gasi i pamti (rollback bez redeploya, bez ijednog deploya).
/// - bez parametra → spremljena vrijednost, default **ON** od 4.9.2026.
///
/// Default je bio OFF od uvođenja (v2.0.122) dok backend nije imao što
/// isporučiti: `/api/persons` je vraćao 404, a `/api/person/:slug` nije slao
/// `is_virtual_channel`, pa se kanal-forma nije mogla upaliti ni s `?vk=1`.
/// Backend je isporučen 4.9.2026. (`domovina-rag`, `/api/persons` = 74 osobe)
/// i feature je pušten svima.
///
/// `?vk=0` i dalje radi i **preživi** ovu promjenu: tko je flag ikad izričito
/// ugasio, ima spremljenu `'0'` i ostaje bez featurea. To je i rollback put —
/// gašenje za pojedinog korisnika ne traži redeploy.
///
/// Perzistencija: `window.localStorage` na webu (SharedPreferences puca u
/// dart2js release buildu — vidi CLAUDE.md), `SharedPreferences` na nativeu.
/// Isti oblik kao `playback_speed.dart` (lazy `init()`, `_loaded` guard protiv
/// utrke između čitanja i settera).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_prefs.dart';

const String _personChannelFlagKey = 'person_channel_flag';

/// Ime query parametra kojim se flag pali/gasi.
const String kPersonChannelFlagParam = 'vk';

/// Vrijednost kad korisnik nije ništa odlučio. ON od 4.9.2026.
const bool _kDefaultOn = true;

class PersonChannelFlag extends ChangeNotifier {
  PersonChannelFlag._();
  static final PersonChannelFlag instance = PersonChannelFlag._();

  bool _on = _kDefaultOn;
  bool _loaded = false;
  Future<void>? _loading;

  /// Je li feature upaljen. Lazy: prvi pristup pokrene učitavanje i javi
  /// listenerima kad vrijednost stigne; dotle vraća default ([_kDefaultOn]).
  ///
  /// Otkako je default ON, ovo znači da korisnik koji je flag ugasio vidi
  /// kanal-formu jedan frame prije nego čitanje iz localStorage stigne. To je
  /// prihvaćeno: obrnuto (default OFF uz spremljeni ON) bi svima koji feature
  /// IMAJU pokazalo bljesak starog izgleda pri svakom učitavanju.
  bool get isOn {
    unawaited(init());
    return _on;
  }

  /// Učitaj stanje (URL parametar pobjeđuje spremljenu vrijednost).
  /// Idempotentno — višestruki pozivi dijele isti Future.
  Future<void> init() => _loading ??= _load();

  /// Eksplicitno paljenje/gašenje (npr. iz account ekrana). Perzistira.
  Future<void> setOn(bool value) async {
    // Korisnikov odabir pobjeđuje eventualno čitanje u letu.
    _loaded = true;
    _loading ??= Future<void>.value();
    if (value != _on) {
      _on = value;
      notifyListeners();
    }
    await _write(value);
  }

  Future<void> _load() async {
    final override = overrideFromUri(kIsWeb ? Uri.base : null);
    if (override != null) {
      _loaded = true;
      if (override != _on) {
        _on = override;
        notifyListeners();
      }
      await _write(override);
      return;
    }
    final raw = await _read();
    // Utrka: setOn() je stigao prije nego se čitanje vratilo.
    if (_loaded) return;
    _loaded = true;
    final value = decode(raw);
    if (value == _on) return;
    _on = value;
    notifyListeners();
  }

  /// `?vk=1` → true, `?vk=0` → false, sve ostalo (i nema parametra) → null.
  /// Čista funkcija — testira se bez browsera.
  @visibleForTesting
  static bool? overrideFromUri(Uri? uri) {
    if (uri == null) return null;
    final raw = uri.queryParameters[kPersonChannelFlagParam];
    if (raw == null) return null;
    switch (raw.trim().toLowerCase()) {
      case '1':
      case 'true':
      case 'on':
        return true;
      case '0':
      case 'false':
      case 'off':
        return false;
      default:
        return null;
    }
  }

  /// Spremljena vrijednost → bool.
  ///
  /// Samo izričito spremljeno gašenje (`'0'`/`'false'`, što upiše `?vk=0` ili
  /// prekidač u `/account`) drži feature ugašenim. Ništa spremljeno, ili
  /// pokvarena vrijednost, znači „korisnik nije odlučio" → default.
  @visibleForTesting
  static bool decode(String? raw) {
    if (raw == null) return _kDefaultOn;
    switch (raw.trim().toLowerCase()) {
      case '0':
      case 'false':
      case 'off':
        return false;
      case '1':
      case 'true':
      case 'on':
        return true;
      default:
        return _kDefaultOn;
    }
  }

  Future<String?> _read() async {
    if (kIsWeb) return getLocalStorageString(_personChannelFlagKey);
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_personChannelFlagKey);
  }

  Future<void> _write(bool value) async {
    final encoded = value ? '1' : '0';
    if (kIsWeb) {
      setLocalStorageString(_personChannelFlagKey, encoded);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_personChannelFlagKey, encoded);
  }

  /// Test hook: vrati flag u početno stanje (default, neučitan).
  @visibleForTesting
  void debugReset() {
    _on = _kDefaultOn;
    _loaded = false;
    _loading = null;
  }
}
