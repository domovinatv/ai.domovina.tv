import 'package:flutter/material.dart';

import '../models/magisterium_data.dart';
import '../models/podcast_article.dart';
import '../services/clip_service.dart';
import '../l10n/app_localizations.dart';
import 'article_section.dart';
import 'magisterium_article_section.dart';
import 'magisterium_section.dart';

/// Visina sticky headera naslova stupaca. Dijeljeno s episode_screen-om koji ga
/// koristi za izracun scroll inseta (da fixed header ne prekrije naslov sekcije).
const double kParallelStickyHeaderHeight = 60;

/// Flex omjer stupaca: clanak ~57.5%, Magisterium ~42.5% (±15% od 50/50).
/// Clanak ima screenshotove + duzi tekst pa profitira od sire kolone; uzi
/// Magisterium stupac se bolje renderira. Header i sekcije MORAJU dijeliti isti
/// omjer da naslovi ostanu poravnati nad stupcima.
const int kArticleColumnFlex = 23;
const int kMagColumnFlex = 17;

/// Desktop paralelni prikaz: svaka sekcija clanka i njena Magisterium
/// per-sekcija analiza stoje jedna uz drugu u istom redu. Posto cijeli view
/// zivi unutar jednog (parent) CustomScrollView-a, oba stupca dijele isti
/// scroll → timestampovi su uvijek horizontalno poravnati, bez drifta.
///
/// Vodi se strukturom clanka (article.iterations/sections); za svaku sekciju
/// Magisterium analiza se pronalazi preko [MagisteriumData.forTimestamp].
class ParallelArticleView extends StatelessWidget {
  final PodcastArticle article;
  final MagisteriumData magisterium;
  final String youtubeId;

  /// Per-timestamp GlobalKey-evi vezani na CIJELI red (clanak + Magisterium),
  /// pa `Scrollable.ensureVisible` dovuce oba stupca skupa. Iste keyeve parent
  /// koristi za detekciju aktivne sekcije pri scrollu.
  final Map<String, GlobalKey> sectionKeys;

  final void Function(String timestamp)? onPlayTap;
  final double columnGap;

  /// Kad false (audio-only epizode), sekcije ne renderiraju screenshot blok.
  final bool showScreenshot;

  /// Person-highlight marker (dolazak s /p/ profila preko `?p=<slug>`):
  /// sekcija s ovim timestampom dobiva crvenu pill oznaku, a sva pojavljivanja
  /// imena u tekstu SVIH sekcija dobiju inline needle highlight.
  final String? highlightTimestamp;

  /// Ime osobe — needle za inline highlight + tekst pill oznake.
  final String? highlightPersonName;

  /// True → pill "X govori ovdje"; false → "Ovdje se spominje: X".
  final bool highlightSpeaks;

  const ParallelArticleView({
    super.key,
    required this.article,
    required this.magisterium,
    required this.youtubeId,
    required this.sectionKeys,
    this.onPlayTap,
    this.columnGap = 32,
    this.showScreenshot = true,
    this.highlightTimestamp,
    this.highlightPersonName,
    this.highlightSpeaks = true,
  });

  @override
  Widget build(BuildContext context) {
    // Naslovi stupaca ("Članak" / "Magisterium AI") renderira sticky
    // SliverPersistentHeader u parentu (ParallelColumnsHeader), ne ovdje.
    final children = <Widget>[];

    var firstSection = true;
    for (final iter in article.iterations) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: ArticleIterationHeader(iteration: iter),
        ),
      );
      for (var i = 0; i < iter.sections.length; i++) {
        final sec = iter.sections[i];
        final mag = magisterium.forTimestamp(sec.screenshotTimestamp);
        // Clip window: start = ova sekcija, end = iduća (ili kraj iteracije).
        final endSec = i + 1 < iter.sections.length
            ? ClipService.hmsToSeconds(iter.sections[i + 1].screenshotTimestamp)
            : ClipService.hmsToSeconds(iter.endTime);
        children.add(
          Padding(
            padding: EdgeInsets.fromLTRB(20, firstSection ? 20 : 44, 20, 0),
            child: KeyedSubtree(
              key: sectionKeys[sec.screenshotTimestamp],
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: kArticleColumnFlex,
                    child: ArticleSectionCard(
                      section: sec,
                      youtubeId: youtubeId,
                      onPlayTap: onPlayTap,
                      showInlineMagisterium: false,
                      padding: EdgeInsets.zero,
                      showScreenshot: showScreenshot,
                      clipEndSec: showScreenshot ? endSec : null,
                      personHighlight:
                          sec.screenshotTimestamp == highlightTimestamp
                              ? highlightPersonName
                              : null,
                      personHighlightSpeaks: highlightSpeaks,
                      personNeedle: highlightPersonName,
                    ),
                  ),
                  SizedBox(width: columnGap),
                  Expanded(
                    flex: kMagColumnFlex,
                    child: (mag != null && mag.assessment.isNotEmpty)
                        ? MagisteriumSectionAnalysis(
                            timestamp: sec.screenshotTimestamp,
                            subtitle: sec.subtitle,
                            subtitleEn: sec.subtitleEn,
                            mag: mag,
                            showDivider: false,
                            padding: EdgeInsets.zero,
                          )
                        : const _NoAnalysisSlot(),
                  ),
                ],
              ),
            ),
          ),
        );
        firstSection = false;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// Red naslova stupaca: "Članak" lijevo, "Magisterium AI" + score desno.
