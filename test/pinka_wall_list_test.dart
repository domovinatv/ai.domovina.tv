/// Kontrakt zida podrške nakon staggered redizajna (T3, 2026-08-08):
/// - točno DVIJE dopuštene visine pločice (visoka = s link previewom,
///   niska = bez njega),
/// - URL se u kartici pojavljuje TOČNO JEDNOM (nema više linkificiranog
///   teksta poruke + iste poveznice u preview kartici ispod),
/// - tap na karticu otvara detaljni sheet s punim, neclampanim tekstom.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:domovina_ai/l10n/app_localizations.dart';
import 'package:domovina_ai/pinka_sdk/src/models/pinka_link_preview.dart';
import 'package:domovina_ai/pinka_sdk/src/models/pinka_public_contribution.dart';
import 'package:domovina_ai/pinka_sdk/src/widgets/pinka_common.dart';
import 'package:domovina_ai/pinka_sdk/src/widgets/pinka_wall_list.dart';

Widget _wrap(Widget child) => MaterialApp(
      locale: const Locale('hr'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    );

PinkaPublicContribution _contribution({
  required String id,
  String? displayName,
  String? message,
  PinkaLinkPreview? preview,
  int amountCents = 1000,
}) =>
    PinkaPublicContribution(
      id: id,
      displayName: displayName,
      message: message,
      amountCents: amountCents,
      currency: 'eur',
      createdAt: null,
      linkPreview: preview,
    );

const _longMessage =
    'Hvala na svemu što radite za hrvatsku javnu riječ, ovo je poruka koja je '
    'namjerno dulja od dva retka kako bi se u kartici morala skratiti elipsom, '
    'a u detaljnom sheetu vidjeti cijela do zadnjeg slova.';

void main() {
  testWidgets('doprinos s previewom dobiva visoku, bez previewa nisku pločicu',
      (tester) async {
    await tester.pumpWidget(_wrap(
      PinkaWallList(
        contributions: [
          _contribution(
            id: 'a',
            displayName: 'Ana',
            message: 'Bez poveznice',
          ),
          _contribution(
            id: 'b',
            displayName: 'Boris',
            message: 'S poveznicom https://example.com/blog',
            preview: const PinkaLinkPreview(
              url: 'https://example.com/blog',
              title: 'Naslov stranice',
              siteName: 'example.com',
            ),
          ),
        ],
      ),
    ));
    await tester.pump();

    final tiles = tester.widgetList<StaggeredGridTile>(
      find.byType(StaggeredGridTile),
    );
    expect(tiles.map((t) => t.mainAxisExtent).toList(),
        [kPinkaWallShortTile, kPinkaWallTallTile]);

    // Odnos visina mora ostati 2:1 (+ razmak) — inače staggered raspored
    // ponovno dobije rupe.
    expect(kPinkaWallTallTile, 2 * kPinkaWallShortTile + kPinkaWallSpacing);
  });

  testWidgets('broj stupaca se računa iz raspoložive širine', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;

    Future<int> columnsAt(double width) async {
      tester.view.physicalSize = Size(width, 1200);
      await tester.pumpWidget(_wrap(
        PinkaWallList(
          contributions: [_contribution(id: 'a', displayName: 'Ana')],
        ),
      ));
      await tester.pump();
      final grid = tester.widget<StaggeredGrid>(find.byType(StaggeredGrid));
      return grid.delegate.getCrossAxisCount(width, kPinkaWallSpacing);
    }

    expect(await columnsAt(360), 1); // mobilni viewport
    expect(await columnsAt(700), 2);
    expect(await columnsAt(1400), 4); // clamp na 4
  });

  testWidgets('dvije niske pločice popune stupac uz jednu visoku (bez rupa)',
      (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(700, 1200); // 2 stupca

    await tester.pumpWidget(_wrap(
      PinkaWallList(
        contributions: [
          _contribution(
            id: 'tall',
            displayName: 'Boris',
            preview: const PinkaLinkPreview(
              url: 'https://example.com/blog',
              title: 'Naslov',
              siteName: 'example.com',
            ),
          ),
          _contribution(id: 's1', displayName: 'Ana'),
          _contribution(id: 's2', displayName: 'Ivo'),
        ],
      ),
    ));
    await tester.pump();

    // Visoka u prvom stupcu, dvije niske u drugom → mreža je točno visine
    // jedne visoke pločice. Svaki višak bi značio rupu.
    expect(tester.getSize(find.byType(StaggeredGrid)).height,
        kPinkaWallTallTile);
  });

  testWidgets('URL se u kartici pojavljuje točno jednom', (tester) async {
    await tester.pumpWidget(_wrap(
      PinkaWallList(
        contributions: [
          _contribution(
            id: 'b',
            displayName: 'Boris',
            message: 'Pogledajte https://example.com/blog super je',
            preview: const PinkaLinkPreview(
              url: 'https://example.com/blog',
              title: 'Naslov stranice',
              siteName: 'example.com',
            ),
          ),
        ],
      ),
    ));
    await tester.pump();

    // Izvor (host) je jedini nositelj poveznice u kartici...
    expect(find.textContaining('example.com'), findsOneWidget);
    // ...a goli URL iz poruke je uklonjen, ostatak teksta je zadržan.
    expect(find.textContaining('https://example.com/blog'), findsNothing);
    expect(find.text('Pogledajte super je'), findsOneWidget);
  });

  testWidgets('tap na karticu otvara sheet s punim tekstom poruke',
      (tester) async {
    final l = await AppLocalizations.delegate.load(const Locale('hr'));

    await tester.pumpWidget(_wrap(
      PinkaWallList(
        contributions: [
          _contribution(
            id: 'a',
            displayName: 'Ana',
            message: _longMessage,
            amountCents: 2500,
          ),
        ],
      ),
    ));
    await tester.pump();

    // U kartici je tekst clampan na jedan redak s elipsom.
    final cardText = tester.widget<Text>(find.text(_longMessage));
    expect(cardText.maxLines, 1);
    expect(cardText.overflow, TextOverflow.ellipsis);

    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();

    // Sheet ima puni tekst (bez clampa, linkificiran) i gumb za zatvaranje.
    final sheetText = tester.widget<PinkaLinkify>(find.byType(PinkaLinkify));
    expect(sheetText.text, _longMessage);
    expect(find.text(l.commonClose), findsOneWidget);
    expect(find.text('25 €'), findsWidgets);
  });

  testWidgets('doprinos bez poruke i poveznice nije tap meta', (tester) async {
    await tester.pumpWidget(_wrap(
      PinkaWallList(
        contributions: [_contribution(id: 'a', displayName: 'Ana')],
      ),
    ));
    await tester.pump();

    // Cijeli sadržaj je već vidljiv u pločici — sheet bi samo ponovio isto.
    expect(find.byType(InkWell), findsNothing);
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('sheet nudi "Otvori poveznicu" samo kad doprinos ima preview',
      (tester) async {
    final l = await AppLocalizations.delegate.load(const Locale('hr'));

    await tester.pumpWidget(_wrap(
      PinkaWallList(
        contributions: [
          _contribution(id: 'a', displayName: 'Ana', message: 'Bez linka'),
        ],
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();
    expect(find.text(l.pinkaWallOpenLink), findsNothing);
    await tester.tap(find.text(l.commonClose));
    await tester.pumpAndSettle();

    await tester.pumpWidget(_wrap(
      PinkaWallList(
        contributions: [
          _contribution(
            id: 'b',
            displayName: 'Boris',
            message: 'https://example.com/blog',
            preview: const PinkaLinkPreview(
              url: 'https://example.com/blog',
              title: 'Naslov stranice',
              description: 'Opis koji se vidi samo u sheetu.',
              siteName: 'example.com',
            ),
          ),
        ],
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('Boris'));
    await tester.pumpAndSettle();
    expect(find.text(l.pinkaWallOpenLink), findsOneWidget);
    expect(find.text('Opis koji se vidi samo u sheetu.'), findsOneWidget);
  });
}
