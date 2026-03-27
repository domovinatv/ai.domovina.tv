import 'package:flutter/material.dart';
import '../models/podcast_article.dart';
import '../services/cdn_config.dart';

class ArticleSection extends StatelessWidget {
  final PodcastArticle article;
  final String youtubeId;
  final Map<String, GlobalKey> sectionKeys;
  final void Function(String timestamp)? onPlayTap;

  const ArticleSection({
    super.key,
    required this.article,
    required this.youtubeId,
    required this.sectionKeys,
    this.onPlayTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(
            'Članak',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 12),
        ...article.iterations.map(
          (iter) => _IterationBlock(
            iteration: iter,
            youtubeId: youtubeId,
            sectionKeys: sectionKeys,
            onPlayTap: onPlayTap,
          ),
        ),
      ],
    );
  }
}

class _IterationBlock extends StatelessWidget {
  final ArticleIteration iteration;
  final String youtubeId;
  final Map<String, GlobalKey> sectionKeys;
  final void Function(String timestamp)? onPlayTap;

  const _IterationBlock({
    required this.iteration,
    required this.youtubeId,
    required this.sectionKeys,
    required this.onPlayTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Text(
                      '${iteration.iterationNumber}',
                      style: TextStyle(
                        color: theme.colorScheme.onPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    iteration.theme,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...iteration.sections.map((sec) => _SectionCard(
                key: sectionKeys[sec.screenshotTimestamp],
                section: sec,
                youtubeId: youtubeId,
                onPlayTap: onPlayTap,
              )),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final PodcastSection section;
  final String youtubeId;
  final void Function(String timestamp)? onPlayTap;

  const _SectionCard({
    super.key,
    required this.section,
    required this.youtubeId,
    this.onPlayTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp badge + play button + subtitle
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Timestamp
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withAlpha(25),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: theme.colorScheme.primary.withAlpha(80), width: 1),
                ),
                child: Text(
                  section.screenshotTimestamp,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              // Play button (samo kad je video dostupan)
              if (onPlayTap != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.play_circle_outline,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      tooltip: 'Pusti od ${section.screenshotTimestamp}',
                      onPressed: () => onPlayTap!(section.screenshotTimestamp),
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  section.subtitle,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Screenshot
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              CdnConfig.screenshotUrl(youtubeId, section.screenshotTimestamp),
              fit: BoxFit.cover,
              width: double.infinity,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),

          if (section.screenshotDescription.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text(
                section.screenshotDescription,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          const SizedBox(height: 12),

          Text(
            section.content,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.65),
          ),
          const SizedBox(height: 10),

          if (section.keywords.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: section.keywords
                  .map((k) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          k,
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer),
                        ),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }
}
