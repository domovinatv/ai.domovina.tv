import 'package:flutter_test/flutter_test.dart';

import 'package:podcast_core/brand/app_brand.dart';
import 'package:podcast_core/brand/domovina_brand.dart';
import 'package:podcast_core/models/channel_detail.dart';
import 'package:podcast_core/screens/home/home_feed.dart';

final DateTime _now = DateTime(2026, 6, 2, 12);

FeedVideo _fv(String channel, String id, String date) => (
      channelId: channel,
      channelName: channel,
      video: ChannelVideo(
        id: id,
        title: 'Episode $id',
        date: date,
        speakers: const ['A'],
        pipeline: const VideoPipeline(
          hasTranscript: true,
          hasDiarized: true,
          hasSummary: true,
          hasArticle: true,
          hasMagisterium: false,
        ),
      ),
    );

final _all = [
  _fv('big', 'b1', '2026-06-01'),
  _fv('big', 'b2', '2026-05-31'),
  _fv('big', 'b3', '2026-05-30'),
  _fv('big', 'b4', '2026-05-29'),
  _fv('big', 'b5', '2026-05-28'),
  _fv('en1', 'e1', '2026-05-20'),
  _fv('en1', 'e2', '2026-05-10'),
  _fv('en2', 'f1', '2026-04-01'),
];

List<String> _ids(Iterable<FeedVideo> v) => v.map((x) => x.video.id).toList();

void main() {
  setUp(() => AppBrand.init(domovinaBrand));

  test('DOMOVINA ne ističe kanale — karusel i rail nepromijenjeni', () {
    expect(domovinaBrand.featuredChannels, isEmpty);
    final before = HomeFeed.pickFeaturedCarousel(_all,
        now: _now, useDefaultScore: false, featuredChannels: const []);
    final withDefault =
        HomeFeed.pickFeaturedCarousel(_all, now: _now, useDefaultScore: false);
    expect(_ids(withDefault.map((p) => p.video)),
        _ids(before.map((p) => p.video)));
    expect(HomeFeed.featuredShows(_all), isEmpty);
  });

  test('istaknuti kanali dobivaju prve slideove, ostatak puni ostali', () {
    final picks = HomeFeed.pickFeaturedCarousel(_all,
        now: _now,
        useDefaultScore: false,
        featuredChannels: const ['en1', 'en2'],
        featuredSlots: 3);
    final channels = picks.map((p) => p.video.channelId).toList();
    expect(picks, hasLength(5));
    expect(channels.take(3).every((c) => c == 'en1' || c == 'en2'), isTrue);
    expect(channels.skip(3).every((c) => c == 'big'), isTrue);
  });

  test('rail istaknutih kanala ide naizmjence po kanalu', () {
    final shows =
        HomeFeed.featuredShows(_all, featuredChannels: const ['en1', 'en2']);
    expect(_ids(shows), ['e1', 'f1', 'e2']);
  });

  test('HERO_PIN stavlja zadanu epizodu prvu, bez duplikata', () {
    final picks = HomeFeed.pickFeaturedCarousel(_all, now: _now, pin: 'f1');
    final ids = picks.map((p) => p.video.video.id).toList();
    expect(ids.first, 'f1');
    expect(ids.where((id) => id == 'f1'), hasLength(1));
    expect(ids, hasLength(5));
  });

  test('HERO_PIN nepoznate epizode ne mijenja izbor', () {
    List<String> ids(String pin) => HomeFeed.pickFeaturedCarousel(_all,
            now: _now, pin: pin)
        .map((p) => p.video.video.id)
        .toList();
    expect(ids('nema'), ids(''));
  });
}
