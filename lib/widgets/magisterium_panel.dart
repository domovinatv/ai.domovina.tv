import 'package:flutter/material.dart';
import '../models/magisterium_data.dart';
import 'magisterium_section.dart';
import 'magisterium_article_section.dart';

/// Tabbed panel showing one or more Magisterium AI analysis variants.
/// Shows tabs only when multiple variants are available.
///
/// [fillParent]: true for column mode (fills Expanded, internal scroll),
///               false for inline mode (no internal scroll, lives in parent scroll).
class MagisteriumPanel extends StatefulWidget {
  final List<(String, MagisteriumData)> variants;
  final bool fillParent;

  /// Optional keys per screenshot_timestamp for scroll-sync (column mode only).
  final Map<String, GlobalKey>? sectionKeys;

  const MagisteriumPanel({
    super.key,
    required this.variants,
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

  @override
  void initState() {
    super.initState();
    _initTabController();
  }

  void _initTabController() {
    if (widget.variants.length > 1) {
      _tabController = TabController(
        length: widget.variants.length,
        vsync: this,
      )..addListener(() {
          if (!_tabController!.indexIsChanging) {
            setState(() => _selectedIndex = _tabController!.index);
          }
        });
    }
  }

  @override
  void didUpdateWidget(MagisteriumPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.variants.length != widget.variants.length) {
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
    if (widget.variants.isEmpty) return const SizedBox.shrink();

    final hasTabs = widget.variants.length > 1;

    if (!hasTabs) {
      final (_, data) = widget.variants.first;
      final content = _VariantContent(
        magisterium: data,
        sectionKeys: widget.sectionKeys,
      );
      if (widget.fillParent) {
        return ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 32),
          children: [content],
        );
      }
      return content;
    }

    // Tabbed mode
    final tabBar = _buildTabBar(context);

    if (widget.fillParent) {
      // Column mode: TabBar + TabBarView filling available space
      return Column(
        children: [
          tabBar,
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: widget.variants.map((v) {
                final (_, data) = v;
                return ListView(
                  padding: const EdgeInsets.only(top: 8, bottom: 32),
                  children: [
                    _VariantContent(
                      magisterium: data,
                      // sectionKeys only on active tab to avoid GlobalKey conflicts
                      sectionKeys: v == widget.variants[_selectedIndex]
                          ? widget.sectionKeys
                          : null,
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      );
    }

    // Inline mode: TabBar + selected variant content (no internal scroll)
    final (_, selectedData) = widget.variants[_selectedIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tabBar,
        _VariantContent(magisterium: selectedData),
      ],
    );
  }

  Widget _buildTabBar(BuildContext context) {
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
        tabs: widget.variants.map((v) {
          final (label, data) = v;
          final color = MagisteriumSection.scoreColor(data.overallScore);
          return Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.church, size: 14, color: color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(label, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: color.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withAlpha(80)),
                  ),
                  child: Text(
                    data.overallScore != null ? '${data.overallScore}' : '?',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
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

/// Score card + chronological article for a single variant.
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
