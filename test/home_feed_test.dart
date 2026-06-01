import 'package:flutter_test/flutter_test.dart';

import 'package:domovina_ai/models/channel_detail.dart';
import 'package:domovina_ai/screens/home/home_feed.dart';

ChannelVideo _video(
  String id, {
  String? date,
  bool hasArticle = false,
  bool hasMagisterium = false,
  int? magScore,
}) =>
    ChannelVideo(
      id: id,
      title: 'Episode $id',
      date: date,
      magisteriumScore: magScore,
      pipeline: VideoPipeline(
        hasTranscript: hasArticle,
        hasDiarized: hasArticle,
        hasSummary: hasArticle,
        hasArticle: hasArticle,
        hasMagisterium: hasMagisterium,
      ),
    );

FeedVideo _fv(ChannelVideo v) =>
    (channelId: 'ch', channelName: 'Channel', video: v);

void main() {
  group('HomeFeed.latestEpisodes', () {
    test('izostavlja neobrađene epizode (has_article == false)', () {
      final all = [
        _fv(_video('ready1', date: '2026-05-30', hasArticle: true)),
        _fv(_video('raw', date: '2026-05-31')), // tek skinuta, bez članka
        _fv(_video('ready2', date: '2026-05-29', hasArticle: true)),
      ];

      final result = HomeFeed.latestEpisodes(all);
      final ids = result.map((v) => v.video.id).toList();

      expect(ids, isNot(contains('raw')));
      expect(ids, ['ready1', 'ready2']); // sortirano po datumu desc
    });

    test('excludeFeatured uklanja featured epizodu', () {
      final featured = _fv(_video('ready1', date: '2026-05-30', hasArticle: true));
      final all = [
        featured,
        _fv(_video('ready2', date: '2026-05-29', hasArticle: true)),
      ];

      final ids = HomeFeed.latestEpisodes(all, excludeFeatured: featured)
          .map((v) => v.video.id)
          .toList();

      expect(ids, ['ready2']);
    });
  });

  group('HomeFeed.pickFeatured', () {
    test('Tier 4 newest fallback bira spremnu, ne neobrađenu epizodu', () {
      final all = [
        _fv(_video('raw', date: '2026-05-31')), // najnovija ali bez članka
        _fv(_video('ready', date: '2026-05-20', hasArticle: true)),
      ];

      final pick = HomeFeed.pickFeatured(all);

      expect(pick, isNotNull);
      expect(pick!.reason, FeaturedReason.newest);
      expect(pick.video.video.id, 'ready');
    });

    test('preferira hi-quality magisterium prije Tier 4', () {
      final all = [
        _fv(_video('raw', date: '2026-05-31')),
        _fv(_video('mag',
            date: '2026-05-25',
            hasArticle: true,
            hasMagisterium: true,
            magScore: 88)),
      ];

      final pick = HomeFeed.pickFeatured(all);

      expect(pick!.video.video.id, 'mag');
      expect(pick.reason, FeaturedReason.hiQualityRecent);
    });
  });
}
