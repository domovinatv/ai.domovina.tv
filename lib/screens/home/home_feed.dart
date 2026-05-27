import '../../models/channel_detail.dart';
import '../../services/channel_cache.dart';

/// Cross-channel video s denormaliziranim channel kontekstom.
typedef FeedVideo = ({String channelId, String channelName, ChannelVideo video});

/// Razlog zbog kojeg je epizoda izabrana kao featured.
enum FeaturedReason {
  /// Tier 1: hasMagisterium, score ≥ 70, ≤ 14 dana. Najbolji slučaj.
  hiQualityRecent,

  /// Tier 2: hasMagisterium, score ≥ 70, bilo koji datum.
  hiQuality,

  /// Tier 3: bilo koja epizoda s AI obradom (hasMagisterium).
  anyMagisterium,

  /// Tier 4: najnovija epizoda bez ikakve obrade.
  newest;

  String get shortLabel {
    switch (this) {
      case FeaturedReason.hiQualityRecent:
        return 'Najbolji izbor';
      case FeaturedReason.hiQuality:
        return 'Visoka Magisterium ocjena';
      case FeaturedReason.anyMagisterium:
        return 'AI-obrađeno';
      case FeaturedReason.newest:
        return 'Najnovije';
    }
  }
}

/// Featured pick s objasnjenjem — koristi se i za render i za "Zasto?" dialog.
class FeaturedPick {
  final FeedVideo video;
  final FeaturedReason reason;
  final int? magisteriumScore;
  final int? daysAgo;
  final double? combinedScore;
  final int candidatePool;

  const FeaturedPick({
    required this.video,
    required this.reason,
    required this.candidatePool,
    this.magisteriumScore,
    this.daysAgo,
    this.combinedScore,
  });
}

/// Logika za feed sekcije na home screenu (hero, "Najnovije", itd.).
class HomeFeed {
  HomeFeed._();

  /// Featured pick s razlogom. Algoritam (4-tier fallback):
  ///
  /// 1. **Hi-quality recent** — `hasMagisterium && score≥70 && ≤14 dana`,
  ///    sortirano po `score*0.6 + recencyScore*0.4`. Najbolji izbor jer
  ///    kombinira kvalitetu i svjezinu.
  /// 2. **Hi-quality** — `hasMagisterium && score≥70`, bilo koji datum.
  ///    Sortirano po score desc.
  /// 3. **Any magisterium** — bilo koja epizoda s AI obradom, sortirano
  ///    po datumu desc.
  /// 4. **Newest** — najnovija epizoda uopce.
  ///
  /// Vraca null ako je `all` prazan.
  static FeaturedPick? pickFeatured(List<FeedVideo> all) {
    if (all.isEmpty) return null;

    final now = DateTime.now();
    int? daysAgoFor(String? date) {
      if (date == null) return null;
      try {
        return now.difference(DateTime.parse(date)).inDays;
      } catch (_) {
        return null;
      }
    }

    double recencyScore(int? daysAgo) {
      if (daysAgo == null) return 0;
      if (daysAgo < 0) return 100;
      if (daysAgo > 14) return 0;
      return 100 - (daysAgo * 7).toDouble();
    }

    // Tier 1 — Najbolji izbor, s dnevnom rotacijom kroz top 5 kandidata.
    final hiQualityRecent = all.where((v) {
      final score = v.video.magisteriumScore ?? 0;
      final hasMag = v.video.pipeline?.hasMagisterium ?? false;
      final d = daysAgoFor(v.video.date);
      return hasMag && score >= 70 && d != null && d <= 14;
    }).toList();

    if (hiQualityRecent.isNotEmpty) {
      hiQualityRecent.sort((a, b) {
        final aScore = (a.video.magisteriumScore ?? 0) * 0.6 +
            recencyScore(daysAgoFor(a.video.date)) * 0.4;
        final bScore = (b.video.magisteriumScore ?? 0) * 0.6 +
            recencyScore(daysAgoFor(b.video.date)) * 0.4;
        return bScore.compareTo(aScore);
      });
      // Dnevna rotacija: izvuci top 5 i seedaj po danu u godini. Time se hero
      // mijenja u ponoc, ali tijekom dana je isti (deterministicki).
      final topN = hiQualityRecent.take(5).toList();
      final dayOfYear = now
          .difference(DateTime(now.year))
          .inDays;
      final picked = topN[dayOfYear % topN.length];
      final d = daysAgoFor(picked.video.date);
      final combined = (picked.video.magisteriumScore ?? 0) * 0.6 +
          recencyScore(d) * 0.4;
      return FeaturedPick(
        video: picked,
        reason: FeaturedReason.hiQualityRecent,
        magisteriumScore: picked.video.magisteriumScore,
        daysAgo: d,
        combinedScore: combined,
        candidatePool: hiQualityRecent.length,
      );
    }

    // Tier 2
    final hiQuality = all.where((v) {
      final score = v.video.magisteriumScore ?? 0;
      final hasMag = v.video.pipeline?.hasMagisterium ?? false;
      return hasMag && score >= 70;
    }).toList();
    if (hiQuality.isNotEmpty) {
      hiQuality.sort((a, b) => (b.video.magisteriumScore ?? 0)
          .compareTo(a.video.magisteriumScore ?? 0));
      final winner = hiQuality.first;
      return FeaturedPick(
        video: winner,
        reason: FeaturedReason.hiQuality,
        magisteriumScore: winner.video.magisteriumScore,
        daysAgo: daysAgoFor(winner.video.date),
        candidatePool: hiQuality.length,
      );
    }

    // Tier 3
    final magisterium = all
        .where((v) => v.video.pipeline?.hasMagisterium ?? false)
        .toList();
    if (magisterium.isNotEmpty) {
      magisterium.sort((a, b) =>
          (b.video.date ?? '').compareTo(a.video.date ?? ''));
      final winner = magisterium.first;
      return FeaturedPick(
        video: winner,
        reason: FeaturedReason.anyMagisterium,
        magisteriumScore: winner.video.magisteriumScore,
        daysAgo: daysAgoFor(winner.video.date),
        candidatePool: magisterium.length,
      );
    }

    // Tier 4
    final sorted = List<FeedVideo>.from(all)
      ..sort((a, b) => (b.video.date ?? '').compareTo(a.video.date ?? ''));
    final winner = sorted.first;
    return FeaturedPick(
      video: winner,
      reason: FeaturedReason.newest,
      magisteriumScore: winner.video.magisteriumScore,
      daysAgo: daysAgoFor(winner.video.date),
      candidatePool: all.length,
    );
  }

  /// "Najnovije epizode" rail — cross-channel sortirano po datumu desc.
  static List<FeedVideo> latestEpisodes(List<FeedVideo> all,
      {int limit = 20, FeedVideo? excludeFeatured}) {
    final filtered = excludeFeatured == null
        ? all
        : all.where((v) => v.video.id != excludeFeatured.video.id).toList();
    final sorted = List<FeedVideo>.from(filtered)
      ..sort((a, b) => (b.video.date ?? '').compareTo(a.video.date ?? ''));
    return sorted.take(limit).toList();
  }

  /// Provjeri ima li dovoljno podataka da feed nije prazan/skeleton.
  static bool hasMinimumData(ChannelCache cache) {
    if (cache.total == 0) return false;
    return cache.loaded >= (cache.total * 0.3).ceil() || cache.done;
  }
}
