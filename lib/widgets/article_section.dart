import 'package:flutter/material.dart';
import '../models/podcast_article.dart';

class ArticleSection extends StatefulWidget {
  final PodcastArticle article;
  final String youtubeId;

  const ArticleSection({
    super.key,
    required this.article,
    required this.youtubeId,
  });

  @override
  State<ArticleSection> createState() => _ArticleSectionState();
}

class _ArticleSectionState extends State<ArticleSection>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: widget.article.iterations.length,
      vsync: this,
    );
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.index != _currentIndex) {
      setState(() => _currentIndex = _tabController.index);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iterations = widget.article.iterations;

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
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: iterations
              .map((i) => Tab(text: 'Dio ${i.iterationNumber}'))
              .toList(),
        ),
        // Prikazuje samo aktivnu iteraciju — bez fiksne visine,
        // outer CustomScrollView preuzima vertikalni scroll.
        _IterationArticle(
          iteration: iterations[_currentIndex],
          youtubeId: widget.youtubeId,
        ),
      ],
    );
  }
}

class _IterationArticle extends StatelessWidget {
  final ArticleIteration iteration;
  final String youtubeId;

  const _IterationArticle({
    required this.iteration,
    required this.youtubeId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            iteration.theme,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 16),
        ...iteration.sections.map(
          (sec) => _SectionCard(section: sec, youtubeId: youtubeId),
        ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final PodcastSection section;
  final String youtubeId;

  const _SectionCard({required this.section, required this.youtubeId});

  /// Konvertira "HH:MM:SS" → "HH-MM-SS" za asset path
  String get _screenshotAssetPath {
    final ts = section.screenshotTimestamp.replaceAll(':', '-');
    return 'assets/images/$youtubeId/screenshots/$ts.png';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp badge + subtitle
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withAlpha(25),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: theme.colorScheme.primary.withAlpha(80),
                      width: 1),
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
              const SizedBox(width: 10),
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
            child: Image.asset(
              _screenshotAssetPath,
              fit: BoxFit.cover,
              width: double.infinity,
              errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
            ),
          ),

          // Screenshot caption
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

          // Content
          Text(
            section.content,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.65),
          ),
          const SizedBox(height: 10),

          // Keywords
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
