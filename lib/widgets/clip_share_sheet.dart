import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../models/podcast_article.dart';
import '../services/clip_service.dart';
import '../services/episode_language.dart';
import '../services/open_url.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// Trailing action on an [ArticleIterationHeader]: opens a sheet to download or
/// copy a link to this chapter as a standalone MP4 clip (cutter.domovina.ai).
/// Only rendered when the episode has a video source (see the header's gate).
class ClipShareButton extends StatelessWidget {
  final String videoId;
  final ArticleIteration iteration;

  const ClipShareButton({
    super.key,
    required this.videoId,
    required this.iteration,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      icon: const Icon(Icons.ios_share, size: 18),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      tooltip: AppLocalizations.of(context).clipTooltip,
      color: theme.colorScheme.onSurfaceVariant,
      onPressed: () => showClipShareSheet(context, videoId, iteration),
    );
  }
}

/// Bottom sheet with two actions: download the chapter clip (a real MP4 file)
/// and copy a shareable link to it.
Future<void> showClipShareSheet(
  BuildContext context,
  String videoId,
  ArticleIteration iteration,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _ClipShareSheet(videoId: videoId, iteration: iteration),
  );
}

class _ClipShareSheet extends StatelessWidget {
  final String videoId;
  final ArticleIteration iteration;

  const _ClipShareSheet({required this.videoId, required this.iteration});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final lang = EpisodeLanguageScope.of(context);
    final themeText = pickLang(lang, iteration.theme, iteration.themeEn);

    final durationSec =
        ClipService.durationSeconds(iteration.startTime, iteration.endTime);
    final minutes = (durationSec / 60).round();
    final sizeMb = (ClipService.estimatedBytes(durationSec) / 1000000).round();

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header — iteration number chip + theme, matching ArticleIterationHeader.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: AppTheme.croBlue,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.fromBorderSide(
                      AppTheme.brandRim(theme.brightness),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '${iteration.iterationNumber}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.clipShareTitle.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        themeText,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: Text(l.clipDownload),
            subtitle: Text(l.clipDownloadSubtitle(sizeMb, minutes)),
            onTap: () {
              openUrl(
                ClipService.downloadUrl(videoId, iteration.iterationNumber),
              );
              Navigator.of(context).pop();
            },
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: Text(l.clipCopyLink),
            subtitle: Text(l.clipCopyLinkSubtitle),
            onTap: () {
              // Capture the messenger before popping the sheet's context away.
              final messenger = ScaffoldMessenger.of(context);
              Clipboard.setData(
                ClipboardData(
                  text: ClipService.inlineUrl(
                    videoId,
                    iteration.iterationNumber,
                  ),
                ),
              );
              Navigator.of(context).pop();
              messenger.showSnackBar(
                SnackBar(
                  content: Text(l.clipLinkCopied),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Text(
              l.clipHint,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
