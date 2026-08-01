/// Ugovor stanja zvuka — posebno razlika „korisnik je ugasio" vs „browser je
/// odbio autoplay sa zvukom".
///
/// Zašto test: `autoplayBlocked` je jedini okidač za „Uključi zvuk" CTA i za
/// preuzimanje mobilnog gumba „Video". Ako se ne obriše nakon korisnikovog
/// tapa, CTA ostane visjeti preko slike zauvijek; ako se obriše prerano,
/// korisnik nema što kliknuti. Player ovdje nije potreban — provjeravamo samo
/// prijelaze stanja (bez attacha `_apply` ne dira nikakav element).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:domovina_ai/services/player_mute.dart';

void main() {
  final mute = PlayerMute.instance;

  setUp(() async {
    // Singleton preživi između testova — vrati ga u polazno stanje.
    await mute.setMuted(false);
  });

  test('polazno stanje: zvuk radi, nema CTA', () {
    expect(mute.muted, isFalse);
    expect(mute.autoplayBlocked, isFalse);
  });

  test('muteForAutoplay pali i mute i CTA', () async {
    await mute.muteForAutoplay();
    expect(mute.muted, isTrue);
    expect(mute.autoplayBlocked, isTrue);
  });

  test('korisnikov unmute gasi CTA', () async {
    await mute.muteForAutoplay();
    await mute.setMuted(false);
    expect(mute.muted, isFalse);
    expect(mute.autoplayBlocked, isFalse);
  });

  test('korisnikov mute NE pali CTA — to nije browserova odluka', () async {
    await mute.setMuted(true);
    expect(mute.muted, isTrue);
    expect(mute.autoplayBlocked, isFalse);
  });

  test('CTA se ne vraća nakon što ga je korisnik jednom riješio', () async {
    await mute.muteForAutoplay();
    await mute.setMuted(false);
    await mute.toggle(); // korisnik sam ugasi zvuk
    expect(mute.muted, isTrue);
    expect(mute.autoplayBlocked, isFalse);
  });

  test('javlja slušateljima na svaku promjenu', () async {
    var calls = 0;
    void listener() => calls++;
    mute.addListener(listener);
    addTearDown(() => mute.removeListener(listener));

    await mute.muteForAutoplay();
    await mute.setMuted(false);
    expect(calls, greaterThanOrEqualTo(2));
  });
}
