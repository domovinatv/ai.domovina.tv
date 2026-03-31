import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/magisterium_data.dart';
import '../models/magisterium_full_data.dart';
import 'magisterium_section.dart';
import 'magisterium_article_section.dart';

/// Generic tab entry for MagisteriumPanel — supports different content types.
class _TabEntry {
  final String label;
  final IconData icon;
  final Color? badgeColor;
  final String? badgeText;
  final Widget Function(bool fillParent, Map<String, GlobalKey>? sectionKeys,
      int selectedIndex, int myIndex) builder;

  const _TabEntry({
    required this.label,
    required this.icon,
    this.badgeColor,
    this.badgeText,
    required this.builder,
  });
}

/// Tabbed panel showing Magisterium AI analysis variants, full evaluation,
/// and prompt. Shows tabs only when multiple entries are available.
///
/// [fillParent]: true for column mode (fills Expanded, internal scroll),
///               false for inline mode (no internal scroll, lives in parent scroll).
class MagisteriumPanel extends StatefulWidget {
  final List<(String, MagisteriumData)> variants;
  final MagisteriumFullData? magisteriumFull;
  final String? magisteriumFullPrompt;
  final bool fillParent;
  final Map<String, GlobalKey>? sectionKeys;

  const MagisteriumPanel({
    super.key,
    required this.variants,
    this.magisteriumFull,
    this.magisteriumFullPrompt,
    this.fillParent = false,
    this.sectionKeys,
  });

  @override
  State<MagisteriumPanel> createState() => _MagisteriumPanelState();
}

