import 'package:flutter/material.dart';

import '../../../screens/home/home_feed.dart';
import '../../../services/cdn_config.dart';
import 'tv_focus.dart';

/// TV hero — split layout (slika lijevo, tekst desno), max 1200dp wide i
/// centriran. Prati editorial pattern s desktop home_screen-a (vidi
/// `lib/screens/home/hero_section.dart`) ali skaliran za couch viewing s
/// fokusiranim PLAY CTA-om.
///
/// Eyebrow koristi `featured.reason.shortLabel`. PLAY je autofocus target —
/// kad korisnik otvori home, fokus je vec na njemu. D-pad DOWN ide na prvi
/// rail ispod.
class TvHero extends StatelessWidget {
  final FeaturedPick featured;

  /// Vizualni cap visine — ogranicava sliku da hero ne pojede previse
  /// vertikale na velikim TV-ima (1080p).
  final double maxHeight;
  final FocusNode? playFocusNode;
  final bool autofocusPlay;
  final VoidCallback onPlay;

  const TvHero({
    super.key,
    required this.featured,
    required this.maxHeight,
    this.playFocusNode,
    this.autofocusPlay = true,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = maxHeight < 280;
    final fv = featured.video;
    final video = fv.video;

    // 16:9 slika; sirinu deriviramo iz maxHeight da slika nikad ne prelazi
    // dozvoljenu visinu. Cap na 540dp da i na 1080p ne bude prevelika.
    final imageWidth = (maxHeight * 16 / 9).clamp(360.0, 540.0);

    final metaParts = <String>[
      fv.channelName,
      if (featured.magisteriumScore != null) '⭐ ${featured.magisteriumScore}',
      if (video.durationDisplay != null) video.durationDisplay!,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 16, 48, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Material(
              color: theme.colorScheme.surfaceContainerLowest,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: imageWidth,
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              CdnConfig.thumbnailUrl(video.id),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color: theme.colorScheme.surfaceContainerHighest,
                              ),
                            ),
                            if (featured.magisteriumScore != null)
                              Positioned(
                                top: 14,
                                right: 14,
                                child: _MagisteriumPill(
                                  score: featured.magisteriumScore!,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 24 : 36,
                          compact ? 20 : 28,
                          compact ? 24 : 36,
                          compact ? 20 : 28,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              featured.reason.shortLabel.toUpperCase(),
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.tertiary,
                                letterSpacing: 2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: compact ? 8 : 12),
                            Text(
                              video.displayTitle,
                              maxLines: compact ? 2 : 3,
                              overflow: TextOverflow.ellipsis,
                              style: (compact
                                      ? theme.textTheme.titleLarge
                                      : theme.textTheme.headlineSmall)
                                  ?.copyWith(
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                            SizedBox(height: compact ? 10 : 14),
                            Text(
                              metaParts.join('  ·  '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            SizedBox(height: compact ? 16 : 24),
                            _PlayButton(
                              focusNode: playFocusNode,
                              autofocus: autofocusPlay,
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
        ),
      ),
    );
  }
}

class _MagisteriumPill extends StatelessWidget {
  final int score;

  const _MagisteriumPill({required this.score});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.church, size: 16, color: Colors.white),
          const SizedBox(width: 6),
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
  final VoidCallback onPressed;

  const _PlayButton({
    this.focusNode,
    required this.autofocus,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TvFocusable(
      style: TvFocusStyle.primaryButton,
      focusNode: focusNode,
      autofocus: autofocus,
      onActivate: onPressed,
      borderRadius: BorderRadius.circular(14),
      builder: (context, focused) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.play_arrow,
              size: 26,
              color: theme.colorScheme.onTertiary,
            ),
            const SizedBox(width: 10),
            Text(
              'POKRENI',
              style: theme.textTheme.titleMedium?.copyWith(
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
