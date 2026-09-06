import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:domovina_ai/services/scroll_memory.dart';

/// Ugovor sloja za pamćenje scroll pozicije.
///
/// Podsjetnik: ovo NIJE glavni mehanizam — glavni je `push` iz
/// `lib/router/nav.dart`, koji ekran ispod ostavlja živ pa mu pozicija nikad ne
/// ode. Ovaj sloj hvata samo slučajeve u kojima ekran stvarno nastaje iznova
/// (deep-link pa ←, hard refresh, `go('/')` s breadcrumba).
void main() {
  setUp(() => ScrollMemory.instance.clearAll());

  group('ScrollMemory — spremanje', () {
    test('vrh se NE pamti — nema što vraćati', () {
      ScrollMemory.instance.save('/', 0);
      expect(ScrollMemory.instance.read('/'), isNull);
    });

    test('negativan offset (overscroll) se ne pamti', () {
      ScrollMemory.instance.save('/', -80);
      expect(ScrollMemory.instance.read('/'), isNull);
    });

    test('pozicija se pamti po ruti i ne miješa se između ruta', () {
      ScrollMemory.instance.save('/', 2400);
      ScrollMemory.instance.save('/channels', 640);
      expect(ScrollMemory.instance.read('/'), 2400);
      expect(ScrollMemory.instance.read('/channels'), 640);
    });

    // `/channels` i `/channels?prikaz=osobe` su DVA prikaza iste rute (odluka
    // O9 u docs/plans/virtualni-kanali.md) — isti razlog zbog kojeg ruter već
    // ima različit ValueKey po prikazu.
    test('query string je dio ključa', () {
      ScrollMemory.instance.save('/channels', 100);
      ScrollMemory.instance.save('/channels?prikaz=osobe', 900);
      expect(ScrollMemory.instance.read('/channels'), 100);
      expect(ScrollMemory.instance.read('/channels?prikaz=osobe'), 900);
    });
  });

  group('ScrollRestorer — vraćanje', () {
    /// Sadržaj koji naraste TEK nakon nekoliko frameova — vjerna slika
    /// naslovnice, čija visina dolazi u više asinkronih koraka (railovi se
    /// pale kako podaci stižu).
    Widget harness({
      required ScrollController controller,
      required int itemCount,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: ScrollRestorer(
            storageKey: '/',
            controller: controller,
            child: ListView.builder(
              controller: controller,
              itemCount: itemCount,
              itemBuilder: (_, i) => SizedBox(height: 100, child: Text('$i')),
            ),
          ),
        ),
      );
    }

    testWidgets('vraća spremljenu poziciju kad sadržaj već ima visinu',
        (tester) async {
      ScrollMemory.instance.save('/', 1500);
      final c = ScrollController();
      addTearDown(c.dispose);

      await tester.pumpWidget(harness(controller: c, itemCount: 100));
      await tester.pump();

      expect(c.position.pixels, 1500);
    });

    testWidgets('čeka da sadržaj naraste umjesto da se clampa na skeleton',
        (tester) async {
      ScrollMemory.instance.save('/', 1500);
      final c = ScrollController();
      addTearDown(c.dispose);

      // Prvi frame: kratka lista (skeleton) — 1500 px ne postoji.
      await tester.pumpWidget(harness(controller: c, itemCount: 3));
      await tester.pump();
      expect(c.position.pixels, 0, reason: 'ne smije se clampati na skeleton');

      // Sadržaj naraste — restore mora pogoditi punu poziciju.
      await tester.pumpWidget(harness(controller: c, itemCount: 100));
      await tester.pump();
      await tester.pump();

      expect(c.position.pixels, 1500);
    });

    testWidgets('odustaje nakon timeouta ako sadržaj nikad ne naraste',
        (tester) async {
      ScrollMemory.instance.save('/', 5000);
      final c = ScrollController();
      addTearDown(c.dispose);

      await tester.pumpWidget(harness(controller: c, itemCount: 5));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      // Bolje vrh nego skok u pogrešno mjesto nakon što korisnik već čita.
      expect(c.position.pixels, 0);
    });

    testWidgets('bez spremljene pozicije počinje na vrhu', (tester) async {
      final c = ScrollController();
      addTearDown(c.dispose);

      await tester.pumpWidget(harness(controller: c, itemCount: 100));
      await tester.pump();

      expect(c.position.pixels, 0);
    });
  });
}
