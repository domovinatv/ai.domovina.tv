import 'package:flutter/material.dart';

import '../../../models/channel_index.dart';
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
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: size,
                height: size,
                child: avatar != null
                    ? Image.network(
                        avatar,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.podcasts_outlined,
                            color: theme.colorScheme.onSurfaceVariant,
                            size: 32,
                          ),
                        ),
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
            const SizedBox(height: 10),
            Text(
              channel.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${channel.videoCount} epizoda',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
