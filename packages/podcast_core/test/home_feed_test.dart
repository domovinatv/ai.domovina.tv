import 'package:flutter_test/flutter_test.dart';

import 'package:podcast_core/brand/app_brand.dart';
import 'package:podcast_core/brand/domovina_brand.dart';
import 'package:podcast_core/models/channel_detail.dart';
import 'package:podcast_core/screens/home/home_feed.dart';

import 'support/test_brands.dart';

/// Fiksno „danas” za ranker — fixture s apsolutnim datumima je inače nakon
/// 14 dana ispadao iz tiera 1 (test je tako i pao 2026-08-13). Dan u godini
/// je 152 (paran), pa dnevna rotacija karusela s dva kandidata kreće od
/// ranga 1.
final DateTime _now = DateTime(2026, 6, 2, 12);

/// Datum `n` dana prije [_now], u obliku iz channel listinga (`YYYY-MM-DD`).
String _daysBefore(int n) =>
    _now.subtract(Duration(days: n)).toIso8601String().split('T').first;

ChannelVideo _video(
  String id, {
  String? date,
  bool hasArticle = false,
  bool hasMagisterium = false,
  int? magScore,
  bool? hasSummary,
  bool? hasDiarized,
  List<String> speakers = const [],
}) =>
    ChannelVideo(
      id: id,
      title: 'Episode $id',
      date: date,
      magisteriumScore: magScore,
      speakers: speakers,
      pipeline: VideoPipeline(
        hasTranscript: hasArticle,
        hasDiarized: hasDiarized ?? hasArticle,
        hasSummary: hasSummary ?? hasArticle,
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

  group('HomeFeed.freshlyArrived', () {
    String daysAgo(int n) =>
        DateTime.now().subtract(Duration(days: n)).toIso8601String().split('T').first;

    test('vraća samo neobrađene (has_article == false) epizode', () {
      final all = [
        _fv(_video('ready', date: daysAgo(1), hasArticle: true)),
        _fv(_video('raw1', date: daysAgo(2))),
        _fv(_video('raw2', date: daysAgo(3))),
      ];

      final ids =
          HomeFeed.freshlyArrived(all).map((v) => v.video.id).toList();

      expect(ids, isNot(contains('ready')));
      expect(ids, ['raw1', 'raw2']); // sortirano po datumu desc
    });

    test('izostavlja stare neobrađene stubove (izvan maxAgeDays)', () {
      final all = [
        _fv(_video('fresh', date: daysAgo(3))),
        _fv(_video('stari', date: daysAgo(120))),
      ];

      final ids = HomeFeed.freshlyArrived(all, maxAgeDays: 30)
          .map((v) => v.video.id)
          .toList();

      expect(ids, ['fresh']);
    });

    test('izostavlja epizode bez datuma', () {
      final all = [
        _fv(_video('nodate')), // date == null
        _fv(_video('fresh', date: daysAgo(1))),
      ];

      final ids =
          HomeFeed.freshlyArrived(all).map((v) => v.video.id).toList();

      expect(ids, ['fresh']);
    });

    test('excludeFeatured uklanja featured epizodu', () {
      final featured = _fv(_video('raw1', date: daysAgo(1)));
      final all = [
        featured,
        _fv(_video('raw2', date: daysAgo(2))),
      ];

      final ids = HomeFeed.freshlyArrived(all, excludeFeatured: featured)
          .map((v) => v.video.id)
          .toList();

      expect(ids, ['raw2']);
    });
  });

  group('HomeFeed.pickFeatured', () {
    test('Tier 4 newest fallback bira spremnu, ne neobrađenu epizodu', () {
      final all = [
        _fv(_video('raw', date: _daysBefore(1))), // najnovija ali bez članka
        _fv(_video('ready', date: _daysBefore(12), hasArticle: true)),
      ];

      final pick = HomeFeed.pickFeatured(all,
          score: HomeFeed.magisteriumScore, now: _now);

      expect(pick, isNotNull);
      expect(pick!.reason, FeaturedReason.newest);
      expect(pick.video.video.id, 'ready');
    });

    test('preferira hi-quality magisterium prije Tier 4', () {
      final all = [
        _fv(_video('raw', date: _daysBefore(1))),
        _fv(_video('mag',
            date: _daysBefore(7),
            hasArticle: true,
            hasMagisterium: true,
            magScore: 88)),
      ];

      final pick = HomeFeed.pickFeatured(all,
          score: HomeFeed.magisteriumScore, now: _now);

      expect(pick!.video.video.id, 'mag');
      expect(pick.reason, FeaturedReason.hiQualityRecent);
      expect(pick.magisteriumScore, 88);
    });

    test('hi-quality stariji od 14 dana pada u Tier 2', () {
      final all = [
        _fv(_video('mag',
            date: _daysBefore(15),
            hasArticle: true,
            hasMagisterium: true,
            magScore: 88)),
      ];

      final pick = HomeFeed.pickFeatured(all,
          score: HomeFeed.magisteriumScore, now: _now);

      expect(pick!.reason, FeaturedReason.hiQuality);
    });

    test('isti ulaz i isti now daju isti izbor (deterministički)', () {
      final all = [
        for (var i = 0; i < 8; i++)
          _fv(_video('mag$i',
              date: _daysBefore(i),
              hasArticle: true,
              hasMagisterium: true,
              magScore: 70 + i)),
      ];

      final a = HomeFeed.pickFeaturedCarousel(all,
          score: HomeFeed.magisteriumScore, now: _now);
      final b = HomeFeed.pickFeaturedCarousel(all,
          score: HomeFeed.magisteriumScore, now: _now);

      expect(a.map((p) => p.video.video.id).toList(),
          b.map((p) => p.video.video.id).toList());
      expect(a.first.reason, FeaturedReason.hiQualityRecent);
    });
  });

  group('HomeFeed.pickFeatured bez domenske ocjene (score == null)', () {
    List<String> ids(List<FeaturedPick> picks) =>
        picks.map((p) => p.video.video.id).toList();

    test('Magisterium ocjena se ignorira; rangira potpunost obrade', () {
      final all = [
        // Visoka Magisterium ocjena, ali bez poglavlja i govornika.
        _fv(_video('mag',
            date: _daysBefore(1),
            hasArticle: true,
            hasSummary: false,
            hasDiarized: false,
            hasMagisterium: true,
            magScore: 95)),
        // Potpuno obrađena (članak + sažetak + diarizacija), bez ocjene.
        _fv(_video('full', date: _daysBefore(5), hasArticle: true)),
      ];

      final picks = HomeFeed.pickFeaturedCarousel(all,
          useDefaultScore: false, now: _now);

      expect(ids(picks), ['full']);
      expect(picks.first.reason, FeaturedReason.hiQualityRecent);
      expect(picks.first.magisteriumScore, isNull);
    });

    test('Tier 1: potpuno obrađene ≤ 14 dana, najsvježija prva', () {
      final all = [
        _fv(_video('old', date: _daysBefore(30), hasArticle: true)),
        _fv(_video('mid', date: _daysBefore(9), hasArticle: true)),
        _fv(_video('new', date: _daysBefore(2), hasArticle: true)),
        _fv(_video('raw', date: _daysBefore(0))),
      ];

      final picks = HomeFeed.pickFeaturedCarousel(all,
          useDefaultScore: false, now: _now);

      expect(picks.map((p) => p.reason).toSet(),
          {FeaturedReason.hiQualityRecent});
      expect(picks.first.candidatePool, 2); // old je izvan 14 dana
      expect(ids(picks), ['new', 'mid']);
      // Ocjena je svima 100 → kombinirano = 60 + svježina × 0,4.
      expect(picks.first.combinedScore, closeTo(60 + 86 * 0.4, 1e-9));
    });

    test('Tier 2: potpuno obrađene starije od 14 dana, datum desc', () {
      final all = [
        _fv(_video('older', date: _daysBefore(40), hasArticle: true)),
        _fv(_video('old', date: _daysBefore(20), hasArticle: true)),
        _fv(_video('partial', date: _daysBefore(1),
            hasArticle: true, hasSummary: false, hasDiarized: false)),
      ];

      final picks = HomeFeed.pickFeaturedCarousel(all,
          useDefaultScore: false, now: _now);

      expect(ids(picks), ['old', 'older']);
      expect(picks.first.reason, FeaturedReason.hiQuality);
    });

    test('Tier 3: članak + poglavlja ILI govornici, datum desc', () {
      final all = [
        _fv(_video('chapters', date: _daysBefore(3),
            hasArticle: true, hasSummary: true, hasDiarized: false)),
        _fv(_video('speakers', date: _daysBefore(1),
            hasArticle: true, hasSummary: false, hasDiarized: false,
            speakers: ['Ana'])),
        _fv(_video('bare', date: _daysBefore(0),
            hasArticle: true, hasSummary: false, hasDiarized: false)),
      ];

      final picks = HomeFeed.pickFeaturedCarousel(all,
          useDefaultScore: false, now: _now);

      expect(ids(picks), ['speakers', 'chapters']);
      expect(picks.first.reason, FeaturedReason.anyMagisterium);
    });

    test('Tier 4: samo članak → najnovija spremna', () {
      final all = [
        _fv(_video('raw', date: _daysBefore(0))),
        _fv(_video('bare2', date: _daysBefore(2),
            hasArticle: true, hasSummary: false, hasDiarized: false)),
        _fv(_video('bare1', date: _daysBefore(1),
            hasArticle: true, hasSummary: false, hasDiarized: false)),
      ];

      final picks = HomeFeed.pickFeaturedCarousel(all,
          useDefaultScore: false, now: _now);

      expect(ids(picks), ['bare1', 'bare2']);
      expect(picks.first.reason, FeaturedReason.newest);
    });
  });

  group('HomeFeed.defaultScore prati flags.domainScore', () {
    tearDown(() => AppBrand.init(domovinaBrand));

    final all = [
      _fv(_video('mag',
          date: _daysBefore(1),
          hasArticle: true,
          hasSummary: false,
          hasDiarized: false,
          hasMagisterium: true,
          magScore: 95)),
      _fv(_video('full', date: _daysBefore(5), hasArticle: true)),
    ];

    test('DOMOVINA (flag upaljen) rangira po Magisterium ocjeni', () {
      AppBrand.init(domovinaBrand);
      expect(HomeFeed.defaultScore, isNotNull);

      final pick = HomeFeed.pickFeatured(all, now: _now);

      expect(pick!.video.video.id, 'mag');
      expect(pick.magisteriumScore, 95);
    });

    test('brend bez domenske ocjene rangira po potpunosti obrade', () {
      AppBrand.init(brandWithoutDomainScore());
      expect(HomeFeed.defaultScore, isNull);

      final pick = HomeFeed.pickFeatured(all, now: _now);

      expect(pick!.video.video.id, 'full');
      expect(pick.magisteriumScore, isNull);
    });
  });
}
