/// Ugovor između `domovina-rag` backenda i ovog frontenda za virtualne kanale.
///
/// Ostali testovi u `person_hub_test.dart` / `person_index_test.dart` čitaju
/// RUČNO PISANE fixture iz plana — oni provjeravaju što model radi s oblikom
/// koji smo ZAMISLILI. Ovaj test čita **stvarne odgovore backenda**, uhvaćene
/// 3.9.2026. s `list-persons.ts` / `get-person.ts` puštenih nad lokalnim
/// korpusom (150 085 chunkova / 3157 epizoda):
///
///   test/fixtures/person_belavic_live.json  ← GET /api/person/tomislav-belavic
///   test/fixtures/persons_index_live.json   ← GET /api/persons (izrezak)
///
/// Razlog postojanja: producent ne verificira potrošača. Backend može
/// preimenovati polje, promijeniti tip (`0.569` vs `"0.569"`) ili prestati
/// slati ključ, a `fromJson` sve to tiho proguta u default — feature bi se
/// ugasio bez ijedne iznimke i bez ijednog crvenog testa. Zato se ovdje ne
/// provjerava samo da parsiranje ne baca, nego da su VRIJEDNOSTI stigle.
///
/// Kad se fixture regenerira, brojke ispod se moraju ažurirati zajedno s njim —
/// razilaženje znači da je backend promijenio ugovor.
library;

import 'dart:convert';
import 'dart:io';

