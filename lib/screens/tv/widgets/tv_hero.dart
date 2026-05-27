import 'package:flutter/material.dart';

import '../../../screens/home/home_feed.dart';
import '../../../services/cdn_config.dart';
import 'tv_focus.dart';

/// TV hero — featured epizoda iz `HomeFeed.pickFeatured`.
///
/// Backdrop je full-bleed thumbnail s gradient overlay-em zdesna prema lijevo
/// da tekst ostaje citljiv. Eyebrow koristi `featured.reason.shortLabel`
/// (Najbolji izbor / Visoka Magisterium ocjena / AI-obradeno / Najnovije).
///
/// PLAY gumb je primary CTA i autofocus target u Faza 2 — kad korisnik otvori
/// home, fokus je vec na njemu. D-pad DOWN ide na prvi rail ispod.
class TvHero extends StatelessWidget {
  final FeaturedPick featured;
  final double height;
  final FocusNode? playFocusNode;
  final bool autofocusPlay;
  final VoidCallback onPlay;

  const TvHero({
    super.key,
    required this.featured,
    required this.height,
    this.playFocusNode,
    this.autofocusPlay = true,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = height < 280;
    final fv = featured.video;
    final video = fv.video;

    final metaParts = <String>[
      fv.channelName,
      if (featured.magisteriumScore != null) '⭐ ${featured.magisteriumScore}',
      if (video.durationDisplay != null) video.durationDisplay!,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 16, 48, 0),
      child: SizedBox(
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
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
              // Gradient lijevo (citljivost teksta) — surface fade prema desno
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      theme.colorScheme.surface.withValues(alpha: 0.92),
                      theme.colorScheme.surface.withValues(alpha: 0.55),
                      theme.colorScheme.surface.withValues(alpha: 0.0),
                    ],
                    stops: const [0, 0.5, 1],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(compact ? 28 : 48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      featured.reason.shortLabel.toUpperCase(),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.tertiary,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: compact ? 6 : 12),
                    SizedBox(
                      width: 560,
                      child: Text(
                        video.displayTitle,
                        maxLines: compact ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: (compact
                                ? theme.textTheme.titleLarge
                                : theme.textTheme.headlineMedium)
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 12),
                      Text(
                        metaParts.join('  ·  '),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    SizedBox(height: compact ? 14 : 28),
                    _PlayButton(
                      focusNode: playFocusNode,
                      autofocus: autofocusPlay,
                      onPressed: onPlay,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.play_arrow,
              size: 28,
              color: theme.colorScheme.onTertiary,
            ),
            const SizedBox(width: 10),
            Text(
              'POKRENI',
              style: theme.textTheme.titleLarge?.copyWith(
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
