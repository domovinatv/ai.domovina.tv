/// Home rail „Izborni dan" — layout na najužem ciljanom ekranu.
///
/// Rail je jedina ulazna točka glasanja koju vidi korisnik bez potvrde
/// e-Osobnom, pa mora preživjeti 320 dp bez overflowa i uvijek završiti
/// karticom koja objašnjava što se ovdje zapravo radi.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:domovina_ai/l10n/app_localizations.dart';
import 'package:domovina_ai/models/vote_candidate.dart';
import 'package:domovina_ai/screens/home/voting_rail.dart';
import 'package:domovina_ai/services/voting_service.dart';

VoteCandidate kandidat(String slug, String ime, {int up = 0, int rank = 1}) =>
    VoteCandidate(
      slug: slug,
      displayName: ime,
      up: up,
      rank: rank,
    );

Widget _harness({required double width}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(
          body: SingleChildScrollView(child: VotingRail(isMobile: true)),
        ),
      ),
      GoRoute(path: '/glasanje', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/glasanje/:slug', builder: (_, _) => const SizedBox()),
    ],
  );
  return MediaQuery(
    data: MediaQueryData(size: Size(width, 800)),
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('hr'),
    ),
  );
}

void main() {
  testWidgets('bez kandidata rail je nevidljiv — home izgleda kao prije',
      (tester) async {
    VotingService.instance.debugSetPreview(const []);
    await tester.pumpWidget(_harness(width: 320));
    await tester.pump();

    expect(find.byType(VotingRail), findsOneWidget);
    expect(find.text('Izborni dan'), findsNothing);
  });

  testWidgets('320 dp: kandidati + CTA kartica, bez overflowa', (tester) async {
    VotingService.instance.debugSetPreview([
      kandidat('podcast-jedan', 'Podcast Jedan', up: 12, rank: 1),
      kandidat('podcast-dva', 'Podcast Dva s jako dugačkim nazivom', rank: 2),
      kandidat('podcast-tri', 'Podcast Tri', rank: 3),
    ]);
    await tester.pumpWidget(_harness(width: 320));
    await tester.pump();

    // Eyebrow je uppercased u EpisodesRail-u.
    expect(find.text('IZBORNI DAN'), findsOneWidget);
    expect(find.text('Svi kandidati'), findsOneWidget);
    expect(find.text('Podcast Jedan'), findsOneWidget);
    // Zadnja kartica objašnjava feature — bez nje su same sličice bez značenja.
    expect(find.text('Glasaj koji ide sljedeći'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap na kandidata vodi na /glasanje/:slug', (tester) async {
    VotingService.instance.debugSetPreview([
      kandidat('podcast-jedan', 'Podcast Jedan', rank: 1),
    ]);
    await tester.pumpWidget(_harness(width: 400));
    await tester.pump();

    await tester.tap(find.text('Podcast Jedan'));
    await tester.pumpAndSettle();

    expect(find.byType(VotingRail), findsNothing);
  });
}
