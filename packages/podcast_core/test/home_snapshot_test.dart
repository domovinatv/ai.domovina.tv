import 'package:flutter_test/flutter_test.dart';

import 'package:podcast_core/models/channel_detail.dart';
import 'package:podcast_core/models/channel_index.dart';
import 'package:podcast_core/models/home_snapshot.dart';
import 'package:podcast_core/screens/home/home_feed.dart';
import 'package:podcast_core/services/channel_cache.dart';

/// Ugovor `channels/data/home.json` v1 (vidi `HomeSnapshot`).
void main() {
  group('HomeSnapshot.tryParse', () {
    test('čita epizode i pipeline bitmask', () {
      final snap = HomeSnapshot.tryParse({
        'version': 1,
        'generated_at': '2026-10-09T02:30:00Z',
        'episodes': [
          {
            'c': 'hnb',
            'id': 'abc',
            'title': 'Naslov',
            'date': '2026-10-05',
            'duration_seconds': 3600.0,
            'magisterium_score': 85,
            'p': 0x1F | 0x80, // transkript…magisterium + article_en
          },
        ],
      })!;

      final e = snap.episodes.single;
      expect(e.channelId, 'hnb');
      expect(e.video.durationSeconds, 3600);
      expect(e.video.pipeline!.hasArticle, isTrue);
      expect(e.video.pipeline!.hasMagisterium, isTrue);
      expect(e.video.pipeline!.hasArticleEn, isTrue);
    });

    test('nepoznata verzija → null (klijent ide starim putem)', () {
      expect(HomeSnapshot.tryParse({'version': 2, 'episodes': []}), isNull);
      expect(HomeSnapshot.tryParse({'episodes': []}), isNull);
    });

    test('preskače zapise bez id-a ili kanala', () {
      final snap = HomeSnapshot.tryParse({
        'version': 1,
        'episodes': [
          {'id': 'bez_kanala'},
          {'c': 'x'},
          {'c': 'x', 'id': 'ok', 'p': 0},
        ],
      })!;
      expect(snap.episodes.map((e) => e.video.id), ['ok']);
    });

    test('bitovi 5 i 7 oba znače engleski članak', () {
      expect(VideoPipeline.fromBits(1 << 5).hasArticleEn, isTrue);
      expect(VideoPipeline.fromBits(1 << 7).hasArticleEn, isTrue);
      expect(VideoPipeline.fromBits(1 << 3).hasArticleEn, isFalse);
    });
  });

  group('ChannelCache s home.json', () {
    late ChannelCache cache;

    setUp(() {
      cache = ChannelCache()
        ..seedIndexForTest(ChannelIndex(
          version: '1',
          channelCount: 2,
          channels: [
            ChannelSummary.fromJson({'id': 'hnb', 'name': 'HNB'}),
            ChannelSummary.fromJson({'id': 'drugi', 'name': 'Drugi'}),
          ],
        ))
        ..seedHomeSnapshotForTest(HomeSnapshot.tryParse({
          'version': 1,
          'episodes': [
            {'c': 'hnb', 'id': 'a', 'title': 'iz snapshota', 'p': 8},
            {'c': 'drugi', 'id': 'b', 'title': 'samo snapshot', 'p': 8},
          ],
        })!);
    });

    test('feedVideos: listing ima prednost, bez duplikata, ime iz indexa', () {
      cache.seedForTest(ChannelDetail.fromJson({
        'id': 'hnb',
        'name': 'HNB',
        'videos': [
          {'id': 'a', 'title': 'iz listinga'},
        ],
      }));

      final byId = {for (final v in cache.feedVideos) v.video.id: v};
      expect(byId.length, 2);
      expect(byId['a']!.video.title, 'iz listinga');
      expect(byId['b']!.channelName, 'Drugi');
    });

    test('hero ne čeka listinge kad je home.json tu', () {
      expect(HomeFeed.heroPoolComplete(cache), isTrue);
      expect(HomeFeed.hasMinimumData(cache), isTrue);
    });

    test('findVideo nalazi epizodu koja je samo u home.json', () {
      expect(cache.findVideo('b')?.channelId, 'drugi');
    });
  });
}
