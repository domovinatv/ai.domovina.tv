import 'package:flutter/material.dart';
import '../services/data_service.dart';
import '../widgets/hero_section.dart';
import '../widgets/summary_section.dart';
import '../widgets/chapters_section.dart';
import '../widgets/article_section.dart';
import '../widgets/entities_section.dart';

class EpisodeScreen extends StatefulWidget {
  /// YouTube video ID — odredjuje koji se skup JSON asseta ucitava
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

class _EpisodeContent extends StatelessWidget {
  final EpisodeData data;

  const _EpisodeContent({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CustomScrollView(
      slivers: [
        // AppBar koji nestaje pri scrollu
        SliverAppBar(
          floating: true,
          snap: true,
          title: Text(
            data.info.channel,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Hero: thumbnail + naslov + statistike
              HeroSection(
                info: data.info,
                summary: data.summary,
                youtubeId: data.youtubeId,
              ),

              Divider(height: 1, color: theme.colorScheme.outlineVariant),

              // Sažetak, teme, govornici, zaključci
              SummarySection(summary: data.summary),

              Divider(height: 1, color: theme.colorScheme.outlineVariant),

              // Poglavlja po iteracijama
              const SizedBox(height: 12),
              ChaptersSection(outline: data.outline),

              Divider(height: 1, color: theme.colorScheme.outlineVariant),

              // Novinarskli clanak po tabovima
              const SizedBox(height: 12),
              ArticleSection(article: data.article),

              Divider(height: 1, color: theme.colorScheme.outlineVariant),

              // Entiteti: osobe, mjesta, organizacije
              const SizedBox(height: 12),
              EntitiesSection(summary: data.summary.summary),

              // Metadata footer
              _MetadataFooter(data: data),
            ],
          ),
        ),
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
