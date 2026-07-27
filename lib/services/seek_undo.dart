/// Undo nakon ručnog skoka po timelineu — „vrati me gdje sam bio".
///
/// Uvedeno 2026-07-27 (plan `docs/plans/2026-07-27-playback-overhaul.md`) jer
/// slučajan swipe po seek baru nepovratno briše podatak dokle je korisnik
/// stigao: nema povijesti, a `watch_progress` je već prepisan.
///
/// Zašto stream, a ne omatanje naših slidera: seek ide kroz najmanje pet
/// putanja bez zajedničkog callbacka (`_SeekBar.onChangeEnd` u
/// `video_panel.dart`, slider u `episode_simple_screen.dart`,
/// `seekOnDoubleTap` unutar media_kita, tipkovničke kratice J/L/←/→ u
/// `episode_video.dart`, `seekto` s lock screena). Jedini izvor istine koji
/// hvata SVE putanje je `player.stream.position` — isti zaključak i isto
/// rješenje kao za pauzu u `services/playback_intent.dart`.
///
/// Programske skokove (resume pri otvaranju epizode, tap na poglavlje — to je
/// odluka D2, sam Undo seek) pozivatelj NEPOSREDNO prije najavi kroz
/// [suppress]; unutar tog prozora skok se ne nudi za poništavanje.
///
/// Čista logika bez ovisnosti na `media_kit` (prima stream, ne Player) da bude
/// unit-testabilna — vidi `test/seek_undo_test.dart`.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

class SeekUndo {
  /// [positionStream] umjesto samog Playera → testabilno bez media_kita
  /// (u testu običan StreamController).
  ///
  /// [jumpThreshold] mora ostati znatno iznad prirodnog pomaka između dva
  /// eventa: `player.stream.position` fira ~5×/s, pa je pri brzini 2,0×
  /// prirodni korak ~0,4 s. Dvije sekunde su sigurne; ne spuštati ispod 1 s.
  ///
  /// [ttl] je koliko dugo ponuda stoji na ekranu prije nego se sama ugasi.
  SeekUndo({
    required Stream<Duration> positionStream,
    this.jumpThreshold = const Duration(seconds: 2),
    this.ttl = const Duration(seconds: 8),
  }) {
    _sub = positionStream.listen(_onPosition);
  }

  final Duration jumpThreshold;
  final Duration ttl;

  StreamSubscription<Duration>? _sub;

  /// Aktivan dok je prozor tolerancije otvoren; neaktivan/null inače.
  Timer? _suppressTimer;

  /// Gasi ponudu nakon [ttl].
  Timer? _expiryTimer;

  /// Zadnja viđena pozicija — kandidat za povratak.
  Duration? _lastPosition;

  final ValueNotifier<Duration?> _undoTarget = ValueNotifier<Duration?>(null);

  /// Pozicija na koju Undo vraća, ili `null` kad ponude nema.
  ValueListenable<Duration?> get undoTarget => _undoTarget;

  /// Otvori prozor tolerancije NEPOSREDNO prije poznatog programskog seeka
  /// (resume pri otvaranju, tap na poglavlje, sam Undo seek). Skok unutar
  /// prozora se ne nudi — nije ga izazvao korisnik povlačenjem timelinea.
  ///
  /// Ponovni poziv restarta prozor.
  void suppress({Duration window = const Duration(milliseconds: 1200)}) {
    _suppressTimer?.cancel();
    _suppressTimer = Timer(window, () {});
  }

  /// Korisnik je prihvatio ponudu. Gasi je i otvara prozor tolerancije, jer
  /// seek koji pozivatelj odmah izvodi inače proizvede novu ponudu („Undo
  /// nudi Undo").
  void consume() {
    _clearOffer();
    suppress();
  }

  void _onPosition(Duration position) {
    final last = _lastPosition;
    _lastPosition = position;
    if (last == null) return;

    final delta = (position - last).abs();
    if (delta <= jumpThreshold) return;

    // Buffering stall ne pomiče poziciju pa ovamo ni ne dolazi; ono što dolazi
    // je stvarni skok — ostaje pitanje je li naš ili korisnikov.
    if (_suppressTimer?.isActive ?? false) {
      // Programska navigacija (poglavlje, resume) poništava zatečenu ponudu:
      // njezino sidro se odnosi na prethodnu radnju i vratilo bi korisnika
      // nekamo treće.
      _clearOffer();
      return;
    }

    // Uzastopni ručni skokovi (korisnik traži gdje je stao) drže PRVO sidro —
    // ono je jedino mjesto na koje se korisnik želi vratiti — a samo produžuju
    // ponudu.
    if (_undoTarget.value == null) _undoTarget.value = last;
    _expiryTimer?.cancel();
    _expiryTimer = Timer(ttl, _clearOffer);
  }

  void _clearOffer() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _undoTarget.value = null;
  }

  void dispose() {
    _suppressTimer?.cancel();
    _suppressTimer = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _sub?.cancel();
    _sub = null;
    _undoTarget.dispose();
  }
}
