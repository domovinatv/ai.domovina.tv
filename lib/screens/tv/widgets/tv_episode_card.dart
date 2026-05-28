import 'package:flutter/material.dart';

import '../../../services/cdn_config.dart';
import '../../../widgets/cached_thumbnail.dart';
import 'tv_focus.dart';

/// Episode kartica za TV rail-ove (Najnovije, Nastavi slušati, itd.).
///
/// Thumbnail je 16:9 i uvijek dolazi s CDN-a (`CdnConfig.thumbnailUrl`) —
/// nikad direktno iz `info.thumbnail` koji moze biti ytimg.com URL (CORS
/// blok na webu, neispravna autenticirana ruta na native). Vidi memory
/// feedback_cdn_thumbnail_force.
class TvEpisodeCard extends StatelessWidget {
  final String episodeId;
  final String title;
  final String? subtitle; // npr. channel name
  final int? magisteriumScore;
  final double? progress; // 0.0–1.0 ako je "Nastavi slušati" rail
  final double width;
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback onTap;

  const TvEpisodeCard({
    super.key,
    required this.episodeId,
    required this.title,
    this.subtitle,
    this.magisteriumScore,
    this.progress,
    required this.width,
    this.focusNode,
    this.autofocus = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thumbHeight = width * 9 / 16;

    return TvFocusable(
      focusNode: focusNode,
      autofocus: autofocus,
      onActivate: onTap,
      builder: (context, focused) => SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRect(
              child: Stack(
                children: [
                  CachedThumbnail(
                    url: CdnConfig.thumbnailUrl(episodeId),
                    width: width,
                    height: thumbHeight,
                  ),
                  if (magisteriumScore != null && magisteriumScore! >= 70)
                    Positioned(
                      top: 0,
                      right: 0,
                      // "MAG 92" monogram — user feedback 2026-05-28: ⭐ emoji
                      // izgledao kao "like" brojač; MAG (Magisterium) je
                      // dignified i jasno odvojen od social-style indikatora.
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        color: theme.colorScheme.tertiary,
                        child: Text(
                          'MAG $magisteriumScore',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onTertiary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),
                  if (progress != null && progress! > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        color: theme.colorScheme.tertiary,
                        backgroundColor: Colors.black.withValues(alpha: 0.5),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // EYEBROW (channel name) — vizualna razlika od title-a:
            // UPPERCASE + letterSpacing + tertiary (croRed) + w700 + manji
            // font. User feedback 2026-05-28: title i channel name su izgledali
            // istovjetno (oba bodySmall onSurface), bilo je nemoguce na prvi
            // pogled odvojiti naziv epizode od naziva kanala. Eyebrow pattern
            // prati editorial home_screen (vidi `hero_section.dart`).
            // maxLines 2 jer cijeli "MOLITVENA ZAJEDNICA EHO" tip dugog
            // imena ne stane u 1 red na 152dp card width-u s letterSpacing-om.
            if (subtitle != null) ...[
              Text(
                subtitle!.toUpperCase(),
                maxLines: 2,
                softWrap: true,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
            ],
            // Maksimalno 5 redova titla — pokriva ~99% hrvatskih naslova na
            // TV card width-u (~152dp @ 12sp ≈ 15 chars/line, 5 redaka ≈ 75
            // chars). Korisnik 2026-05-28: title NE smije biti truncated.
            Text(
              title,
              maxLines: 5,
              softWrap: true,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.2,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
