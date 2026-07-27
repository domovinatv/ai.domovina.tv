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
  });
}
