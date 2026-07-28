import 'package:flutter_test/flutter_test.dart';

import 'package:domovina_ai/models/person_hub.dart';

/// Kontrakt person hub modela prema `GET mcp.domovina.ai/api/person/{slug}`.
/// Ključno: osoba koja se SAMO spominje (nikad gost — bl. Ivan Merz) je valjan
/// profil, ne prazno stanje; njezine agregacije dolaze iz `mention_*` polja.
void main() {
  group('personSlug', () {
    test('folda dijakritiku i razmake', () {
      expect(personSlug('Željka Markić'), 'zeljka-markic');
      expect(personSlug('don Tomislav Lukač'), 'don-tomislav-lukac');
      expect(personSlug('  Ivan   Merz '), 'ivan-merz');
    });

    test('dvočlano prezime i rubni znakovi', () {
      expect(
        personSlug('Marijana Šarolić Robić'),
        'marijana-sarolic-robic',
      );
      expect(personSlug('Đurđica Ćuk-Žižić'), 'durdica-cuk-zizic');
      expect(personSlug('  --Ivan--  '), 'ivan');
    });

    test('ASCII-fold spaja "Mič" i "Mić" u isti slug (poznata kolizija)', () {
      // Zato backend šalje `ambiguous: true` kad jedan slug pokrije više
      // kanonskih imena — vidi rizik "Kolizija slugova" u planu.
      expect(personSlug('Ana Mič'), personSlug('Ana Mić'));
    });
  });

  group('PersonHub.fromJson', () {
    test('mention-only osoba je valjan profil, ne prazno stanje', () {
      final hub = PersonHub.fromJson({
        'name': 'Ivan Merz',
        'slug': 'ivan-merz',
        'avatar_url': null,
        'channel_count': 0,
        'episode_count': 0,
        'channels': [],
        'episodes': [],
        'timeline': [],
        'mentions': [
          {
            'youtube_id': 'DgxNotap0gw',
            'title': 'Svetost bl. Ivana Merza',
            'channel': 'mladi_za_domovinu',
            'upload_date': '2026-05-06',
            'first_ts': 1005,
            'deep_link': 'https://domovina.ai/v/DgxNotap0gw/t/1005',
          },
          {
            'youtube_id': 'fIdYMq-CNe0',
            'title': 'Merzfest 2025.',
            'channel': 'mladi_za_domovinu',
            'upload_date': '2026-05-07',
            'first_ts': 0,
            'deep_link': 'https://domovina.ai/v/fIdYMq-CNe0',
          },
        ],
        'mention_episode_count': 2,
        'mention_channels': [
          {'channel': 'mladi_za_domovinu', 'count': 2},
        ],
        'mention_timeline': [
          {'month': '2026-05', 'count': 2},
        ],
      });

      expect(hub.isMentionOnly, isTrue);
      expect(hub.mentions.length, 2);
      expect(hub.mentionCount, 2);
      expect(hub.mentionChannels.single.channel, 'mladi_za_domovinu');
      expect(hub.mentionTimeline.single.month, '2026-05');
      // Spomen s razriješenim timestampom vodi na točan trenutak; bez njega na
      // cijelu epizodu.
      expect(hub.mentions[0].routePath, '/v/DgxNotap0gw/t/1005');
      expect(hub.mentions[1].routePath, '/v/fIdYMq-CNe0');
    });

    test('govornik bez spomena nije mention-only', () {
      final hub = PersonHub.fromJson({
        'name': 'Don Tomislav Lukač',
        'slug': 'don-tomislav-lukac',
        'channel_count': 1,
        'episode_count': 1,
        'channels': [
          {'channel': 'radio_mreznica', 'count': 1},
        ],
        'episodes': [
          {
            'youtube_id': 'itkHwGmV2e4',
            'title': 'PODCAST MREŽNICA',
            'channel': 'radio_mreznica',
            'upload_date': '2025-10-04',
            'first_ts': 20,
            'deep_link': 'https://domovina.ai/v/itkHwGmV2e4/t/20',
          },
        ],
        'timeline': [
          {'month': '2025-10', 'count': 1},
        ],
      });

      expect(hub.isMentionOnly, isFalse);
      expect(hub.mentions, isEmpty);
      // Backend prije v0.8.0 ne šalje mention_* polja → prazne liste, ne crash.
      expect(hub.mentionChannels, isEmpty);
      expect(hub.mentionTimeline, isEmpty);
      expect(hub.channels.single.channelRouteSlug, 'radio-mreznica');
    });

    test('stari odgovor (bez ijednog novog polja) daje današnje ponašanje', () {
      final hub = PersonHub.fromJson({
        'name': 'Don Tomislav Lukač',
        'slug': 'don-tomislav-lukac',
        'channel_count': 1,
        'episode_count': 1,
        'channels': [
          {'channel': 'radio_mreznica', 'count': 1},
        ],
        'episodes': [
          {
            'youtube_id': 'itkHwGmV2e4',
            'title': 'PODCAST MREŽNICA',
            'channel': 'radio_mreznica',
            'upload_date': '2025-10-04',
            'first_ts': 20,
            'deep_link': 'https://domovina.ai/v/itkHwGmV2e4/t/20',
          },
        ],
        'timeline': [
          {'month': '2025-10', 'count': 1},
        ],
      });

      // Kanal-forma se NE aktivira dok backend ne kaže da smije.
      expect(hub.isVirtualChannel, isFalse);
      expect(hub.optout, isFalse);
      expect(hub.ambiguous, isFalse);
      expect(hub.cameoEpisodes, isEmpty);
      expect(hub.cameoEpisodeCount, 0);
      expect(hub.avgMagisteriumScore, isNull);
      // Bez `speaking_seconds` epizoda ostaje u glavnom popisu — cameo bi je
      // tiho sakrio.
      expect(hub.episodes.single.tier, PersonEpisodeTier.primary);
      expect(hub.primaryEpisodes.length, 1);
      expect(hub.cameoAppearances, isEmpty);
      // Nema `total_duration_seconds` ni `duration_seconds` → 0, ne crash.
      expect(hub.totalDurationSeconds, 0);
      expect(hub.durationDisplay, '0h 0m');
      // Godine se izvedu iz upload_date kad ih backend ne pošalje.
      expect(hub.firstYear, 2025);
      expect(hub.lastYear, 2025);
      // Izvorni kanal bez `channel_tracked` nije klikabilan.
      expect(hub.episodes.single.channelTracked, isFalse);
      expect(hub.episodes.single.channelRoutePath, isNull);
      expect(hub.episodes.single.channelDisplayName, 'radio_mreznica');
    });
  });

  group('classifyPersonEpisodeTier', () {
    test('bez mjerenja govora je primary (graceful na stari backend)', () {
      expect(
        classifyPersonEpisodeTier(durationSeconds: 3600),
        PersonEpisodeTier.primary,
      );
      expect(classifyPersonEpisodeTier(), PersonEpisodeTier.primary);
    });

    test('granica udjela 0,15 je inkluzivna', () {
      // Epizoda od 1000 s: 150 s = točno 15 %. Ispod 300 s je, pa apsolutni
      // prag ne sudjeluje — mjeri se čisti udio.
      expect(
        classifyPersonEpisodeTier(speakingSeconds: 150, durationSeconds: 1000),
        PersonEpisodeTier.primary,
      );
      expect(
        classifyPersonEpisodeTier(speakingSeconds: 149, durationSeconds: 1000),
        PersonEpisodeTier.cameo,
      );
    });

    test('granica 300 s je inkluzivna i neovisna o udjelu', () {
      // 300 / 7200 = 4,2 % — pada na udjelu, prolazi na apsolutnom pragu.
      expect(
        classifyPersonEpisodeTier(speakingSeconds: 300, durationSeconds: 7200),
        PersonEpisodeTier.primary,
      );
      expect(
        classifyPersonEpisodeTier(speakingSeconds: 299, durationSeconds: 7200),
        PersonEpisodeTier.cameo,
      );
    });

    test('eksplicitan speaking_share pobjeđuje izračun iz trajanja', () {
      expect(
        classifyPersonEpisodeTier(
          speakingSeconds: 60,
          durationSeconds: 0, // dijeljenje s nulom se ne smije dogoditi
          speakingShare: 0.4,
        ),
        PersonEpisodeTier.primary,
      );
      expect(
        classifyPersonEpisodeTier(speakingShare: 0.02),
        PersonEpisodeTier.cameo,
      );
    });

    test('backendov tier pobjeđuje klijentsku klasifikaciju', () {
      final ep = PersonEpisode.fromJson({
        'youtube_id': 'x1',
        'channel': 'n1',
        'upload_date': '2026-01-01',
        'duration_seconds': 3600,
        'speaking_seconds': 30, // klijentski bi bio cameo
        'tier': 'primary', // ručni force_primary override
      });
      expect(ep.tier, PersonEpisodeTier.primary);
    });
  });

  group('PersonHub — virtualni kanal', () {
    Map<String, dynamic> hubJson({
      bool virtual = true,
      bool ambiguous = false,
      bool optout = false,
    }) =>
        {
          'name': 'Marijana Šarolić Robić',
          'slug': 'marijana-sarolic-robic',
          'channel_count': 3,
          'episode_count': 3,
          'is_virtual_channel': virtual,
          'ambiguous': ambiguous,
          'optout': optout,
          'total_duration_seconds': 49151,
          'channels': const [],
          'episodes': const [],
          'timeline': const [],
        };

    test('durationDisplay za 49 151 s daje "13h 39m"', () {
      expect(PersonHub.fromJson(hubJson()).durationDisplay, '13h 39m');
      expect(personDurationDisplay(0), '0h 0m');
      expect(personDurationDisplay(3599), '0h 59m');
    });

    test('ambiguous gasi kanal-formu', () {
      expect(PersonHub.fromJson(hubJson()).isVirtualChannel, isTrue);
      expect(
        PersonHub.fromJson(hubJson(ambiguous: true)).isVirtualChannel,
        isFalse,
      );
    });

    test('optout gasi kanal-formu, ali profil i dalje postoji', () {
      final hub = PersonHub.fromJson(hubJson(optout: true));
      expect(hub.isVirtualChannel, isFalse);
      expect(hub.optout, isTrue);
      expect(hub.name, 'Marijana Šarolić Robić');
    });

    test('cameo epizode se ne miješaju u glavni popis', () {
      final hub = PersonHub.fromJson({
        'name': 'Marijana Šarolić Robić',
        'slug': 'marijana-sarolic-robic',
        'channel_count': 2,
        'episode_count': 1,
        'is_virtual_channel': true,
        'cameo_episode_count': 2,
        'channels': const [],
        'timeline': const [],
        'episodes': [
          {
            'youtube_id': 'primary1',
            'channel': 'n1',
            'upload_date': '2022-04-01',
            'duration_seconds': 3076,
            'speaking_seconds': 1488,
            'tier': 'primary',
          },
          // Backend šalje samo primary u episodes[], ali ako se cameo provuče,
          // filtriramo ga i klijentski.
          {
            'youtube_id': 'sneaky',
            'channel': 'n1',
            'upload_date': '2022-04-02',
            'duration_seconds': 7200,
            'speaking_seconds': 40,
          },
        ],
        'cameo_episodes': [
          {
            'youtube_id': 'cameo1',
            'channel': 'lider',
            'upload_date': '2021-01-01',
            'duration_seconds': 4000,
            'speaking_seconds': 90,
            'tier': 'cameo',
          },
        ],
      });

      expect(hub.primaryEpisodes.map((e) => e.youtubeId), ['primary1']);
      expect(hub.cameoAppearances.map((e) => e.youtubeId), ['sneaky', 'cameo1']);
      expect(hub.cameoEpisodeCount, 2);
    });

    test('agregati se izvedu kad ih backend ne pošalje', () {
      final hub = PersonHub.fromJson({
        'name': 'X',
        'slug': 'x',
        'channel_count': 2,
        'episode_count': 2,
        'channels': const [],
        'timeline': const [],
        'episodes': [
          {
            'youtube_id': 'a',
            'channel': 'n1',
            'upload_date': '2020-04-20',
            'duration_seconds': 1000,
            'magisterium_score': 80,
          },
          {
            'youtube_id': 'b',
            'channel': 'lider',
            'upload_date': '2026-06-24',
            'duration_seconds': 500,
            'magisterium_score': 71,
          },
        ],
      });

      expect(hub.totalDurationSeconds, 1500);
      expect(hub.avgMagisteriumScore, 76); // (80+71)/2 = 75,5 → 76
      expect(hub.firstYear, 2020);
      expect(hub.lastYear, 2026);
    });
  });
}
