/// Defenderi za `SeekUndo` (2026-07-27, plan
/// `docs/plans/2026-07-27-playback-overhaul.md`).
///
/// Štite ugovor zbog kojeg servis postoji: **ručni skok po timelineu mora biti
/// poništiv**, a programski skok (resume pri otvaranju, tap na poglavlje —
/// odluka D2, sam Undo seek) i prirodni tijek reprodukcije ne smiju ponuditi
/// Undo.
library;

import 'dart:async';

import 'package:domovina_ai/services/seek_undo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Kratki prozori da testovi ne čekaju stvarnih 1,2 s / 8 s; margina do
  /// [afterWindow] je namjerno velika (flake guard na sporom CI-u).
  const window = Duration(milliseconds: 40);
  const ttl = Duration(milliseconds: 60);
  const afterWindow = Duration(milliseconds: 200);

  late StreamController<Duration> positionController;
  SeekUndo? undo;

  setUp(() {
    positionController = StreamController<Duration>();
  });

  tearDown(() async {
    undo?.dispose();
    undo = null;
    await positionController.close();
  });

  SeekUndo build() {
    return undo = SeekUndo(
      positionStream: positionController.stream,
      jumpThreshold: const Duration(seconds: 2),
      ttl: ttl,
    );
  }

  /// Emitira poziciju playera i pusti event loop da je dostavi listeneru.
  Future<void> emit(Duration position) async {
    positionController.add(position);
    await Future<void>.delayed(Duration.zero);
  }

  /// Prirodni tijek: ~5 eventa u sekundi, korak 0,2 s.
  Future<void> emitNatural(Duration from, {int steps = 10}) async {
    for (var i = 1; i <= steps; i++) {
      await emit(from + Duration(milliseconds: 200 * i));
    }
  }

  test('1 — prirodni tijek ne pali ponudu', () async {
    final u = build();

    await emit(const Duration(minutes: 5));
    await emitNatural(const Duration(minutes: 5));

    expect(u.undoTarget.value, isNull);
  });

  test('2 — prirodni tijek pri 2,0× (korak 0,4 s) ne pali ponudu', () async {
    final u = build();

    await emit(const Duration(minutes: 5));
    for (var i = 1; i <= 10; i++) {
      await emit(const Duration(minutes: 5) + Duration(milliseconds: 400 * i));
    }

    expect(u.undoTarget.value, isNull);
  });

  test('3 — skok naprijed pali ponudu na prethodnu poziciju', () async {
    final u = build();

    await emit(const Duration(minutes: 5));
    await emit(const Duration(minutes: 5, seconds: 1)); // još prirodno
    await emit(const Duration(minutes: 42)); // scrub

    expect(u.undoTarget.value, const Duration(minutes: 5, seconds: 1));
  });

  test('4 — skok natrag pali ponudu', () async {
    final u = build();

    await emit(const Duration(minutes: 42));
    await emit(const Duration(minutes: 5)); // scrub unatrag

    expect(u.undoTarget.value, const Duration(minutes: 42));
  });

  test('5 — skok unutar suppress prozora ne pali (tap na poglavlje)', () async {
    final u = build();

    await emit(const Duration(minutes: 5));
    u.suppress(window: window);
    await emit(const Duration(minutes: 42));

    expect(u.undoTarget.value, isNull);
  });

  test('6 — skok NAKON isteka prozora pali', () async {
    final u = build();

    await emit(const Duration(minutes: 5));
    u.suppress(window: window);
    await Future<void>.delayed(afterWindow);
    await emit(const Duration(minutes: 42));

    expect(u.undoTarget.value, const Duration(minutes: 5));
  });

  test('7 — prvi event nakon otvaranja epizode ne pali ponudu', () async {
    final u = build();

    // openAndResume: prvo što stigne je već resume pozicija.
    await emit(const Duration(minutes: 33));

    expect(u.undoTarget.value, isNull);
  });

  test('8 — ponuda istekne nakon ttl', () async {
    final u = build();

    await emit(const Duration(minutes: 5));
    await emit(const Duration(minutes: 42));
    expect(u.undoTarget.value, isNotNull);

    await Future<void>.delayed(afterWindow);

    expect(u.undoTarget.value, isNull);
  });

  test('9 — consume() gasi ponudu odmah i ne nudi Undo na Undo seek', () async {
    final u = build();

    await emit(const Duration(minutes: 5));
    await emit(const Duration(minutes: 42));
    expect(u.undoTarget.value, const Duration(minutes: 5));

    u.consume();
    expect(u.undoTarget.value, isNull);

    // Pozivatelj odmah izvodi povratni seek.
    await emit(const Duration(minutes: 5));

    expect(u.undoTarget.value, isNull, reason: 'Undo ne smije ponuditi Undo');
  });

  test('10 — rupa u streamu (buffering stall) ne pali ponudu', () async {
    final u = build();

    await emit(const Duration(minutes: 5));
    await emit(const Duration(minutes: 5, milliseconds: 200));
    // Stall: nekoliko sekundi bez eventa, pozicija se ne miče.
    await Future<void>.delayed(afterWindow);
    await emit(const Duration(minutes: 5, milliseconds: 200));
    await emitNatural(const Duration(minutes: 5, milliseconds: 200));

    expect(u.undoTarget.value, isNull);
  });

  test('11 — uzastopni skokovi drže PRVO sidro i produžuju ponudu', () async {
    final u = build();

    await emit(const Duration(minutes: 5));
    await emit(const Duration(minutes: 42)); // prvi scrub
    expect(u.undoTarget.value, const Duration(minutes: 5));

    await emit(const Duration(minutes: 12)); // korisnik i dalje traži
    expect(u.undoTarget.value, const Duration(minutes: 5),
        reason: 'sidro ostaje mjesto na kojem je korisnik stvarno bio');
  });

  test('12 — programski skok gasi zatečenu ponudu', () async {
    final u = build();

    await emit(const Duration(minutes: 5));
    await emit(const Duration(minutes: 42)); // scrub → ponuda
    expect(u.undoTarget.value, isNotNull);

    u.suppress(window: window);
    await emit(const Duration(minutes: 20)); // tap na poglavlje

    expect(u.undoTarget.value, isNull,
        reason: 'nakon namjerne navigacije sidro više ne pripada zadnjoj radnji');
  });

  test('13 — dispose prestaje slušati stream', () async {
    final u = build();

    await emit(const Duration(minutes: 5));
    u.dispose();
    undo = null;
    await emit(const Duration(minutes: 42));

    // undoTarget je disposean pa ga ne čitamo; dovoljno je da ništa nije
    // puknulo (notifikacija nad disposeanim ValueNotifierom baca assert).
  });
}