import 'package:domovina_ai/models/person_hub.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  group('ugovor s backendom — GET /api/person/:slug', () {
    late PersonHub hub;

    setUp(() {
      hub = PersonHub.fromJson(_fixture('person_belavic_live.json'));
    });

    test('kanal-forma se aktivira', () {
      expect(hub.name, 'Tomislav Belavić');
      expect(hub.slug, 'tomislav-belavic');
      expect(hub.isVirtualChannel, isTrue);
      expect(hub.ambiguous, isFalse);
      expect(hub.optout, isFalse);
    });

    test('brojke su one koje hero prikazuje', () {
      expect(hub.episodes.length, 6);
      expect(hub.episodeCount, 6);
      expect(hub.channelCount, 6);
      expect(hub.cameoEpisodes, isEmpty);
      expect(hub.cameoEpisodeCount, 0);
      // 6 h 48 min — zbroj max(end_ts) kroz svih 6 epizoda.
      expect(hub.totalDurationSeconds, 24481);
      expect(hub.durationDisplay, '6h 48m');
      expect(hub.firstYear, 2023);
      expect(hub.lastYear, 2026);
    });

    test('svaka epizoda nosi kanal-metapodatke i mjeru nastupa', () {
      for (final e in hub.episodes) {
        expect(e.channelName, isNotEmpty,
            reason: 'chip izvornog kanala bi ostao prazan');
        expect(e.durationSeconds, isNotNull);
        expect(e.speakingSeconds, isNotNull);
        expect(e.speakingShare, isNotNull);
        expect(e.tier, PersonEpisodeTier.primary);
      }
    });

    test('svih 6 izvornih kanala je praćeno → chip smije biti klikabilan', () {
      // Ovo je razlika između linka i mrtvog teksta u UI-ju: `channel_tracked`
      // false vodi na /c/<slug> koji ne postoji.
      expect(hub.episodes.every((e) => e.channelTracked), isTrue);
      expect(
        hub.episodes.every(
          (e) => e.channelYoutubeId != null && e.channelYoutubeId!.startsWith('UC'),
        ),
        isTrue,
      );
    });

    test('deep link cilja trenutak u kojem osoba progovori, ne početak', () {
      final e = hub.episodes.firstWhere((e) => e.youtubeId == 'uixJ3kMd0XA');
      expect(e.channelName, contains('Željka Markić'));
      expect(e.channelYoutubeId, 'UCUxKo1ZDaHyXQwr3_w4FZgw');
      expect(e.firstTs, 6);
      expect(e.durationSeconds, 2865);
      expect(e.speakingSeconds, 1629);
      expect(e.speakingShare, closeTo(0.569, 0.001));
    });

    test('spomeni ostaju izvan kanala (govori vs spominje se)', () {
      expect(hub.mentionCount, 1);
      final speakingIds = hub.episodes.map((e) => e.youtubeId).toSet();
      for (final m in hub.mentions) {
        expect(speakingIds.contains(m.youtubeId), isFalse,
            reason: 'ista epizoda ne smije biti i nastup i spomen');
      }
    });
  });

  group('ugovor s backendom — GET /api/persons', () {
    late PersonIndex index;

    setUp(() {
      index = PersonIndex.fromJson(_fixture('persons_index_live.json'));
    });

    test('indeks se parsira i sve osobe su virtualni kanali', () {
      expect(index.version, '1.0');
      expect(index.persons, isNotEmpty);
      expect(index.virtualChannels.length, index.persons.length);
    });

    test('Belavić nosi iste brojke kao njegov profil', () {
      final b = index.bySlug('tomislav-belavic')!;
      expect(b.name, 'Tomislav Belavić');
      expect(b.episodeCount, 6);
      expect(b.channelCount, 6);
      expect(b.totalDurationSeconds, 24481);
      expect(b.durationDisplay, '6h 48m');
      expect(b.initials, 'TB');
      expect(b.routePath, '/p/tomislav-belavic');
    });

    test('kartica ima što prikazati: zadnja epizoda s naslovom', () {
      for (final p in index.persons) {
        expect(p.latestEpisode, isNotNull);
        expect(p.latestEpisode!.title, isNotEmpty,
            reason: 'rail „Novo od praćenih" bi prikazao praznu karticu');
        expect(p.latestEpisode!.date, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      }
    });

    test('pravilo uvrštavanja drži domaćine i rolne oznake vani', () {
      for (final p in index.persons) {
        // ≥ 3 kanala: domaćin praćenog kanala ovdje ne prolazi.
        expect(p.channelCount, greaterThanOrEqualTo(3));
        expect(p.episodeCount, greaterThanOrEqualTo(3));
        // ≥ 2 tokena u slugu: „ana", „pjevac" nisu osobe.
        expect(p.slug.split('-').where((t) => t.isNotEmpty).length,
            greaterThanOrEqualTo(2),
            reason: 'jednočlan slug skuplja nastupe više različitih ljudi');
      }
    });

    test('avg_magisterium_score je null i to se podnosi', () {
      // rag_chunks nema Magisterium ocjene; pilula se ne smije crtati praznom.
      expect(index.persons.every((p) => p.avgMagisteriumScore == null), isTrue);
    });
  });

  group('regresija — profil BEZ kanal-forme ne smije izgubiti nastupe', () {
    // Backend od 3.9.2026. dijeli nastupe: `episodes[]` = primary,
    // `cameo_episodes[]` = kratki. Izmjereno tog dana, cameo je 31,7 % svih
    // parova govornik-epizoda. Profil bez feature flaga mora izgledati TOČNO
    // kao prije uvođenja virtualnih kanala, pa crta `allAppearances`, ne
    // `episodes`. Da crta `episodes`, gotovo trećina nečijih nastupa bi tiho
    // nestala s javne stranice — bez ijedne greške i bez ijednog crvenog testa.
    PersonHub hubWithCameo() => PersonHub.fromJson({
          'name': 'Test Osoba',
          'slug': 'test-osoba',
          'channel_count': 2,
          'episode_count': 1,
          'is_virtual_channel': false,
          'episodes': [
            {
              'youtube_id': 'stari1',
              'channel': 'a',
              'upload_date': '2024-01-01',
              'tier': 'primary',
            },
          ],
          'cameo_episodes': [
            {
              'youtube_id': 'novi1',
              'channel': 'b',
              'upload_date': '2026-05-05',
              'tier': 'cameo',
            },
          ],
        });

    test('allAppearances sadrži i primary i cameo', () {
      final hub = hubWithCameo();
      expect(hub.episodes.length, 1);
      expect(hub.cameoEpisodes.length, 1);
      expect(
        hub.allAppearances.map((e) => e.youtubeId),
        containsAll(<String>['stari1', 'novi1']),
      );
    });

    test('spojeni popis je presortiran po datumu, cameo ne pada na dno', () {
      // Backend sortira svaki popis zasebno; bez presortiranja bi noviji cameo
      // nastup završio ispod starijeg primary nastupa.
      expect(hubWithCameo().allAppearances.first.youtubeId, 'novi1');
    });

    test('bez cameo nastupa lista ostaje netaknuta', () {
      final hub = PersonHub.fromJson(_fixture('person_belavic_live.json'));
      expect(hub.cameoEpisodes, isEmpty);
      expect(hub.allAppearances, same(hub.episodes));
    });
  });
}
