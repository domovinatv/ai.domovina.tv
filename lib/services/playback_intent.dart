/// Namjera reprodukcije — odgovor na pitanje „želi li korisnik da ovo svira?".
///
/// Uvedeno 2026-07-25 (plan `docs/plans/2026-07-25-background-playback-control.md`)
/// jer je izričita korisnikova Pauza bila poništiva: zatvaranje video drawera
/// swipe-rightom i odlazak appa u pozadinu bezuvjetno su zvali `play()`.
///
/// Zašto stream, a ne omatanje naših gumba: `media_kit` ima `playAndPauseOnTap`,
/// `MaterialDesktopPlayOrPauseButton` i tipkovničke kratice koje zovu
/// `player.playOrPause()` interno, bez callbacka. Jedini izvor istine koji
/// hvata SVE putanje je `player.stream.playing`.
///
/// Problem s tim izvorom: framework tranzicije (dispose `Video` widgeta pri
/// zatvaranju drawera, media_kitova SurfaceView auto-pauza kad app ode u
/// pozadinu) emitiraju isti `playing:false` kao i korisnikov tap. Zato pozivatelj
/// NEPOSREDNO prije poznate tranzicije otvori prozor tolerancije preko
/// [suppress] — unutar njega `false` ne gasi namjeru.
///
/// Čista logika bez ovisnosti na `media_kit` (prima stream + getter, ne Player)
/// da bude unit-testabilna — vidi `test/playback_intent_test.dart`.
library;

import 'dart:async';

class PlaybackIntent {
  /// [playingStream] i [isPlayingNow] umjesto samog Playera → testabilno
  /// bez media_kita (u testu StreamController + zatvorena varijabla).
  PlaybackIntent({
    required Stream<bool> playingStream,
    required bool Function() isPlayingNow,
    bool initiallyWants = true,
  })  : _isPlayingNow = isPlayingNow,
        _wantsPlayback = initiallyWants {
    _sub = playingStream.listen(_onPlayingChanged);
  }

  final bool Function() _isPlayingNow;

  StreamSubscription<bool>? _sub;

  /// Aktivan dok je prozor tolerancije otvoren; `null`/neaktivan inače.
  Timer? _suppressTimer;

  bool _wantsPlayback;

  /// True dok korisnik nije sam pauzirao.
  bool get wantsPlayback => _wantsPlayback;

  /// Otvori prozor tolerancije NEPOSREDNO prije poznate framework
  /// tranzicije (zatvaranje drawera, odlazak u pozadinu). Unutar prozora
  /// `playing:false` NE gasi namjeru — jer ga nije izazvao korisnik.
  ///
  /// Ponovni poziv restarta prozor. Prozor NE uskrsava već ugašenu namjeru —
  /// korisnikova pauza prije poziva ostaje na snazi.
  void suppress({Duration window = const Duration(milliseconds: 800)}) {
    _suppressTimer?.cancel();
    _suppressTimer = Timer(window, () {});
  }

  /// Namjera postoji, ali player stvarno ne svira → treba ga vratiti.
  bool get shouldResume => _wantsPlayback && !_isPlayingNow();

  /// Svaki prijelaz iz streama ažurira namjeru 1:1, OSIM `false` unutar
  /// otvorenog [suppress] prozora — to je framework, ne korisnik.
  void _onPlayingChanged(bool playing) {
    if (playing) {
      _wantsPlayback = true;
      return;
    }
    // Prozor namjerno NE zatvaramo na `true`: nakon našeg resume-a može
    // stići još jedna framework pauza iz iste tranzicije (npr. druga faza
    // SurfaceView teardowna). Prozor istječe samo po vremenu.
    if (_suppressTimer?.isActive ?? false) return;
    _wantsPlayback = false;
  }

  void dispose() {
    _suppressTimer?.cancel();
    _suppressTimer = null;
    _sub?.cancel();
    _sub = null;
  }
}
