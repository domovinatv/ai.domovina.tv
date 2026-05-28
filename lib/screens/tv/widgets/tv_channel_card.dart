import 'package:flutter/material.dart';

import '../../../models/channel_index.dart';
import '../../../widgets/cached_thumbnail.dart';
import 'tv_focus.dart';

/// Channel kartica za TV "Kanali" rail. Uvijek koristi kvadratni avatar
/// (`channel.avatarSquare`) — banner cover (`avatarCover`) varira po
/// dimenzijama (vidi memory feedback_channel_cover_dichotomy), pa za
/// uniformno-shaped TV rail kvadrat je jedini siguran izbor.
class TvChannelCard extends StatelessWidget {
  final ChannelSummary channel;
  final double size;
  final VoidCallback onTap;

  const TvChannelCard({
    super.key,
    required this.channel,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatar = channel.avatarSquare;

    return TvFocusable(
      onActivate: onTap,
      builder: (context, focused) => SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRect(
              child: SizedBox(
                width: size,
                height: size,
                child: avatar != null
                    ? CachedThumbnail(
                        url: avatar,
                        errorIcon: Icons.podcasts_outlined,
                      )
                    : Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.podcasts_outlined,
                          color: theme.colorScheme.onSurfaceVariant,
                          size: 32,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            // Do 3 reda imena kanala — bez ellipsis-a. Kratka imena ostaju
            // jednoredna; duga (npr. "Centar za duhovna zvanja Splitsko-
            // makarske nadbiskupije") se prelijevaju bez odsijecanja.
            // Bumped na 3 reda 2026-05-28 — channel names na narrow TV card
            // s 2 reda i dalje su clip-ali zadnju rijec.
            Text(
              channel.name,
              maxLines: 3,
              softWrap: true,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            // `height: 1.2` override — Material3 labelSmall default 1.45
            // sirio bi liniju na ~16dp; TvMetrics rail kalkulira 13.2.
            Text(
              '${channel.videoCount} epizoda',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
