/// Defenderi za `PlaybackIntent` (2026-07-25, plan
/// `docs/plans/2026-07-25-background-playback-control.md`).
///
/// Štite ugovor zbog kojeg servis postoji: **izričitu korisnikovu pauzu ne
/// poništava ništa**, ali framework pauza (dispose `Video` widgeta pri
/// zatvaranju drawera, media_kitova SurfaceView auto-pauza u pozadini) unutar
/// `suppress()` prozora ne smije prekinuti reprodukciju.
library;

import 'dart:async';

import 'package:domovina_ai/services/playback_intent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Kratki prozor da testovi ne čekaju stvarnih 800 ms; margina do
  /// [afterWindow] je namjerno velika (flake guard na sporom CI-u).
  const window = Duration(milliseconds: 40);
  const afterWindow = Duration(milliseconds: 200);

  late StreamController<bool> playingController;
  late bool playingNow;
  PlaybackIntent? intent;

  setUp(() {
    playingController = StreamController<bool>();
    playingNow = true; // svira u trenutku instanciranja (kao nakon openAndResume)
  });

  tearDown(() async {
    intent?.dispose();
    intent = null;
    await playingController.close();
  });

  PlaybackIntent build({bool initiallyWants = true}) {
    return intent = PlaybackIntent(
      playingStream: playingController.stream,
      isPlayingNow: () => playingNow,
      initiallyWants: initiallyWants,
    );
  }

  /// Emitira stanje playera i pusti event loop da ga dostavi listeneru.
  Future<void> emitPlaying(bool value) async {
    playingNow = value;
    playingController.add(value);
    await Future<void>.delayed(Duration.zero);
  }

  test('1 — korisnikova pauza bez prozora gasi namjeru', () async {
    final i = build();
    expect(i.wantsPlayback, isTrue);

    await emitPlaying(false);

    expect(i.wantsPlayback, isFalse);
    expect(i.shouldResume, isFalse);
  });

  test('2 — framework pauza unutar suppress prozora ne gasi namjeru', () async {
    final i = build();

    i.suppress(window: window);
    await emitPlaying(false);

    expect(i.wantsPlayback, isTrue);
    expect(playingNow, isFalse);
    expect(i.shouldResume, isTrue, reason: 'pozivatelj mora vratiti play()');
  });

  test('3 — pauza NAKON isteka prozora gasi namjeru', () async {
    final i = build();

    i.suppress(window: window);
    await Future<void>.delayed(afterWindow);
    await emitPlaying(false);

    expect(i.wantsPlayback, isFalse);
    expect(i.shouldResume, isFalse);
  });

  test('4 — prozor ne uskrsava već ugašenu namjeru', () async {
    final i = build();

    await emitPlaying(false); // korisnik stisne Pauzu
    expect(i.wantsPlayback, isFalse);

    i.suppress(window: window); // pa krene tranzicija (swipe / home)
    await emitPlaying(false); // framework pauza

    expect(i.wantsPlayback, isFalse);
    expect(i.shouldResume, isFalse);
  });

  test('playing:true vraća namjeru (korisnik ponovno pokrene)', () async {
    final i = build();

    await emitPlaying(false);
    expect(i.wantsPlayback, isFalse);

    await emitPlaying(true);
    expect(i.wantsPlayback, isTrue);
    expect(i.shouldResume, isFalse, reason: 'već svira, nema što vraćati');
  });

  test('prozor prima više framework pauza iz iste tranzicije', () async {
    final i = build();

    i.suppress(window: window);
    await emitPlaying(false); // SurfaceView teardown
    await emitPlaying(true); // naš resume
    await emitPlaying(false); // druga faza teardowna, prozor još otvoren

    expect(i.wantsPlayback, isTrue);
    expect(i.shouldResume, isTrue);
  });

  test('ponovni suppress restarta prozor', () async {
    final i = build();

    i.suppress(window: window);
    await Future<void>.delayed(const Duration(milliseconds: 25));
    i.suppress(window: window);
    await Future<void>.delayed(const Duration(milliseconds: 25));
    await emitPlaying(false); // 50 ms od prvog poziva, 25 ms od drugog

    expect(i.wantsPlayback, isTrue);
  });

  test('initiallyWants: false → shouldResume je false i dok player stoji',
      () async {
    final i = build(initiallyWants: false);
    playingNow = false;

    expect(i.wantsPlayback, isFalse);
    expect(i.shouldResume, isFalse);
  });

  test('dispose prestaje slušati stream', () async {
    final i = build();

    i.dispose();
    intent = null;
    await emitPlaying(false);

    expect(i.wantsPlayback, isTrue, reason: 'nakon disposea ništa ne stiže');
  });
}
