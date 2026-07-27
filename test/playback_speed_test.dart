/// Defender za `PlaybackSpeed` (2026-07-27, plan
/// `docs/plans/2026-07-27-playback-overhaul.md`).
///
/// `PlaybackSpeed` je singleton s lazy `init()`-om pa se sve odvija u jednom
/// uređenom slijedu — dijeljenje na više `test()` blokova bi dijelilo i stanje.
library;

import 'package:domovina_ai/services/playback_speed.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pokvarena spremljena vrijednost → 1.0, clamp i kružni prekidač',
      () async {
    SharedPreferences.setMockInitialValues({'playback_speed': 'zzz'});

    await PlaybackSpeed.instance.init();
    final speed = PlaybackSpeed.instance;
    expect(speed.rate, 1.0, reason: 'nečitljiva vrijednost pada na default');

    // Krug: 1.0 → 1.25 → 1.5 → 1.75 → 2.0 → 1.0
    final seen = <double>[];
    for (var i = 0; i < kPlaybackRates.length + 1; i++) {
      seen.add(speed.rate);
      await speed.setRate(speed.nextRate);
    }
    expect(seen, [...kPlaybackRates, kPlaybackRates.first]);
    expect(speed.rate, kPlaybackRates[1], reason: 'krug se nastavlja dalje');

    // Vrijednost izvan popisa se clampa na najbližu ponuđenu.
    await speed.setRate(1.37);
    expect(speed.rate, 1.25);
    await speed.setRate(99);
    expect(speed.rate, 2.0);
    await speed.setRate(double.nan);
    expect(speed.rate, 1.0);

    // Promjena se javlja listenerima i perzistira.
    var notified = 0;
    void listener() => notified++;
    speed.addListener(listener);
    await speed.setRate(1.5);
    await speed.setRate(1.5); // ista vrijednost → bez notifikacije
    speed.removeListener(listener);
    expect(notified, 1);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('playback_speed'), '1.5');
  });
}
