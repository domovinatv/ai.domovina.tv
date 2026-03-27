import 'package:flutter/material.dart';
import '../models/podcast_article.dart';

class TableOfContents extends StatefulWidget {
  final PodcastArticle article;
  final void Function(String timestamp) onSectionTap;
  final String? activeTimestamp;

  const TableOfContents({
    super.key,
    required this.article,
    required this.onSectionTap,
    this.activeTimestamp,
  });

  @override
  State<TableOfContents> createState() => _TableOfContentsState();
}

class _TableOfContentsState extends State<TableOfContents> {
  // Koja su poglavlja otvorena (iteracija index)
  late final Set<int> _expanded;

  @override
  void initState() {
    super.initState();
    // Sve iteracije otvorene inicijalno
    _expanded = {
      for (var i = 0; i < widget.article.iterations.length; i++) i,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 248,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            alignment: Alignment.centerLeft,
            child: Text(
              'Sadržaj',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          // Scrollable lista poglavlja
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: widget.article.iterations
                  .asMap()
                  .entries
                  .map((e) => _IterationGroup(
                        index: e.key,
                        iteration: e.value,
                        isExpanded: _expanded.contains(e.key),
                        activeTimestamp: widget.activeTimestamp,
                        onToggle: () => setState(() {
                          if (_expanded.contains(e.key)) {
                            _expanded.remove(e.key);
                          } else {
                            _expanded.add(e.key);
                          }
                        }),
                        onSectionTap: widget.onSectionTap,
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _IterationGroup extends StatelessWidget {
  final int index;
  final ArticleIteration iteration;
  final bool isExpanded;
  final String? activeTimestamp;
  final VoidCallback onToggle;
  final void Function(String) onSectionTap;

  const _IterationGroup({
    required this.index,
    required this.iteration,
    required this.isExpanded,
    required this.activeTimestamp,
    required this.onToggle,
    required this.onSectionTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Iteracija header — klikabilni
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: theme.colorScheme.onPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    iteration.theme,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),

        // Sekcije unutar iteracije
        if (isExpanded)
          ...iteration.sections.map((sec) {
            final isActive = sec.screenshotTimestamp == activeTimestamp;
            return _SectionItem(
              timestamp: sec.screenshotTimestamp,
              subtitle: sec.subtitle,
              isActive: isActive,
              onTap: () => onSectionTap(sec.screenshotTimestamp),
            );
          }),

        if (index < 1) // separator između iteracija osim zadnje
          Divider(
            height: 8,
            indent: 14,
            endIndent: 14,
            color: theme.colorScheme.outlineVariant,
          ),
      ],
    );
  }
}

class _SectionItem extends StatelessWidget {
  final String timestamp;
  final String subtitle;
  final bool isActive;
  final VoidCallback onTap;

  const _SectionItem({
    required this.timestamp,
    required this.subtitle,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: isActive
            ? BoxDecoration(
                color: theme.colorScheme.primaryContainer.withAlpha(120),
                border: Border(
                  left: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 3,
                  ),
                ),
              )
            : null,
        padding: EdgeInsets.fromLTRB(isActive ? 11 : 14, 6, 10, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                // Prikaz kao MM:SS (bez sata ako je 00)
                _formatTimestamp(timestamp),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isActive
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isActive
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(String ts) {
    // "00:04:25" → "04:25", "01:06:30" → "1:06:30"
    final parts = ts.split(':');
    if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      if (h == 0) return '${parts[1]}:${parts[2]}';
      return '$h:${parts[1]}:${parts[2]}';
    }
    return ts;
  }
}
