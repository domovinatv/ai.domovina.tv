import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../screens/home/home_feed.dart';
import '../../../services/cdn_config.dart';
import '../../../widgets/cached_thumbnail.dart';
import 'tv_focus.dart';
import 'tv_metrics.dart';

/// TV hero — split layout (slika lijevo, tekst desno), max `metrics.heroMaxWidth`
/// i centriran. Prati editorial pattern s desktop home_screen-a (vidi
/// `lib/screens/home/hero_section.dart`) ali skaliran za couch viewing s
/// fokusiranim PLAY CTA-om.
///
/// Eyebrow koristi `featured.reason.shortLabel`. PLAY je autofocus target —
/// kad korisnik otvori home, fokus je vec na njemu, ali ensureVisible
/// preskoceno (vidi `tv_focus.dart`) da autofocus ne scrolla appbar van
/// ekrana.
class TvHero extends StatelessWidget {
  final FeaturedPick featured;
  final TvMetrics metrics;
  final FocusNode? playFocusNode;
  final bool autofocusPlay;
  final VoidCallback onPlay;

  const TvHero({
    super.key,
    required this.featured,
    required this.metrics,
    this.playFocusNode,
    this.autofocusPlay = true,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = metrics.heroMaxHeight;
    final compact = maxHeight < 260;
    final fv = featured.video;
    final video = fv.video;

    // 16:9 slika; sirinu deriviramo iz maxHeight da slika ne prelazi
    // dozvoljenu visinu. Slika zadrzava fiksni aspect (imageWidth×imageHeight)
    // i NIKAD se ne rasteze — ako tekst panel zatreba vise visine, cijeli hero
    // naraste a slika se vertikalno centrira (crossAxisAlignment.center).
    // Tako izbjegavamo overflow na malim TV-ima (EON 960×540 = hero 180dp gdje
    // tekst ~183dp ne stane) bez stretchanja slike (EON feedback 2026-05-28).
    final imageWidth = (maxHeight * 16 / 9).clamp(320.0, 480.0);
    final imageHeight = imageWidth * 9 / 16;

    final metaParts = <String>[
      fv.channelName,
      if (featured.magisteriumScore != null) 'MAG ${featured.magisteriumScore}',
      if (video.durationDisplay != null) video.durationDisplay!,
    ];

    final scale = metrics.scale;
    final titleStyle = (compact
            ? theme.textTheme.titleLarge
            : theme.textTheme.headlineSmall)
        ?.copyWith(
      fontWeight: FontWeight.w700,
      height: 1.2,
      fontSize: ((compact
                  ? theme.textTheme.titleLarge?.fontSize
                  : theme.textTheme.headlineSmall?.fontSize) ??
              22) *
          scale,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(metrics.pagePadH, 8, metrics.pagePadH, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: metrics.heroMaxWidth),
          // Hero visina = max(imageHeight, tekst panel) — slika fiksna 16:9,
          // tekst diktira rast. Bez ClipRRect (ukloneno 2026-05-28: rounded
          // corners su lose izgledali za thumbnails koji imaju margin-e/
          // letterbox — radije ostavimo siroke rubove i pustimo da svaka slika
          // dise prirodno).
          child: Material(
            color: theme.colorScheme.surfaceContainerLowest,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: imageWidth,
                  height: imageHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedThumbnail(
                        url: CdnConfig.thumbnailUrl(video.id),
                        width: imageWidth,
                        height: imageHeight,
                      ),
                      if (featured.magisteriumScore != null)
                        Positioned(
                          top: 12 * scale,
                          right: 12 * scale,
                          child: _MagisteriumPill(
                            score: featured.magisteriumScore!,
                            scale: scale,
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      (compact ? 20 : 28) * scale,
                      (compact ? 16 : 22) * scale,
                      (compact ? 20 : 28) * scale,
                      (compact ? 16 : 22) * scale,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          featured.reason
                              .shortLabel(AppLocalizations.of(context))
                              .toUpperCase(),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.tertiary,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: (compact ? 4 : 8) * scale),
                        Text(
                          video.displayTitle,
                          maxLines: compact ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                        SizedBox(height: (compact ? 6 : 10) * scale),
                        Text(
                          metaParts.join('  ·  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        SizedBox(height: (compact ? 10 : 16) * scale),
                        _PlayButton(
                          focusNode: playFocusNode,
                          autofocus: autofocusPlay,
                          scale: scale,
                          onPressed: onPlay,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MagisteriumPill extends StatelessWidget {
  final int score;
  final double scale;

  const _MagisteriumPill({required this.score, required this.scale});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 10 * scale,
        vertical: 5 * scale,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.church, size: 14 * scale, color: Colors.white),
          SizedBox(width: 5 * scale),
          Text(
            '$score',
            style: theme.textTheme.labelLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final FocusNode? focusNode;
  final bool autofocus;
  final double scale;
  final VoidCallback onPressed;

  const _PlayButton({
    this.focusNode,
    required this.autofocus,
    required this.scale,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return TvFocusable(
      style: TvFocusStyle.primaryButton,
      focusNode: focusNode,
      autofocus: autofocus,
      onActivate: onPressed,
      borderRadius: BorderRadius.circular(14),
      builder: (context, focused) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: 18 * scale,
          vertical: 8 * scale,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.play_arrow,
              size: 22 * scale,
              color: theme.colorScheme.onTertiary,
            ),
            SizedBox(width: 8 * scale),
            Text(
              l.tvPlay.toUpperCase(),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onTertiary,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