class _MagisteriumPanelState extends State<MagisteriumPanel>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  int _selectedIndex = 0;

  List<_TabEntry> _buildTabs() {
    final tabs = <_TabEntry>[];

    // Existing per-section / per-block variants
    for (final (label, data) in widget.variants) {
      final color = MagisteriumSection.scoreColor(data.overallScore);
      tabs.add(_TabEntry(
        label: label,
        icon: Icons.church,
        badgeColor: color,
        badgeText: data.overallScore != null ? '${data.overallScore}' : '?',
        builder: (fill, keys, sel, my) => _VariantContent(
          magisterium: data,
          sectionKeys: sel == my ? keys : null,
        ),
      ));
    }

    // Magisterium Full evaluacija (Magisterium AI API output)
    if (widget.magisteriumFull != null) {
      final full = widget.magisteriumFull!;
      final color = MagisteriumSection.scoreColor(full.overallScore);
      tabs.add(_TabEntry(
        label: 'Evaluacija',
        icon: Icons.auto_awesome,
        badgeColor: color,
        badgeText: '${full.overallScore}',
        builder: (_, __, ___, ____) =>
            _MagisteriumFullContent(data: full),
      ));
    }

    // Magisterium Full prompt (raw markdown)
    if (widget.magisteriumFullPrompt != null) {
      tabs.add(_TabEntry(
        label: 'Prompt',
        icon: Icons.code,
        builder: (_, __, ___, ____) =>
            _MarkdownContent(markdown: widget.magisteriumFullPrompt!),
      ));
    }

    return tabs;
  }

  @override
  void initState() {
    super.initState();
    _initTabController();
  }

  void _initTabController() {
    final count = _buildTabs().length;
    if (count > 1) {
      _tabController = TabController(length: count, vsync: this)
        ..addListener(() {
          if (!_tabController!.indexIsChanging) {
            setState(() => _selectedIndex = _tabController!.index);
          }
        });
    }
  }

  @override
  void didUpdateWidget(MagisteriumPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldCount = oldWidget.variants.length +
        (oldWidget.magisteriumFull != null ? 1 : 0) +
        (oldWidget.magisteriumFullPrompt != null ? 1 : 0);
    final newCount = widget.variants.length +
        (widget.magisteriumFull != null ? 1 : 0) +
        (widget.magisteriumFullPrompt != null ? 1 : 0);
    if (oldCount != newCount) {
      _tabController?.dispose();
      _selectedIndex = 0;
      _initTabController();
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _buildTabs();
    if (tabs.isEmpty) return const SizedBox.shrink();

    if (tabs.length == 1) {
      final content = tabs.first
          .builder(widget.fillParent, widget.sectionKeys, 0, 0);
      if (widget.fillParent) {
        return ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 32),
          children: [content],
        );
      }
      return content;
    }

    // Tabbed mode
    final tabBar = _buildTabBar(context, tabs);

    if (widget.fillParent) {
      return Column(
        children: [
          tabBar,
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                for (int i = 0; i < tabs.length; i++)
                  ListView(
                    padding: const EdgeInsets.only(top: 8, bottom: 32),
                    children: [
                      tabs[i].builder(
                          true, widget.sectionKeys, _selectedIndex, i),
                    ],
                  ),
              ],
            ),
          ),
        ],
      );
    }

    // Inline mode
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tabBar,
        tabs[_selectedIndex]
            .builder(false, widget.sectionKeys, _selectedIndex, _selectedIndex),
      ],
    );
  }

  Widget _buildTabBar(BuildContext context, List<_TabEntry> tabs) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80),
          ),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: tabs.length > 3,
        tabs: tabs.map((t) {
          return Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(t.icon, size: 14, color: t.badgeColor),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(t.label, overflow: TextOverflow.ellipsis),
                ),
                if (t.badgeText != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: (t.badgeColor ?? theme.colorScheme.primary)
                          .withAlpha(25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: (t.badgeColor ?? theme.colorScheme.primary)
                            .withAlpha(80),
                      ),
                    ),
                    child: Text(
                      t.badgeText!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: t.badgeColor ?? theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
        labelColor: theme.colorScheme.primary,
        unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
        indicatorColor: theme.colorScheme.primary,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerHeight: 0,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab content widgets
// ---------------------------------------------------------------------------

/// Score card + chronological article for per-section/per-block variant.
class _VariantContent extends StatelessWidget {
  final MagisteriumData magisterium;
  final Map<String, GlobalKey>? sectionKeys;

  const _VariantContent({
    required this.magisterium,
    this.sectionKeys,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        MagisteriumSection(magisterium: magisterium),
        const SizedBox(height: 4),
        MagisteriumArticleSection(
          magisterium: magisterium,
          sectionKeys: sectionKeys,
        ),
      ],
    );
  }
}

/// Full Magisterium AI evaluation — renders markdown evaluation + citations.
class _MagisteriumFullContent extends StatelessWidget {
  final MagisteriumFullData data;

  const _MagisteriumFullContent({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scoreColor = MagisteriumSection.scoreColor(data.overallScore);

    // Build markdown: evaluation text + footnotes with citation details
    final buffer = StringBuffer();
    buffer.writeln(data.evaluation);

    if (data.citations.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('---');
      buffer.writeln();
      buffer.writeln('## Izvori (${data.citations.length})');
      buffer.writeln();
      for (int i = 0; i < data.citations.length; i++) {
        final c = data.citations[i];
        final author = c.documentAuthor ?? '';
        final year = c.documentYear ?? '';
        final authorYear =
            [author, year].where((s) => s.isNotEmpty).join(', ');
        buffer.writeln(
            '**[^${i + 1}]** ${c.documentTitle}${authorYear.isNotEmpty ? ' ($authorYear)' : ''}');
        buffer.writeln();
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Score header
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: scoreColor.withAlpha(15),
            border: Border.all(color: scoreColor.withAlpha(60)),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: scoreColor.withAlpha(25),
                  shape: BoxShape.circle,
                  border: Border.all(color: scoreColor.withAlpha(80), width: 2),
                ),
                child: Center(
                  child: Text(
                    '${data.overallScore}',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: scoreColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.scoreInterpretation,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scoreColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Magisterium AI  •  ${data.citations.length} citata',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Evaluation markdown
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: MarkdownBody(
            data: buffer.toString(),
            selectable: true,
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              p: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
              h1: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
              h2: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
              h3: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
              blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              blockquoteDecoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: scoreColor.withAlpha(120), width: 3),
                ),
                color: scoreColor.withAlpha(10),
              ),
              listBullet: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// Raw markdown content — used for prompt display.
class _MarkdownContent extends StatelessWidget {
  final String markdown;

  const _MarkdownContent({required this.markdown});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: MarkdownBody(
        data: markdown,
        selectable: true,
        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
          p: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          h1: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.bold),
          h2: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
          h3: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
          code: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
      ),
    );
  }
}
