/// Ugovor lokalnog praćenja (T5, `docs/plans/virtualni-kanali.md`).
///
/// Remote sync je namjerno izostavljen — `domovina_ai.follows` ne postoji
/// (`domovinatv/domovina-api#3`), pa testovi pokrivaju SAMO lokalnu putanju.
/// U `flutter test` je `kIsWeb == false`, pa servis ide kroz
/// `SharedPreferences`; web grana koristi `local_prefs.dart` (localStorage) i
/// dijeli iste ključeve, što se ovdje provjerava preko konstanti
/// [kFollowsStorageKey] / [kFollowsSeenStorageKey].
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:domovina_ai/l10n/app_localizations.dart';
import 'package:domovina_ai/models/person_hub.dart';
import 'package:domovina_ai/screens/home/followed_rail.dart';
import 'package:domovina_ai/services/follow_service.dart';
import 'package:domovina_ai/services/person_channel_flag.dart';
import 'package:domovina_ai/services/person_index_cache.dart';
import 'package:domovina_ai/widgets/follow_button.dart';

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('hr'),
      home: Scaffold(body: child),
    );

/// Indeks s jednom osobom koja ima zadnju epizodu — izvor za rail.
PersonIndex _indexWith({required String slug, required String date}) =>
    PersonIndex.fromJson({
      'version': '1.0',
      'persons': [
        {
          'slug': slug,
          'name': 'Marijana Šarolić Robić',
          'episode_count': 17,
          'channel_count': 17,
          'is_virtual_channel': true,
          'latest_episode': {
            'youtube_id': 'bkp-0X4aG9E',
            'date': date,
            'title': 'AI revolucija',
          },
        },
      ],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('namespace ključeva', () {
    test('osoba i kanal ne kolidiraju ni kad se id poklapa', () {
      expect(personFollowKey('marijana-sarolic-robic'),
          'person:marijana-sarolic-robic');
      expect(channelFollowKey('slijedi_svoj_poziv_2'),
          'channel:slijedi_svoj_poziv_2');
      expect(personFollowKey('n1'), isNot(channelFollowKey('n1')));
    });

    test('slug osobe se čuva DOSLOVNO (bez -↔_ transformacije kanala)', () {
      expect(personSlugFromFollowKey(personFollowKey('don-tomislav-lukac')),
          'don-tomislav-lukac');
      expect(channelIdFromFollowKey(channelFollowKey('muzevni_budite')),
          'muzevni_budite');
    });

    test('parsiranje vraća null za tuđi namespace', () {
      expect(personSlugFromFollowKey('channel:n1'), isNull);
      expect(channelIdFromFollowKey('person:zeljka-markic'), isNull);
      expect(personSlugFromFollowKey('smeće'), isNull);
    });
  });

  group('isNewerThanSeen', () {
    test('bez viđenog datuma je sve novo', () {
      expect(isNewerThanSeen('2026-06-24', null), isTrue);
      expect(isNewerThanSeen('2026-06-24', ''), isTrue);
    });

    test('stroga usporedba — isti datum nije novo', () {
      expect(isNewerThanSeen('2026-06-24', '2026-06-24'), isFalse);
      expect(isNewerThanSeen('2026-06-25', '2026-06-24'), isTrue);
      expect(isNewerThanSeen('2026-06-23', '2026-06-24'), isFalse);
    });

    test('bez datuma epizode nema obavijesti', () {
      expect(isNewerThanSeen(null, null), isFalse);
      expect(isNewerThanSeen('', '2020-01-01'), isFalse);
    });
  });

  group('FollowService', () {
    late FollowService follows;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FollowService.instance.debugReset();
      follows = FollowService.instance;
    });
    tearDown(FollowService.instance.debugReset);

    test('default je prazno i „ne pratim"', () async {
      await follows.ensureLoaded();
      expect(follows.isLoaded, isTrue);
      expect(follows.all, isEmpty);
      expect(follows.isFollowingSync(personFollowKey('x')), isFalse);
    });

    test('toggle vraća novo stanje i javlja listenerima', () async {
      var notified = 0;
      void listener() => notified++;
      follows.addListener(listener);
      addTearDown(() => follows.removeListener(listener));

      final key = personFollowKey('marijana-sarolic-robic');
      expect(await follows.toggle(key), isTrue);
      expect(follows.isFollowingSync(key), isTrue);
      expect(await follows.toggle(key), isFalse);
      expect(follows.isFollowingSync(key), isFalse);
      // 2 × toggle + prvo učitavanje popisa.
      expect(notified, greaterThanOrEqualTo(2));
    });

    test('praćenje preživi reload (novi servis čita isti zapis)', () async {
      await follows.toggle(personFollowKey('zeljka-markic'));
      await follows.toggle(channelFollowKey('muzevni_budite'));

      // Simulira novi session: isti storage, prazno memorijsko stanje.
      follows.debugReset();
      await follows.ensureLoaded();

      expect(follows.personSlugs, ['zeljka-markic']);
      expect(follows.channelIds, ['muzevni_budite']);
    });

    test('zapis ide u dogovoreni ključ, kao JSON lista', () async {
      await follows.toggle(channelFollowKey('n1'));
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kFollowsStorageKey);
      expect(raw, isNotNull);
      expect(jsonDecode(raw!), ['channel:n1']);
    });

    test('pokvaren zapis ne ruši servis — praćenja jednostavno nema', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kFollowsStorageKey: '{ovo nije json',
        kFollowsSeenStorageKey: '[]',
      });
      follows.debugReset();
      await follows.ensureLoaded();
      expect(follows.all, isEmpty);
      expect(follows.lastSeenDate('person:x'), isNull);
    });

    test('markSeen gasi „novo" i ne vraća se na stariji datum', () async {
      final key = personFollowKey('marijana-sarolic-robic');
      await follows.toggle(key);

      // Prije ijednog otvaranja je najnovija epizoda „novo".
      expect(follows.hasUnseen(key, '2026-06-24'), isTrue);

      await follows.markSeen(key, '2026-06-24');
      expect(follows.hasUnseen(key, '2026-06-24'), isFalse);
      expect(follows.hasUnseen(key, '2026-07-01'), isTrue);

      // Otvaranje arhivske epizode ne smije vratiti rail.
      await follows.markSeen(key, '2020-01-01');
      expect(follows.lastSeenDate(key), '2026-06-24');

      // Prazan datum je no-op (stari backend bez `latest_episode.date`).
      await follows.markSeen(key, '');
      expect(follows.lastSeenDate(key), '2026-06-24');
    });

    test('viđeni datumi preživljavaju prestanak praćenja', () async {
      final key = channelFollowKey('n1');
      await follows.toggle(key);
      await follows.markSeen(key, '2026-06-24');
      await follows.toggle(key); // unfollow

      follows.debugReset();
      await follows.ensureLoaded();

      // Ponovno praćenje ne smije vratiti već viđenu epizodu u rail.
      expect(follows.lastSeenDate(key), '2026-06-24');
      expect(follows.hasUnseen(key, '2026-06-24'), isFalse);
    });

    test('viđeni datumi idu u zaseban ključ', () async {
      final key = personFollowKey('x');
      await follows.markSeen(key, '2026-01-01');
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString(kFollowsSeenStorageKey)!),
          {'person:x': '2026-01-01'});
    });
  });

  group('FollowButton', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FollowService.instance.debugReset();
      PersonChannelFlag.instance.debugReset();
    });
    tearDown(() {
      FollowService.instance.debugReset();
      PersonChannelFlag.instance.debugReset();
    });

    Widget button() => _wrap(FollowButton(
          followKey: personFollowKey('marijana-sarolic-robic'),
          followLabel: 'Prati',
          followingLabel: 'Pratiš',
          semanticsIdentifier: 'person-follow-button',
        ));

    testWidgets('bez flaga se ne prikazuje (ekran izgleda kao danas)',
        (tester) async {
      await tester.pumpWidget(button());
      await tester.pumpAndSettle();
      expect(find.text('Prati'), findsNothing);
    });

    testWidgets('s flagom tap prebacuje stanje i perzistira', (tester) async {
      await PersonChannelFlag.instance.setOn(true);
      await tester.pumpWidget(button());
      await tester.pumpAndSettle();

      expect(find.text('Prati'), findsOneWidget);
      await tester.tap(find.text('Prati'));
      await tester.pumpAndSettle();

      expect(find.text('Pratiš'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString(kFollowsStorageKey)!),
          ['person:marijana-sarolic-robic']);
    });
  });

  group('FollowedRail', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FollowService.instance.debugReset();
      PersonChannelFlag.instance.debugReset();
      personIndexCache.debugReset();
    });
    tearDown(() {
      FollowService.instance.debugReset();
      PersonChannelFlag.instance.debugReset();
      personIndexCache.debugReset();
    });

    Widget rail(List<String> opened) => _wrap(FollowedRail(
          isMobile: true,
          onVideoTap: opened.add,
        ));

    testWidgets('bez praćenja se ne prikazuje', (tester) async {
      await PersonChannelFlag.instance.setOn(true);
      personIndexCache.debugSetIndex(
          _indexWith(slug: 'marijana-sarolic-robic', date: '2026-06-24'));

      await tester.pumpWidget(rail([]));
      await tester.pumpAndSettle();
      expect(find.text('NOVO OD PRAĆENIH'), findsNothing);
    });

    testWidgets('praćena osoba s neviđenom epizodom uđe u rail; tap je označi',
        (tester) async {
      await PersonChannelFlag.instance.setOn(true);
      final key = personFollowKey('marijana-sarolic-robic');
      await FollowService.instance.toggle(key);
      personIndexCache.debugSetIndex(
          _indexWith(slug: 'marijana-sarolic-robic', date: '2026-06-24'));

      final opened = <String>[];
      await tester.pumpWidget(rail(opened));
      await tester.pumpAndSettle();

      expect(find.text('NOVO OD PRAĆENIH'), findsOneWidget);
      expect(find.text('AI revolucija'), findsOneWidget);

      await tester.tap(find.text('AI revolucija'));
      await tester.pumpAndSettle();

      expect(opened, ['bkp-0X4aG9E']);
      expect(FollowService.instance.lastSeenDate(key), '2026-06-24');
      // Viđena epizoda više nije "novo" → rail se sam sklonio.
      expect(find.text('NOVO OD PRAĆENIH'), findsNothing);
    });

    testWidgets('bez flaga rail ostaje skriven i s praćenjem', (tester) async {
      await FollowService.instance.toggle(personFollowKey('marijana-sarolic-robic'));
      personIndexCache.debugSetIndex(
          _indexWith(slug: 'marijana-sarolic-robic', date: '2026-06-24'));

      await tester.pumpWidget(rail([]));
      await tester.pumpAndSettle();
      expect(find.text('NOVO OD PRAĆENIH'), findsNothing);
    });
  });
}
