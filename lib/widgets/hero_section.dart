import 'package:flutter/material.dart';
import '../models/podcast_info.dart';
import '../models/podcast_summary.dart';
import '../services/cdn_config.dart';
import '../services/episode_language.dart';

class HeroSection extends StatelessWidget {
  final PodcastInfo info;
  final String youtubeId;

  /// Ako prosljeden, preferira lokalizirani title (HR ili EN) iz pipeline-a
  /// nad YouTube `info.title`. Bez summary-a (npr. basic layout dok AI nije
  /// gotov) fallback je `info.title`.
  final SummaryContent? summary;

  const HeroSection({
    super.key,
    required this.info,
    required this.youtubeId,
    this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uploadDt = info.uploadDateTime;
    final dateStr =
        '${uploadDt.day}.${uploadDt.month}.${uploadDt.year}.';
    final lang = EpisodeLanguageScope.of(context);

    // Prefer lokalizirani naslov iz summary-a (HR ili EN), fallback YouTube original.
    String displayTitle = info.title;
    final s = summary;
    if (s != null) {
      if (lang == EpisodeLanguage.en) {
        if (s.titleEn != null && s.titleEn!.isNotEmpty) {
          displayTitle = s.titleEn!;
        } else if (s.titleHr.isNotEmpty) {
          displayTitle = s.titleHr;
        }
      } else if (s.titleHr.isNotEmpty) {
        displayTitle = s.titleHr;
      }
    }

    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Image.network(
              CdnConfig.thumbnailUrl(youtubeId),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.image_not_supported_outlined,
                  size: 48,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Channel chip
                Chip(
                  label: Text(
                    info.channel,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onPrimary),
                  ),
                  backgroundColor: theme.colorScheme.primary,
                  side: BorderSide.none,
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 12),

                // Title
                Text(
                  displayTitle,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 16),

                // Stats row
                Wrap(
                  spacing: 20,
                  runSpacing: 8,
                  children: [
                    _Stat(icon: Icons.calendar_today_outlined, label: dateStr),
                    _Stat(
                      icon: Icons.timer_outlined,
                      label: info.durationString.isNotEmpty
                          ? info.durationString
                          : _formatDuration(info.duration),
                    ),
                    // YouTube view/like/comment counts hidden — snapshot data, not live-synced.
                    // Re-enable once we have our own internal statistics.
                    // _Stat(
                    //   icon: Icons.visibility_outlined,
                    //   label: _formatCount(info.viewCount),
                    // ),
                    // _Stat(
                    //   icon: Icons.thumb_up_outlined,
                    //   label: _formatCount(info.likeCount),
                    // ),
                    // if (info.commentCount != null)
                    //   _Stat(
                    //     icon: Icons.comment_outlined,
                    //     label: _formatCount(info.commentCount!),
                    //   ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h}h ${m}min';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  // ignore: unused_element
  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Stat({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
