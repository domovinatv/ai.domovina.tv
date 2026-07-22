import '../../l10n/app_localizations.dart';
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

  String shortLabel(AppLocalizations l) {
    switch (this) {
      case FeaturedReason.hiQualityRecent:
        return l.homeReasonShortHiQualityRecent;
      case FeaturedReason.hiQuality:
        return l.homeReasonShortHiQuality;
      case FeaturedReason.anyMagisterium:
        return l.homeReasonShortAnyMagisterium;
      case FeaturedReason.newest:
        return l.homeReasonShortNewest;
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

  /// Epizoda je "spremna za homepage" kad ima generiran članak (`has_article`).
  ///
  /// Članak je zadnji AI korak prije nego pipeline uploada video + screenshotove
  /// na CDN, pa je `has_article` kanonski signal da epizoda ima sliku i sadržaj
  /// za prikaz (isti gate koristi i channel stranica). Channel index je namjerno
  /// permisivan i sadrži i tek-skinute, neobrađene epizode (`has_article:false`,
  /// bez članka/videa/slike) — homepage ih NE smije surfati u hero/"Najnovije".
  /// Channel stranica ih i dalje prikazuje, ali s oznakom "još u obradi".
  static bool isReadyForHome(FeedVideo v) =>
      v.video.pipeline?.hasArticle ?? false;

  /// Epizoda je "tek pristigla" — pipeline je skinuo info + thumbnail, ali još
  /// nije producirao članak (`has_article:false`). Gledljiva je (YouTube), ali
  /// bez sažetka/članka/Magisterium analize. Suprotno od [isReadyForHome] —
  /// ove se NE pojavljuju u "Najnovije epizode", nego u zasebnom "Upravo stiglo"
  /// railu s "U obradi" oznakom.
  static bool isFreshUnprocessed(FeedVideo v) =>
      !(v.video.pipeline?.hasArticle ?? false);

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
  ///
  /// Implementiran kao prvi element [pickFeaturedCarousel] — time je jedan-pick
  /// (npr. TV hero) uvijek identičan prvom slideu web hero karusela.
  static FeaturedPick? pickFeatured(List<FeedVideo> all) {
    final picks = pickFeaturedCarousel(all);
    return picks.isEmpty ? null : picks.first;
  }

  /// Featured **uži izbor** za hero karusel — vraca do [limit] kandidata
  /// (poredanih) umjesto jednog picka. Prvi element je isti kao [pickFeatured]
  /// (današnji dnevni pick), ostali slijede po rangu pa rotiraju natrag.
  ///
  /// Isti 4-tier fallback kao [pickFeatured]:
  /// 1. **Hi-quality recent** — `hasMagisterium && score≥70 && ≤14 dana`,
  ///    sortirano po `score*0.6 + recencyScore*0.4`; dnevna rotacija određuje
  ///    koji je kandidat prvi (hero se mijenja u ponoc, deterministicki).
  /// 2. **Hi-quality** — `hasMagisterium && score≥70`, sortirano po score desc.
  /// 3. **Any magisterium** — bilo koja AI-obrađena, sortirano po datumu desc.
  /// 4. **Newest** — najnovije spremne epizode.
  ///
  /// Vraca praznu listu ako je `all` prazan.
  static List<FeaturedPick> pickFeaturedCarousel(List<FeedVideo> all,
      {int limit = 5}) {
    if (all.isEmpty) return const [];

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

    // Tier 1 — Najbolji izbor, s dnevnom rotacijom kroz top N kandidata.
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
      // Izvuci top N i seedaj početak po danu u godini. Karusel počinje od
      // današnjeg dnevnog picka pa nastavlja po rangu (i rotira natrag), tako
      // da je prvi slide deterministicki isti tijekom dana.
      final topN = hiQualityRecent.take(limit).toList();
      final dayOfYear = now.difference(DateTime(now.year)).inDays;
      final start = dayOfYear % topN.length;
      final ordered = [...topN.sublist(start), ...topN.sublist(0, start)];
      return ordered.map((v) {
        final d = daysAgoFor(v.video.date);
        final combined =
            (v.video.magisteriumScore ?? 0) * 0.6 + recencyScore(d) * 0.4;
        return FeaturedPick(
          video: v,
          reason: FeaturedReason.hiQualityRecent,
          magisteriumScore: v.video.magisteriumScore,
          daysAgo: d,
          combinedScore: combined,
          candidatePool: hiQualityRecent.length,
        );
      }).toList();
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
      return hiQuality
          .take(limit)
          .map((v) => FeaturedPick(
                video: v,
                reason: FeaturedReason.hiQuality,
                magisteriumScore: v.video.magisteriumScore,
                daysAgo: daysAgoFor(v.video.date),
                candidatePool: hiQuality.length,
              ))
          .toList();
    }

    // Tier 3
    final magisterium = all
        .where((v) => v.video.pipeline?.hasMagisterium ?? false)
        .toList();
    if (magisterium.isNotEmpty) {
      magisterium.sort((a, b) =>
          (b.video.date ?? '').compareTo(a.video.date ?? ''));
      return magisterium
          .take(limit)
          .map((v) => FeaturedPick(
                video: v,
                reason: FeaturedReason.anyMagisterium,
                magisteriumScore: v.video.magisteriumScore,
                daysAgo: daysAgoFor(v.video.date),
                candidatePool: magisterium.length,
              ))
          .toList();
    }

    // Tier 4 — najnovije SPREMNE epizode (imaju članak). Neobrađene epizode iz
    // permisivnog channel indexa se preskaču. Fallback na cijeli `all` samo u
    // degeneriranom slučaju (nijedna epizoda nema članak — npr. svjež katalog),
    // da homepage ipak nije prazan.
    final readyPool = all.where(isReadyForHome).toList();
    final pool = readyPool.isNotEmpty ? readyPool : all;
    final sorted = List<FeedVideo>.from(pool)
      ..sort((a, b) => (b.video.date ?? '').compareTo(a.video.date ?? ''));
    return sorted
        .take(limit)
        .map((v) => FeaturedPick(
              video: v,
              reason: FeaturedReason.newest,
              magisteriumScore: v.video.magisteriumScore,
              daysAgo: daysAgoFor(v.video.date),
              candidatePool: pool.length,
            ))
        .toList();
  }

  /// "Najnovije epizode" rail — cross-channel sortirano po datumu desc.
  static List<FeedVideo> latestEpisodes(List<FeedVideo> all,
      {int limit = 20, FeedVideo? excludeFeatured}) {
    // Samo spremne epizode (s člankom) — neobrađene iz permisivnog channel
    // indexa se ne prikazuju u "Najnovije epizode".
    final filtered = all
        .where(isReadyForHome)
        .where((v) =>
            excludeFeatured == null || v.video.id != excludeFeatured.video.id)
        .toList();
    final sorted = List<FeedVideo>.from(filtered)
      ..sort((a, b) => (b.video.date ?? '').compareTo(a.video.date ?? ''));
    return sorted.take(limit).toList();
  }

  /// "Upravo stiglo" rail — tek pristigle epizode (info + thumbnail, bez
  /// članka) sortirano po datumu desc. Kronološki su među najnovijima, ali ih
  /// "Najnovije epizode" sakriva jer nemaju članak. Ovdje ih surfamo gledljive
  /// uz "U obradi" oznaku.
  ///
  /// Gate na svježinu ([maxAgeDays]) sprječava da stari, nikad-obrađeni stubovi
  /// iz permisivnog channel indexa zatrpaju rail — prikazuju se samo epizode
  /// koje su doista nedavno pristigle. Zahtijeva i datum i thumbnail signal
  /// (svaka epizoda u listingu ima thumbnail URL, pa je dovoljan datum).
  static List<FeedVideo> freshlyArrived(List<FeedVideo> all,
      {int limit = 12, int maxAgeDays = 30, FeedVideo? excludeFeatured}) {
    final now = DateTime.now();
    bool recent(String? date) {
      if (date == null) return false;
      try {
        final d = now.difference(DateTime.parse(date)).inDays;
        return d <= maxAgeDays;
      } catch (_) {
        return false;
      }
    }

    final filtered = all
        .where(isFreshUnprocessed)
        .where((v) => recent(v.video.date))
        .where((v) =>
            excludeFeatured == null || v.video.id != excludeFeatured.video.id)
        .toList();
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
