// Integracijski testovi koji verificiraju ispravnost renderiranja i semantičke strukture.
//
// Pokreni:
//   chromedriver --port=4444 &
//   flutter drive --driver=test_driver/integration_test.dart \
//                 --target=integration_test/rendering_test.dart -d chrome
//
// Za Skwasm renderer dodaj: --wasm
// Testovi koji dohvaćaju EpisodeScreen koriste live CDN — zahtijevaju mrežnu konekciju.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:domovina_ai/main.dart' as app;

/// Video ID koji mora uvijek biti dostupan na CDN-u za testove.
const kTestVideoId = 'H-p2Hl6x7I0';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ─── HomeScreen ──────────────────────────────────────────────────────────

  group('HomeScreen — rendering', () {
    testWidgets('prikazuje naslov, subtitle, input i gumb', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      expect(find.text('Domovina.ai'), findsOneWidget);
      expect(find.text('Unesi YouTube ID epizode'), findsOneWidget);
      expect(find.text('Otvori epizodu'), findsOneWidget);
      expect(find.byIcon(Icons.ondemand_video_outlined), findsOneWidget);
    });

    testWidgets('prazno polje prikazuje validacijsku grešku', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Otvori epizodu'));
      await tester.pumpAndSettle();

      expect(find.text('Unesi YouTube ID'), findsOneWidget);
      expect(find.text('Domovina.ai'), findsOneWidget); // i dalje na HomeScreen
    });

    testWidgets('screenshot — HomeScreen', (tester) async {
      final binding = IntegrationTestWidgetsFlutterBinding.instance;
      app.main();
      await tester.pumpAndSettle();
      await binding.takeScreenshot('home_screen');
    });
  });

  // ─── HomeScreen semantics ─────────────────────────────────────────────────

  group('HomeScreen — semantics', () {
    testWidgets('input field ima semantic label', (tester) async {
      final semantics = tester.ensureSemantics();
      app.main();
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('YouTube ID'),
        findsOneWidget,
        reason: 'TextFormField mora imati semanticsLabel za screen readere i testove',
      );
      semantics.dispose();
    });

    testWidgets('semantics node za cijelu aplikaciju postoji', (tester) async {
      final semantics = tester.ensureSemantics();
      app.main();
      await tester.pumpAndSettle();

      final node = tester.getSemantics(find.byType(MaterialApp));
      expect(node, isNotNull);
      semantics.dispose();
    });
  });

  // ─── EpisodeScreen — CDN load ─────────────────────────────────────────────

  group('EpisodeScreen — CDN load', () {
    /// Pumpa app, navigira na epizodu i čeka učitavanje.
    /// Koristi [pump] umjesto [pumpAndSettle] jer media_kit player
    /// emitira kontinuirani stream pozicija koji sprečava settling.
    Future<void> loadEpisode(WidgetTester tester, String ytId) async {
      app.main();
      await tester.pumpAndSettle();

      // Unesi ID direktno u TextFormField (bez semantics findinga)
      await tester.enterText(find.byType(TextFormField), ytId);
      await tester.tap(find.text('Otvori epizodu'));

      // Pumpa do 30s čekajući CDN fetch (5 paralelnih requesta)
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        // Izađi čim se pojavi sadržaj ili error
        final hasContent = find.text('Sažetak').evaluate().isNotEmpty ||
            find.text('Poglavlja').evaluate().isNotEmpty ||
            find.text('Članak').evaluate().isNotEmpty;
        final hasError = find.text('Natrag').evaluate().isNotEmpty;
        if (hasContent || hasError) break;
      }
    }

    testWidgets('navigira s HomeScreen na EpisodeScreen', (tester) async {
      await loadEpisode(tester, kTestVideoId);

      // Nije ostao na HomeScreen
      expect(find.text('Unesi YouTube ID epizode'), findsNothing);
      // Nije prikazao "Video ne postoji" error
      expect(find.textContaining('nije pronađena na CDN-u'), findsNothing);
    });

    testWidgets('barem jedna sekcija sadržaja je prikazana', (tester) async {
      await loadEpisode(tester, kTestVideoId);

      final hasSazetak  = find.text('Sažetak').evaluate().isNotEmpty;
      final hasPoglavlja = find.text('Poglavlja').evaluate().isNotEmpty;
      final hasClanak   = find.text('Članak').evaluate().isNotEmpty;

      expect(
        hasSazetak || hasPoglavlja || hasClanak,
        isTrue,
        reason: 'Barem jedna sekcija mora biti prikazana nakon CDN load',
      );
    });

    testWidgets('video player kontrole su prisutne', (tester) async {
      final semantics = tester.ensureSemantics();
      await loadEpisode(tester, kTestVideoId);

      // Skip gumbi imaju tooltip → semantic label
      expect(find.bySemanticsLabel('-10s'), findsOneWidget);
      expect(find.bySemanticsLabel('+10s'), findsOneWidget);

      // Play ili Pause gumb mora biti prisutan
      final hasPlay  = find.bySemanticsLabel('Reproduciraj').evaluate().isNotEmpty;
      final hasPause = find.bySemanticsLabel('Pauziraj').evaluate().isNotEmpty;
      expect(hasPlay || hasPause, isTrue,
          reason: 'Play/Pause gumb mora imati semantic label');

      semantics.dispose();
    });

    testWidgets('nepostojeći video ID prikazuje error s gumbom Natrag', (tester) async {
      await loadEpisode(tester, 'nepostojeci_xyz_000');
      expect(find.text('Natrag'), findsOneWidget);
    });

    testWidgets('screenshot — EpisodeScreen nakon load', (tester) async {
      final binding = IntegrationTestWidgetsFlutterBinding.instance;
      await loadEpisode(tester, kTestVideoId);
      await binding.takeScreenshot('episode_screen_$kTestVideoId');
    });
  });
}