/// Mora koristiti isti [columnGap] kao [ParallelArticleView] da se naslovi
/// poklope sa stupcima ispod. Koristi se kao sticky header iznad paralelne zone.
class ParallelColumnsHeader extends StatelessWidget {
  final int? overallScore;
  final double columnGap;

  const ParallelColumnsHeader({
    super.key,
    required this.overallScore,
    this.columnGap = 32,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    // start poravnanje: "Članak" sjeda na istu liniju kao "Magisterium AI"
    // naslov (desni blok je dvoredni). Cijeli red delegat vertikalno centrira
    // u baru.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: kArticleColumnFlex,
          child: Text(
            l.sectionArticle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(width: columnGap),
        Expanded(
          flex: kMagColumnFlex,
          child: _MagisteriumColumnHeader(overallScore: overallScore),
        ),
      ],
    );
  }
}

/// SliverPersistentHeader delegate koji pinna [ParallelColumnsHeader] na vrh dok
/// je paralelna zona vidljiva. Unutar [SliverMainAxisGroup] otpinna se kad zona
/// odscrolla. Sadrzaj je centriran i constrainan na istu sirinu (maxContentWidth)
/// kao paralelni stupci, pa se naslovi poklope.
class ParallelColumnsStickyDelegate extends SliverPersistentHeaderDelegate {
  final int? overallScore;
  final double columnGap;
  final double maxContentWidth;
  final double height;

  const ParallelColumnsStickyDelegate({
    required this.overallScore,
    this.columnGap = 32,
    this.maxContentWidth = 1500,
    this.height = kParallelStickyHeaderHeight,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = Theme.of(context);
    // DecoratedBox + Center: Center vertikalno (i horizontalno) centrira
    // shrink-wrapani header u fiksnoj visini bara. (Stari Container.alignment +
    // Column/Expanded je davao loose constraintove → Expanded kolaps → tekst
    // zalijepljen na vrh.) Divider je bottom border.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ParallelColumnsHeader(
              overallScore: overallScore,
              columnGap: columnGap,
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(ParallelColumnsStickyDelegate oldDelegate) {
    return oldDelegate.overallScore != overallScore ||
        oldDelegate.columnGap != columnGap ||
        oldDelegate.maxContentWidth != maxContentWidth ||
        oldDelegate.height != height;
  }
}

/// Header desnog stupca — naziv + ukupni Magisterium score.
class _MagisteriumColumnHeader extends StatelessWidget {
  /// Ukupni score. Prosljeduje se eksplicitno (a ne cita iz MagisteriumData)
  /// jer EN overlay varijanta cesto nema `overall_score` — caller fallbacka na
  /// HR score (score je jezicno-neovisan).
  final int? overallScore;

  const _MagisteriumColumnHeader({required this.overallScore});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final score = overallScore;
    final color = MagisteriumSection.scoreColor(score);

    // Ikona crkve inline s "Magisterium AI" naslovom (gornji red); podnaslov
    // uvucen ispod (poravnat s naslovom, ne s ikonom). Bez ovog ikona "lebdi"
    // na vertikalnom centru bloka — izmedu naslova i podnaslova.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.church, size: 20, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Magisterium AI',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (score != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withAlpha(80)),
                ),
                child: Text(
                  '$score/100',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 28, top: 1),
          child: Text(
            l.sectionTheologicalAnalysisSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Placeholder kad sekcija nema teolosku analizu — drzi red poravnatim.
class _NoAnalysisSlot extends StatelessWidget {
  const _NoAnalysisSlot();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      AppLocalizations.of(context).sectionNoTheologicalAnalysis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}
