import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:domovina_ai/l10n/app_localizations.dart';
import 'package:domovina_ai/models/podcast_summary.dart';
import 'package:domovina_ai/widgets/entities_section.dart';

/// Traka osoba ispod naslova epizode — glavna joj je zadaća da se osoba s
/// koje si došao (`?p=<slug>`) vidi ODMAH, a ne tek na dnu članka.
SummaryContent _summary(List<String> people) => SummaryContent(
      titleHr: 'Test',
      abstractHr: 'Test',
      keyTopics: const [],
      speakers: const [],
      keyPoints: const [],
      mentionedPeople: people,
      mentionedPlaces: const [],
      mentionedOrganizations: const [],
      language: 'hr',
      contentType: 'podcast',
      sentiment: 'neutral',
    );

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('hr'),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('renderira chip za svaku spomenutu osobu', (tester) async {
    await tester.pumpWidget(_wrap(
      PeopleRail(summary: _summary(['Ivan Merz', 'Željka Markić'])),
    ));

    expect(find.text('Ivan Merz'), findsOneWidget);
    expect(find.text('Željka Markić'), findsOneWidget);
  });

  testWidgets('prazan popis osoba ne zauzima prostor', (tester) async {
    await tester.pumpWidget(_wrap(PeopleRail(summary: _summary(const []))));

    expect(find.byType(EntityChip), findsNothing);
    expect(tester.getSize(find.byType(PeopleRail)).height, 0);
  });

  testWidgets('istaknuta osoba je bijelo-na-crveno, ostale nisu',
      (tester) async {
    await tester.pumpWidget(_wrap(
      PeopleRail(
        // Slug se folda: "Željka Markić" → "zeljka-markic".
        summary: _summary(['Ivan Merz', 'Željka Markić']),
        highlightPersonSlug: 'zeljka-markic',
      ),
    ));

    final chips = tester
        .widgetList<EntityChip>(find.byType(EntityChip))
        .toList(growable: false);
    expect(chips.length, 2);
    expect(chips.firstWhere((c) => c.label == 'Željka Markić').highlighted,
        isTrue);
    expect(chips.firstWhere((c) => c.label == 'Ivan Merz').highlighted, isFalse);
  });

  testWidgets('nepoznat slug ne istakne nikoga', (tester) async {
    await tester.pumpWidget(_wrap(
      PeopleRail(
        summary: _summary(['Ivan Merz']),
        highlightPersonSlug: 'netko-drugi',
      ),
    ));

    expect(
      tester.widget<EntityChip>(find.byType(EntityChip)).highlighted,
      isFalse,
    );
  });
}
