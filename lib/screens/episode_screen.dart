import 'package:flutter/material.dart';
import '../services/data_service.dart';
import '../widgets/hero_section.dart';
import '../widgets/summary_section.dart';
import '../widgets/chapters_section.dart';
import '../widgets/article_section.dart';
import '../widgets/entities_section.dart';
import '../widgets/table_of_contents.dart';

class EpisodeScreen extends StatefulWidget {
  final String youtubeId;

  const EpisodeScreen({super.key, required this.youtubeId});

  @override
  State<EpisodeScreen> createState() => _EpisodeScreenState();
}

class _EpisodeScreenState extends State<EpisodeScreen> {
  late Future<EpisodeData> _future;

  @override
  void initState() {
    super.initState();
    _future = EpisodeData.load(youtubeId: widget.youtubeId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      body: FutureBuilder<EpisodeData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 12),
                    Text(
                      'Greška pri ucitavanju podataka:\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return _EpisodeContent(data: snapshot.data!);
        },
      ),
    );
  }
}

class _EpisodeContent extends StatefulWidget {
  final EpisodeData data;

  const _EpisodeContent({required this.data});

  @override
  State<_EpisodeContent> createState() => _EpisodeContentState();
}

class _EpisodeContentState extends State<_EpisodeContent> {
  final _scrollController = ScrollController();
  late final Map<String, GlobalKey> _sectionKeys;
  String? _activeTimestamp;

  @override
  void initState() {
    super.initState();
    _sectionKeys = {
      for (final iter in widget.data.article.iterations)
        for (final sec in iter.sections)
          sec.screenshotTimestamp: GlobalKey(),
    };
    _scrollController.addListener(_updateActiveSection);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateActiveSection);
    _scrollController.dispose();
    super.dispose();
  }

  /// Osvježava aktivnu sekciju na temelju scroll pozicije
  void _updateActiveSection() {
    for (final entry in _sectionKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final pos = box.localToGlobal(Offset.zero);
      // Sekcija je "aktivna" ako joj je vrh u gornjem trećini ekrana
      final screenH = MediaQuery.sizeOf(context).height;
      if (pos.dy >= 0 && pos.dy < screenH * 0.4) {
        if (_activeTimestamp != entry.key) {
          setState(() => _activeTimestamp = entry.key);
        }
        return;
      }
    }
  }

  void _scrollToSection(String timestamp) {
    final key = _sectionKeys[timestamp];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        alignment: 0.05,
      );
      setState(() => _activeTimestamp = timestamp);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final theme = Theme.of(context);
    final isWide = MediaQuery.sizeOf(context).width > 900;

    final mainContent = CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverAppBar(
          floating: true,
          snap: true,
          title: Text(
            data.info.channel,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  data.info.id,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
        SliverToBoxAdapter(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  HeroSection(
                    info: data.info,
                    summary: data.summary,
                    youtubeId: data.youtubeId,
                  ),
                  Divider(height: 1, color: theme.colorScheme.outlineVariant),
                  SummarySection(summary: data.summary),
                  Divider(height: 1, color: theme.colorScheme.outlineVariant),
                  const SizedBox(height: 12),
                  ChaptersSection(outline: data.outline),
                  Divider(height: 1, color: theme.colorScheme.outlineVariant),
                  const SizedBox(height: 12),
                  ArticleSection(
                    article: data.article,
                    youtubeId: data.youtubeId,
                    sectionKeys: _sectionKeys,
                  ),
                  Divider(height: 1, color: theme.colorScheme.outlineVariant),
                  const SizedBox(height: 12),
                  EntitiesSection(summary: data.summary.summary),
                  _MetadataFooter(data: data),
                ],
              ),
            ),
          ),
        ),
      ],
    );

    if (!isWide) return mainContent;

    // Desktop: sidebar lijevo + main content desno
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TableOfContents(
          article: data.article,
          onSectionTap: _scrollToSection,
          activeTimestamp: _activeTimestamp,
        ),
        Expanded(child: mainContent),
      ],
    );
  }
}

class _MetadataFooter extends StatelessWidget {
  final EpisodeData data;

  const _MetadataFooter({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = data.summary;

    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Metadata',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _MetaRow('YouTube ID', data.info.id),
          _MetaRow('Kanal', data.info.channel),
          _MetaRow('Model (sažetak)', summary.model),
          _MetaRow('Model (članak)', data.article.metadata.model),
          _MetaRow(
            'Generirano',
            summary.generatedAt.toIso8601String().substring(0, 10),
          ),
          _MetaRow('Jezik', summary.summary.language.toUpperCase()),
          _MetaRow('Tip sadržaja', summary.summary.contentType),
          _MetaRow('Sentiment', summary.summary.sentiment),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetaRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
