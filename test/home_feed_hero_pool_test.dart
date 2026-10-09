import 'package:flutter_test/flutter_test.dart';

import 'package:domovina_ai/models/channel_detail.dart';
import 'package:domovina_ai/models/channel_index.dart';
import 'package:domovina_ai/screens/home/home_feed.dart';
import 'package:domovina_ai/services/channel_cache.dart';

/// Ugovor za [HomeFeed.heroPoolComplete]: hero se smije latchati prije kraja
/// prefetcha samo kad nijedan neučitani kanal više ne može dati tier 1
/// kandidata. Vidi `docs/2026-10-08-brzina-ucitavanja-naslovnice.md` (Q3).

final _now = DateTime(2026, 10, 9);

ChannelSummary _summary(String id, String? latestDate) =>
    ChannelSummary.fromJson({
      'id': id,
      'name': id,
      if (latestDate != null)
        'latest_video': {'id': '${id}_v', 'date': latestDate, 'title': 't'},
    });

ChannelDetail _detail(String id, List<Map<String, dynamic>> videos) =>
    ChannelDetail.fromJson({'id': id, 'name': id, 'videos': videos});

Map<String, dynamic> _video(String id, String date,
        {bool magisterium = true, int score = 80}) =>
    {
      'id': id,
      'title': id,
      'date': date,
      'magisterium_score': score,
      'pipeline': {'has_article': true, 'has_magisterium': magisterium},
    };

ChannelCache _cacheWith(List<ChannelSummary> channels) {
  final cache = ChannelCache();
  cache.seedIndexForTest(ChannelIndex(
    version: '1',
    channelCount: channels.length,
    channels: channels,
  ));
  return cache;
}

void main() {
  test('stari neučitani kanali ne drže hero kad je tier 1 popunjen', () {
    final cache = _cacheWith([
      _summary('svjez', '2026-10-05'),
      _summary('star1', '2026-08-01'),
      _summary('star2', '2026-06-01'),
    ]);
    cache.seedForTest(_detail('svjez', [_video('a', '2026-10-05')]));

    expect(HomeFeed.heroPoolComplete(cache, now: _now), isTrue);
  });

  test('neučitan kanal sa svježom epizodom drži hero', () {
    final cache = _cacheWith([
      _summary('svjez', '2026-10-05'),
      _summary('jos_svjeziji', '2026-10-08'),
    ]);
    cache.seedForTest(_detail('svjez', [_video('a', '2026-10-05')]));

    expect(HomeFeed.heroPoolComplete(cache, now: _now), isFalse);
  });

  test('prazan tier 1 traži cijeli katalog (tier 2 je „bilo koji datum")', () {
    final cache = _cacheWith([
      _summary('svjez', '2026-10-05'),
      _summary('star', '2026-01-01'),
    ]);
    // Svježa epizoda bez Magisteriuma → tier 1 prazan.
    cache.seedForTest(
        _detail('svjez', [_video('a', '2026-10-05', magisterium: false)]));

    expect(HomeFeed.heroPoolComplete(cache, now: _now), isFalse);
  });

  test('kanal bez datuma u indexu se ne smatra starim', () {
    final cache = _cacheWith([
      _summary('svjez', '2026-10-05'),
      _summary('bez_datuma', null),
    ]);
    cache.seedForTest(_detail('svjez', [_video('a', '2026-10-05')]));

    expect(HomeFeed.heroPoolComplete(cache, now: _now), isFalse);
  });

  test('byFreshness stavlja najsvježije kanale prve, bez datuma na kraj', () {
    final ordered = byFreshness([
      _summary('b', '2026-09-01'),
      _summary('none', null),
      _summary('a', '2026-10-01'),
    ]).map((c) => c.id);

    expect(ordered, ['a', 'b', 'none']);
  });
}
