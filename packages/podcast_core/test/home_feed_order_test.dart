import 'dart:math';

import 'package:podcast_core/models/channel_detail.dart';
import 'package:podcast_core/screens/home/home_feed.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rail „Najnovije epizode" ne smije ovisiti o redoslijedu kojim su listinzi
/// kanala stigli. `date` je dan, pa epizode istog dana imaju jednak ključ;
/// bez tie-breaka su se premetale sa svakim novim listingom (prijava
/// 9.10.2026.).
void main() {
  FeedVideo ep(String id, String channel, String date) => (
        channelId: channel,
        channelName: channel,
        video: ChannelVideo(
          id: id,
          title: id,
          date: date,
          // bit 3 = has_article, bit 4 = has_magisterium
          pipeline: VideoPipeline.fromBits(0x18),
          magisteriumScore: 80,
        ),
      );

  final pool = [
    ep('a1', 'lood', '2026-10-08'),
    ep('b1', 'rastuci', '2026-10-08'),
    ep('c1', 'mladi', '2026-10-07'),
    ep('d1', 'cuspajz', '2026-10-07'),
    ep('e1', 'lood', '2026-10-06'),
    ep('f1', 'radio', '2026-10-06'),
    ep('g1', 'budi', '2026-10-06'),
  ];

  List<String> ids(List<FeedVideo> l) => [for (final v in l) v.video.id];

  test('latestEpisodes: isti bazen u bilo kojem redoslijedu → isti rail', () {
    final expected = ids(HomeFeed.latestEpisodes(pool, limit: 12));
    expect(expected, ['a1', 'b1', 'c1', 'd1', 'e1', 'f1', 'g1']);
    for (var seed = 0; seed < 20; seed++) {
      final shuffled = List<FeedVideo>.from(pool)..shuffle(Random(seed));
      expect(ids(HomeFeed.latestEpisodes(shuffled, limit: 12)), expected,
          reason: 'seed $seed');
    }
  });

  test('hero: redoslijed ne ovisi o pristizanju', () {
    final a = HomeFeed.pickFeaturedCarousel(pool);
    final b = HomeFeed.pickFeaturedCarousel(pool.reversed.toList());
    expect([for (final p in a) p.video.video.id],
        [for (final p in b) p.video.video.id]);
  });
}
