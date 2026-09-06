import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:domovina_ai/router/nav.dart';

/// Ugovor navigacijskog stoga (`lib/router/nav.dart`).
///
/// Ovi testovi postoje jer je regresija ovdje NEVIDLJIVA dok je netko ne
/// primijeti rukom: `go()` umjesto `push()` ne baca grešku, ne pada u
/// analizatoru, i izgleda točno isto — samo se scroll tiho ne vrati i Back
/// odvede na krivo mjesto. Točno tako je i nastalo stanje od 82 `go()` poziva.
void main() {
  /// Minimalni ruter s istim oblikom kao produkcijski: sve rute su top-level
  /// `GoRoute` s `NoTransitionPage` (dakle `maintainState: true`).
  GoRouter buildRouter({required GlobalKey homeKey}) {
    Page<void> page(String key, Widget child) =>
        NoTransitionPage(key: ValueKey(key), child: child);

    return GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (_, _) => page('home', _Home(key: homeKey)),
        ),
        GoRoute(
          path: '/v/:id',
          pageBuilder: (_, s) =>
              page('v-${s.pathParameters['id']}', const _Leaf('episode')),
        ),
        GoRoute(
          path: '/m/:id',
          pageBuilder: (_, s) =>
              page('m-${s.pathParameters['id']}', const _Leaf('simple')),
        ),
        GoRoute(
          path: '/c/:slug',
          pageBuilder: (_, s) =>
              page('c-${s.pathParameters['slug']}', const _Leaf('channel')),
        ),
      ],
    );
  }

  Future<GoRouter> pumpApp(WidgetTester tester, GlobalKey homeKey) async {
    final router = buildRouter(homeKey: homeKey);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  /// Ono što go_router vrati Routeru da upiše u adresnu traku. Ovo je JEDINI
  /// put kojim URL na webu nastaje, pa je i jedini pošten način da se u testu
  /// provjeri što bi korisnik vidio.
  String addressBarOf(GoRouter router) {
    final info = router.routeInformationParser
        .restoreRouteInformation(router.routerDelegate.currentConfiguration);
    return info!.uri.toString();
  }

  group('drillDown gradi stog', () {
    testWidgets('nakon drill-downa canPop() je true', (tester) async {
      final homeKey = GlobalKey();
      final router = await pumpApp(tester, homeKey);

      expect(router.routerDelegate.currentConfiguration.matches.length, 1);

      drillDown(homeKey.currentContext!, '/v/abc');
      await tester.pumpAndSettle();

      expect(router.routerDelegate.currentConfiguration.matches.length, 2,
          reason: 'push mora dodati match, ne zamijeniti listu');
    });

    testWidgets('ekran ispod PREŽIVI drill-down — isti State, isti scroll',
        (tester) async {
      final homeKey = GlobalKey();
      final router = await pumpApp(tester, homeKey);

      final stateBefore = homeKey.currentState as _HomeState;
      stateBefore.marker = 'scrollao-sam-2400';

      drillDown(homeKey.currentContext!, '/v/abc');
      await tester.pumpAndSettle();

      // Ovo je srž popravka: `go()` bi ovdje dao null (ruta uklonjena iz
      // match liste → State dispose-an), pa se scroll nije imao odakle vratiti.
      expect(homeKey.currentState, isNotNull,
          reason: 'ruta ispod mora ostati montirana (maintainState: true)');

      router.pop();
      await tester.pumpAndSettle();

      expect(identical(homeKey.currentState, stateBefore), isTrue,
          reason: 'pop mora vratiti ISTU instancu, ne izgraditi novu');
      expect((homeKey.currentState as _HomeState).marker, 'scrollao-sam-2400');
    });

    testWidgets('ograda kMaxStackDepth zaustavlja rast stoga', (tester) async {
      final homeKey = GlobalKey();
      final router = await pumpApp(tester, homeKey);

      for (var i = 0; i < kMaxStackDepth + 5; i++) {
        drillDown(homeKey.currentContext!, '/v/ep$i');
        await tester.pumpAndSettle();
      }

      // Bazni match + najviše kMaxStackDepth imperativnih.
      expect(
        router.routerDelegate.currentConfiguration.matches.length,
        lessThanOrEqualTo(kMaxStackDepth + 1),
        reason: 'bez ograde je push curenje memorije — svaki ekran ostaje živ',
      );
    });
  });

  group('swapPresentation ne troši Back korak', () {
    testWidgets('/v ↔ /m ne produbljuje stog', (tester) async {
      final homeKey = GlobalKey();
      final router = await pumpApp(tester, homeKey);

      drillDown(homeKey.currentContext!, '/v/abc');
      await tester.pumpAndSettle();
      final depthAfterOpen =
          router.routerDelegate.currentConfiguration.matches.length;

      final ctx = tester.element(find.text('episode'));
      swapPresentation(ctx, '/m/abc');
      await tester.pumpAndSettle();

      expect(find.text('simple'), findsOneWidget);
      expect(router.routerDelegate.currentConfiguration.matches.length,
          depthAfterOpen,
          reason: 'prebacivanje prikaza nije korak u povijesti pregledavanja');
    });

    testWidgets('nakon prebacivanja prikaza Back i dalje vodi na naslovnicu',
        (tester) async {
      final homeKey = GlobalKey();
      final router = await pumpApp(tester, homeKey);

      drillDown(homeKey.currentContext!, '/v/abc');
      await tester.pumpAndSettle();
      swapPresentation(tester.element(find.text('episode')), '/m/abc');
      await tester.pumpAndSettle();

      router.pop();
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget,
          reason: 'dva prebacivanja prikaza ne smiju stvoriti lažne korake');
    });
  });

  group('goPeer zamjenjuje vrh, ne produbljuje', () {
    testWidgets('epizoda → srodna epizoda drži dubinu', (tester) async {
      final homeKey = GlobalKey();
      final router = await pumpApp(tester, homeKey);

      drillDown(homeKey.currentContext!, '/v/prva');
      await tester.pumpAndSettle();
      final depth =
          router.routerDelegate.currentConfiguration.matches.length;

      goPeer(tester.element(find.text('episode')), '/v/druga');
      await tester.pumpAndSettle();

      expect(router.routerDelegate.currentConfiguration.matches.length, depth);
    });
  });

  group('adresna traka prati pushani ekran', () {
    // Ovo je bio KRITIČNI PUT migracije (stavka 2 u backlogu).
    //
    // `RouteMatchList.uri` po ugovoru odražava samo NE-imperativne matcheve
    // (go_router match.dart:509-511), a `RouteMatchList.push` ne prosljeđuje
    // `uri` — pa bez `optionURLReflectsImperativeAPIs` adresna traka ostaje na
    // baznoj ruti. Za nas bi to razbilo „Kopiraj poveznicu", worker OG inject i
    // url_sync. Test provjerava baš ono što go_router vrati Routeru da upiše.
    setUp(() => GoRouter.optionURLReflectsImperativeAPIs = true);

    testWidgets('push na epizodu daje URL epizode, ne naslovnice',
        (tester) async {
      final homeKey = GlobalKey();
      final router = await pumpApp(tester, homeKey);

      expect(addressBarOf(router), '/');

      drillDown(homeKey.currentContext!, '/v/abc');
      await tester.pumpAndSettle();

      expect(addressBarOf(router), '/v/abc',
          reason: 'bez optionURLReflectsImperativeAPIs ovdje bi ostalo "/"');
    });

    testWidgets('query i timestamp preživljavaju push', (tester) async {
      final homeKey = GlobalKey();
      final router = await pumpApp(tester, homeKey);

      drillDown(homeKey.currentContext!, '/v/abc?p=don-damir-stojic');
      await tester.pumpAndSettle();

      expect(addressBarOf(router), '/v/abc?p=don-damir-stojic');
    });

    testWidgets('pop vraća adresnu traku na baznu rutu', (tester) async {
      final homeKey = GlobalKey();
      final router = await pumpApp(tester, homeKey);

      drillDown(homeKey.currentContext!, '/c/muzevni-budite');
      await tester.pumpAndSettle();
      expect(addressBarOf(router), '/c/muzevni-budite');

      router.pop();
      await tester.pumpAndSettle();
      expect(addressBarOf(router), '/');
    });

    testWidgets('bez zastavice URL bi ostao na baznoj ruti — regresijski dokaz',
        (tester) async {
      GoRouter.optionURLReflectsImperativeAPIs = false;
      addTearDown(() => GoRouter.optionURLReflectsImperativeAPIs = true);

      final homeKey = GlobalKey();
      final router = await pumpApp(tester, homeKey);

      drillDown(homeKey.currentContext!, '/v/abc');
      await tester.pumpAndSettle();

      expect(addressBarOf(router), '/',
          reason: 'dokumentira ZAŠTO zastavica u main.dart mora ostati');
    });
  });

  group('back', () {
    testWidgets('popa kad ima stog', (tester) async {
      final homeKey = GlobalKey();
      await pumpApp(tester, homeKey);

      drillDown(homeKey.currentContext!, '/v/abc');
      await tester.pumpAndSettle();

      back(tester.element(find.text('episode')));
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('bez stoga ide na zadani fallback, ne slijepo na /',
        (tester) async {
      final homeKey = GlobalKey();
      final router = await pumpApp(tester, homeKey);

      // Simulira dolazak izvana (share link) — nema se što popati.
      router.go('/v/abc');
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.matches.length, 1);

      back(tester.element(find.text('episode')),
          fallback: '/c/muzevni-budite');
      await tester.pumpAndSettle();

      expect(find.text('channel'), findsOneWidget);
    });
  });
}

class _Home extends StatefulWidget {
  const _Home({super.key});

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  /// Stoji umjesto scroll pozicije — svjedok da State nije presložen.
  String marker = '';

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('home'));
}

class _Leaf extends StatelessWidget {
  final String label;
  const _Leaf(this.label);

  @override
  Widget build(BuildContext context) => Scaffold(body: Text(label));
}
