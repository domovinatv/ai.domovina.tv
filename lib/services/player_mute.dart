/// Stanje „zvuk isključen" za trenutno otvoreni [Player] — i razlog zašto.
///
/// # Zašto uopće postoji
///
/// Browseri dopuštaju autoplay **sa zvukom** samo ako je korisnik već
/// interaktirao s domenom u toj sesiji (Chromium), odnosno ako je element
/// `muted` ili nema audio traku (WebKit). Share link na točan trenutak
/// (`/v/<id>/t/<sec>`) otvoren hladno nema nikakav gesture iza sebe, pa
/// `player.play()` bude odbijen i mi padnemo na **muted autoplay**.
///
/// Iz tog stanja se izlazi ISKLJUČIVO korisnikovim tapom — WebKit izričito
/// pauzira reprodukciju ako se element odmuta bez gesturea. Zato mute nije
/// interni detalj playera nego stanje koje UI mora vidjeti i ponuditi gumb.
///
/// # Zašto singleton, a ne polje ekrana
///
/// Isti mute vidi tri površine odjednom (media_kit traka preko slike, red
/// kontrola u `video_panel.dart`, `_PlayerTab` u `episode_simple_screen.dart`)
/// plus overlay CTA. Prethodna izvedba je stanje provlačila kroz parametre
/// `VideoPanel`-a i **ispustila ga na dvije od šest pozivnih točaka** — upravo
/// one mobilne (video u `endDrawer`), pa na mobitelu unmute nije postojao.
/// Singleton uklanja tu klasu buga.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'media_element_mute_web.dart'
    if (dart.library.io) 'media_element_mute_stub.dart' as platform;

class PlayerMute extends ChangeNotifier {
  PlayerMute._();

  static final PlayerMute instance = PlayerMute._();

  Player? _player;
  StreamSubscription<double>? _volumeSub;
  bool _muted = false;
  bool _autoplayBlocked = false;

  /// Glasnoća prije muteanja (native putanja). Web mute ne dira `volume`.
  double _volumeBeforeMute = 100;

  /// Je li zvuk trenutno ugašen.
  bool get muted => _muted;

  /// True kad je zvuk ugašen zato što je **browser** odbio autoplay sa zvukom,
  /// a ne zato što je korisnik tako htio. Razlika je bitna za UI: samo u tom
  /// slučaju gumb nosi naglašeni „Uključi zvuk" tretman i overlay preko slike.
  bool get autoplayBlocked => _autoplayBlocked;

  /// Ima li itko trenutno otvoren player (kontrole se inače ne crtaju).
  bool get hasPlayer => _player != null;

  /// Veže se na novootvoreni player. Zove [openAndResume]; ekrani ne moraju
  /// ništa raditi osim [detach] u `dispose`.
  void attach(Player player) {
    _volumeSub?.cancel();
    _player = player;
    _muted = false;
    _autoplayBlocked = false;
    _volumeBeforeMute = 100;
    // Zvuk se može promijeniti i mimo nas: media_kitov
    // `MaterialDesktopVolumeButton` (klizač u desktop traci) zove `setVolume`,
    // a to na webu usput **skida** `muted` flag. Bez ovog sinkroniziranja bi
    // naš gumb pokazivao mute dok zvuk već svira.
    _volumeSub = player.stream.volume.listen((volume) {
      final actual = kIsWeb
          ? platform.elementMuted(player) ?? (volume == 0)
          : volume == 0;
      if (actual == _muted) return;
      _muted = actual;
      if (!actual) _autoplayBlocked = false;
      notifyListeners();
    });
    notifyListeners();
  }

  /// Odvezuje se, ali samo ako je [player] doista onaj vezani — brza interna
  /// navigacija zna disposeati stari player NAKON što je novi već attachan.
  void detach(Player player) {
    if (!identical(_player, player)) return;
    _volumeSub?.cancel();
    _volumeSub = null;
    _player = null;
    _muted = false;
    _autoplayBlocked = false;
    notifyListeners();
  }

  /// Muteanje kao posljedica browserove autoplay politike (ne korisnikov izbor).
  Future<void> muteForAutoplay() async {
    await _apply(true);
    _autoplayBlocked = true;
    notifyListeners();
  }

  /// Korisnikov izbor — briše [autoplayBlocked] u oba smjera (kad ga je jednom
  /// riješio tapom, CTA se više ne vraća).
  Future<void> setMuted(bool value) async {
    await _apply(value);
    _autoplayBlocked = false;
    notifyListeners();
  }

  Future<void> toggle() => setMuted(!_muted);

  Future<void> _apply(bool value) async {
    final p = _player;
    if (p == null) {
      _muted = value;
      return;
    }
    if (value && !_muted) _volumeBeforeMute = p.state.volume;
    final restore = _volumeBeforeMute > 0 ? _volumeBeforeMute : 100.0;

    // Na webu prvo pravi `muted` property (jedini koji radi na iOS-u); ako
    // element nije dohvatljiv, padamo na volume — bolje išta nego ništa.
    if (kIsWeb && platform.setElementMuted(p, value)) {
      _muted = value;
      return;
    }
    await p.setVolume(value ? 0 : restore);
    _muted = value;
  }
}
