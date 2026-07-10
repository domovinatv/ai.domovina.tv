import 'package:flutter/material.dart';
import '../models/podcast_outline.dart';
import '../services/clip_service.dart';
import '../l10n/app_localizations.dart';
import 'clip_share_sheet.dart';

class ChaptersSection extends StatelessWidget {
  final PodcastOutline outline;

  /// When non-null, each chapter row gets a download/share clip action. Null for
  /// audio-only episodes (the cutter needs `video_h264.mp4`).
  final String? videoId;

  const ChaptersSection({super.key, required this.outline, this.videoId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.sectionChapters,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...outline.iterations.asMap().entries.map((e) {
            final iter = e.value;
            return _IterationBlock(
              iteration: iter,
              isLast: e.key == outline.iterations.length - 1,
              videoId: videoId,
            );
          }),
        ],
      ),
    );
  }
}

class _IterationBlock extends StatefulWidget {
  final OutlineIteration iteration;
  final bool isLast;
  final String? videoId;

  const _IterationBlock({
    required this.iteration,
    required this.isLast,
    this.videoId,
  });

  @override
  State<_IterationBlock> createState() => _IterationBlockState();
}

class _IterationBlockState extends State<_IterationBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iter = widget.iteration;

    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      '${iter.iterationNumber}',
                      style: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        iter.theme,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${iter.startTime} – ${iter.endTime}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 44, bottom: 8),
            child: Column(
              children: iter.chapters.asMap().entries.map((entry) {
                final j = entry.key;
                final ch = entry.value;
                // Clip window: this chapter's start → the next chapter's start,
                // or the iteration end for the last chapter in the block.
                final startSec = ch.totalSeconds;
                final endSec = j + 1 < iter.chapters.length
                    ? iter.chapters[j + 1].totalSeconds
                    : ClipService.hmsToSeconds(iter.endTime);
                final canClip = widget.videoId != null && endSec > startSec;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          ch.timestamp,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(ch.topic, style: theme.textTheme.bodySmall),
                      ),
                      if (canClip)
                        ClipShareButton(
                          videoId: widget.videoId!,
                          startSec: startSec,
                          endSec: endSec,
                          title: ch.topic,
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        if (!widget.isLast)
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
      ],
    );
  }
}
