import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/podcast_article.dart';
import '../models/magisterium_data.dart';
import '../services/cdn_config.dart';
import 'magisterium_section.dart';
import 'citation_helpers.dart';
import '../services/open_url.dart';

class ArticleSection extends StatelessWidget {
  final PodcastArticle article;
  final String youtubeId;
  final Map<String, GlobalKey> sectionKeys;
  final void Function(String timestamp)? onPlayTap;
  final MagisteriumData? magisterium;

  const ArticleSection({
    super.key,
    required this.article,
    required this.youtubeId,
    required this.sectionKeys,
    this.onPlayTap,
    this.magisterium,
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
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...article.iterations.map(
          (iter) => _IterationBlock(
            iteration: iter,
            youtubeId: youtubeId,
            sectionKeys: sectionKeys,
            onPlayTap: onPlayTap,
            magisterium: magisterium,
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
  final MagisteriumData? magisterium;

  const _IterationBlock({
    required this.iteration,
    required this.youtubeId,
    required this.sectionKeys,
    required this.onPlayTap,
    this.magisterium,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
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
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...iteration.sections.map(
            (sec) => _SectionCard(
              key: sectionKeys[sec.screenshotTimestamp],
              section: sec,
              youtubeId: youtubeId,
              onPlayTap: onPlayTap,
              sectionMagisterium: magisterium?.forTimestamp(
                sec.screenshotTimestamp,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatefulWidget {
  final PodcastSection section;
  final String youtubeId;
  final void Function(String timestamp)? onPlayTap;
  final SectionMagisterium? sectionMagisterium;

  const _SectionCard({
    super.key,
    required this.section,
    required this.youtubeId,
    this.onPlayTap,
    this.sectionMagisterium,
  });

  @override
  State<_SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<_SectionCard> {
  bool _citationsExpanded = false;

  int _tsToSeconds(String ts) {
    final parts = ts.split(':').map(int.parse).toList();
    if (parts.length == 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
    return 0;
  }

  void _copyShareLink(BuildContext context) {
    final seconds = _tsToSeconds(widget.section.screenshotTimestamp);
    // Path-based URL → distinct crawler cache entry po timestampu.
    // Vidi web/_worker.js — chapter-aware OG injection na ovaj path.
    final url = 'https://domovina.ai/v/${widget.youtubeId}/t/$seconds';
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Link kopiran: ${widget.section.screenshotTimestamp}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final section = widget.section;
    final mag = widget.sectionMagisterium;

    return Padding(
      padding: const EdgeInsets.only(bottom: 56, top: 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp badge + play button + score badge + subtitle
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withAlpha(25),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: theme.colorScheme.primary.withAlpha(80),
                    width: 1,
                  ),
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
              if (widget.onPlayTap != null)
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
                      onPressed: () =>
                          widget.onPlayTap!(section.screenshotTimestamp),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.link,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    tooltip: 'Kopiraj link',
                    onPressed: () => _copyShareLink(context),
                  ),
                ),
              ),
              if (mag?.score != null) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: MagisteriumSection.scoreColor(
                      mag!.score,
                    ).withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: MagisteriumSection.scoreColor(
                        mag.score,
                      ).withAlpha(80),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.church,
                        size: 12,
                        color: MagisteriumSection.scoreColor(mag.score),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${mag.score}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: MagisteriumSection.scoreColor(mag.score),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  section.subtitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Screenshot
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              CdnConfig.screenshotUrl(
                widget.youtubeId,
                section.screenshotTimestamp,
              ),
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

          // Article content — markdown
          MarkdownBody(
            data: section.content,
            styleSheet: MarkdownStyleSheet.fromTheme(
              theme,
            ).copyWith(p: theme.textTheme.bodyMedium?.copyWith(height: 1.65)),
            onTapLink: (text, href, title) {
              if (href != null) openUrl(href);
            },
          ),
          const SizedBox(height: 10),

          if (section.keywords.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: section.keywords
                  .map(
                    (k) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        k,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),

          // Magisterium enrichment block
          if (mag != null && mag.assessment.isNotEmpty)
            _MagisteriumEnrichment(
              mag: mag,
              citationsExpanded: _citationsExpanded,
              onToggleCitations: () =>
                  setState(() => _citationsExpanded = !_citationsExpanded),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Magisterium enrichment block shown under each article section
// ---------------------------------------------------------------------------

class _MagisteriumEnrichment extends StatelessWidget {
  final SectionMagisterium mag;
  final bool citationsExpanded;
  final VoidCallback onToggleCitations;

  const _MagisteriumEnrichment({
    required this.mag,
    required this.citationsExpanded,
    required this.onToggleCitations,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = MagisteriumSection.scoreColor(mag.score);
    final mdStyle = MarkdownStyleSheet.fromTheme(
      theme,
    ).copyWith(p: theme.textTheme.bodySmall?.copyWith(height: 1.5));

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.church, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                'Teoloska procjena',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Assessment — markdown
          MarkdownBody(data: mag.assessment, styleSheet: mdStyle),

          // Enrichment — markdown
          if (mag.enrichment.isNotEmpty) ...[
            const SizedBox(height: 8),
            MarkdownBody(
              data: mag.enrichment,
              styleSheet: mdStyle.copyWith(
                p: theme.textTheme.bodySmall?.copyWith(
                  height: 1.5,
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],

          // Concerns
          if (mag.concerns.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...mag.concerns.map(
              (c) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber,
                      size: 14,
                      color: Color(0xFFEF6C00),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        c,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFEF6C00),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Citations (expandable, tappable)
          if (mag.citations.isNotEmpty) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: onToggleCitations,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      citationsExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${mag.citations.length} izvor${mag.citations.length == 1 ? '' : 'a'}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (citationsExpanded)
              ...mag.citations.map((cit) => _CitationCard(citation: cit)),
          ],
        ],
      ),
    );
  }
}

class _CitationCard extends StatelessWidget {
  final MagisteriumCitation citation;

  const _CitationCard({required this.citation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cleanText = cleanCitedText(citation.citedText);
    final displayText = cleanText.length > 300
        ? '${cleanText.substring(0, 300)}...'
        : cleanText;

    final ref = [
      citation.documentTitle,
      if (citation.documentReference.isNotEmpty) citation.documentReference,
      if (citation.documentYear.isNotEmpty) citation.documentYear,
    ].join(' — ');

    return GestureDetector(
      onTap: () => showCitationSheet(context, citation),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
          borderRadius: BorderRadius.circular(6),
          border: Border(
            left: BorderSide(
              color: theme.colorScheme.primary.withAlpha(100),
              width: 3,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              displayText,
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.5,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    ref,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  Icons.open_in_new,
                  size: 12,
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
