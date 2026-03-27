import 'package:flutter/material.dart';
import '../models/podcast_article.dart';

class ArticleSection extends StatefulWidget {
  final PodcastArticle article;

  const ArticleSection({super.key, required this.article});

  @override
  State<ArticleSection> createState() => _ArticleSectionState();
}

class _ArticleSectionState extends State<ArticleSection>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: widget.article.iterations.length,
      vsync: this,
    );
  }

  @override
  void dispose() {
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
        SizedBox(
          height: 2000,
          child: TabBarView(
            controller: _tabController,
            children: iterations
                .map((iter) => _IterationArticle(iteration: iter))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _IterationArticle extends StatelessWidget {
  final ArticleIteration iteration;

  const _IterationArticle({required this.iteration});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
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
        ...iteration.sections.map((sec) => _SectionCard(section: sec)),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final PodcastSection section;

  const _SectionCard({required this.section});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
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
          const SizedBox(height: 10),

          // Content
          Text(section.content,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.65)),
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
                              color:
                                  theme.colorScheme.onSecondaryContainer),
                        ),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }
}
