/// „Prikaži sve" na home railu osoba → katalog s filtrom „Osobe".
///
/// Rail pokazuje vrh popisa; puni katalog živi u `/channels`, isti ekran u
/// kojem su i kanali. Odredište je query param (`?prikaz=osobe`) na postojećoj
/// ruti, a NE nova `/osobe` ruta — nova javna content ruta mora u OBA
/// deep-link popisa (AASA `components` u `web/_worker.js` + Android intent
/// filter), pravilo iz CLAUDE.md.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:domovina_ai/l10n/app_localizations.dart';
import 'package:domovina_ai/models/person_hub.dart';
import 'package:domovina_ai/screens/channels/all_channels_screen.dart';
import 'package:domovina_ai/screens/home/persons_rail.dart';
import 'package:domovina_ai/services/person_channel_flag.dart';
import 'package:domovina_ai/services/person_index_cache.dart';

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('hr'),
      home: Scaffold(body: child),
    );

/// Indeks s [count] osoba — sve prolaze prag, sve su virtualni kanali.
PersonIndex _indexWith(int count) => PersonIndex.fromJson({
      'version': '1.0',
      'person_count': count,
      'persons': [
        for (var i = 0; i < count; i++)
          {
            'slug': 'osoba-broj-$i',
            'name': 'Osoba Broj $i',
            'episode_count': 20 - i,
            'channel_count': 4,
            'total_duration_seconds': 3600,
            'first_year': 2020,
            'last_year': 2026,
            'is_virtual_channel': true,
            'latest_episode': {
              'youtube_id': 'vid$i',
              'date': '2026-06-0${i % 9 + 1}',
              'title': 'Epizoda $i',
            },
          },
      ],
    });

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PersonChannelFlag.instance.debugReset();
    personIndexCache.debugReset();
  });
  tearDown(() {
    PersonChannelFlag.instance.debugReset();
    personIndexCache.debugReset();
  });

  group('PersonsRail — „Prikaži sve"', () {
    testWidgets('rail nudi „Prikaži sve" uz naslov', (tester) async {
      await PersonChannelFlag.instance.setOn(true);
      personIndexCache.debugSetIndex(_indexWith(20));

      await tester.pumpWidget(_wrap(const PersonsRail(isMobile: false)));
      await tester.pumpAndSettle();

      expect(find.text('OSOBE'), findsOneWidget);
      expect(find.text('Prikaži sve'), findsOneWidget);
    });

    testWidgets('rail je ograničen na `limit` kartica, ne na cijeli indeks',
        (tester) async {
      // Bez kapice bi home gradio karticu za svaku osobu u indeksu (74 na dan
      // 4.9.2026.) pri svakom buildu — na stranici koja je namjerno olakšana
      // zbog scroll-perfa.
      await PersonChannelFlag.instance.setOn(true);
      personIndexCache.debugSetIndex(_indexWith(20));

      await tester
          .pumpWidget(_wrap(const PersonsRail(isMobile: false, limit: 5)));
      await tester.pumpAndSettle();

      expect(find.text('Osoba Broj 0'), findsOneWidget);
      expect(find.text('Osoba Broj 4'), findsOneWidget);
      // Šesta osoba je iza kapice — vidi se tek u katalogu.
      expect(find.text('Osoba Broj 5'), findsNothing);
    });

    testWidgets('s ugašenim flagom rail se uopće ne crta', (tester) async {
      await PersonChannelFlag.instance.setOn(false);
      personIndexCache.debugSetIndex(_indexWith(20));

      await tester.pumpWidget(_wrap(const PersonsRail(isMobile: false)));
      await tester.pumpAndSettle();

      expect(find.text('Prikaži sve'), findsNothing);
    });
  });

  group('AllChannelsView — početni filtar', () {
    testWidgets('otvoren s CatalogFilter.persons pokazuje samo osobe',
        (tester) async {
      await PersonChannelFlag.instance.setOn(true);
      personIndexCache.debugSetIndex(_indexWith(6));

      await tester.pumpWidget(_wrap(
        const AllChannelsView(initialFilter: CatalogFilter.persons),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Osoba Broj 0'), findsOneWidget);
      expect(find.text('Osoba Broj 5'), findsOneWidget);
    });

    testWidgets(
        'filtar „Osobe" bez dostupnih osoba pada na „Sve", ne na praznu listu',
        (tester) async {
      // Dva puta vode ovamo: /channels?prikaz=osobe kod korisnika s ugašenim
      // flagom, i gašenje flaga dok je „Osobe" aktivan. Chipovi se u tom
      // slučaju ne crtaju, pa bi prazna lista bila ćorsokak bez izlaza.
      await PersonChannelFlag.instance.setOn(false);
      personIndexCache.debugSetIndex(_indexWith(6));

      await tester.pumpWidget(_wrap(
        const AllChannelsView(initialFilter: CatalogFilter.persons),
      ));
      await tester.pumpAndSettle();

      // Nijedna osoba (flag ugašen), ali ni prazan ekran — filter chipovi
      // uopće nisu vidljivi, pa katalog mora pokazati kanale.
      expect(find.text('Osoba Broj 0'), findsNothing);
      expect(find.text('Osobe'), findsNothing);
    });
  });
}
