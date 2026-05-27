import 'package:flutter/material.dart';

import '../../../services/cdn_config.dart';
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
                  Image.network(
                    CdnConfig.thumbnailUrl(episodeId),
                    width: width,
                    height: thumbHeight,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: width,
                      height: thumbHeight,
                      color: theme.colorScheme.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: theme.colorScheme.onSurfaceVariant,
                        size: 32,
                      ),
                    ),
                  ),
                  if (magisteriumScore != null && magisteriumScore! >= 70)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        color: theme.colorScheme.tertiary,
                        child: Text(
                          '⭐ $magisteriumScore',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onTertiary,
                            fontWeight: FontWeight.w700,
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
            const SizedBox(height: 6),
            // Maksimalno 3 reda titla — kratki naslovi ostaju 1-2 reda; dugi
            // se ne odsijecaju. Bez `overflow: ellipsis` jer korisnik zeli
            // vidjeti cijeli naslov, makar to znacilo da neke kartice budu
            // visocije (rail height je dimenzioniran za 3-line worst case).
            Text(
              title,
              maxLines: 3,
              softWrap: true,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                maxLines: 1,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
