/// Model za .article.json — novinarski članak po sekcijama
class PodcastArticle {
  final ArticleMetadata metadata;
  final List<ArticleIteration> iterations;

  const PodcastArticle({required this.metadata, required this.iterations});

  factory PodcastArticle.fromJson(Map<String, dynamic> json) {
    return PodcastArticle(
      metadata: ArticleMetadata.fromJson(
          json['metadata'] as Map<String, dynamic>? ?? {}),
      iterations: (json['iterations'] as List<dynamic>? ?? [])
          .map((i) => ArticleIteration.fromJson(i as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ArticleMetadata {
  final String sourceFile;
  final DateTime generatedAt;
  final String model;

  const ArticleMetadata({
    required this.sourceFile,
    required this.generatedAt,
    required this.model,
  });

  factory ArticleMetadata.fromJson(Map<String, dynamic> json) {
    return ArticleMetadata(
      sourceFile: json['source_file'] as String? ?? '',
      generatedAt: DateTime.tryParse(json['generated_at'] as String? ?? '') ??
          DateTime.now(),
      model: json['model'] as String? ?? '',
    );
  }
}

class ArticleIteration {
  final int iterationNumber;
  final String startTime;
  final String endTime;
  final String theme;
  final List<PodcastSection> sections;

  const ArticleIteration({
    required this.iterationNumber,
    required this.startTime,
    required this.endTime,
    required this.theme,
    required this.sections,
  });

  factory ArticleIteration.fromJson(Map<String, dynamic> json) {
    return ArticleIteration(
      iterationNumber: json['iteration_number'] as int? ?? 0,
      startTime: json['start_time'] as String? ?? '',
      endTime: json['end_time'] as String? ?? '',
      theme: json['theme'] as String? ?? '',
      sections: (json['sections'] as List<dynamic>? ?? [])
          .map((s) => PodcastSection.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}

class PodcastSection {
  final String subtitle;
  final String screenshotTimestamp; // HH:MM:SS
  final String screenshotDescription;
  final String content;
  final List<String> keywords;
  final List<String> entities;

  const PodcastSection({
    required this.subtitle,
    required this.screenshotTimestamp,
    required this.screenshotDescription,
    required this.content,
    required this.keywords,
    required this.entities,
  });

  factory PodcastSection.fromJson(Map<String, dynamic> json) {
    return PodcastSection(
      subtitle: json['subtitle'] as String? ?? '',
      screenshotTimestamp: json['screenshot_timestamp'] as String? ?? '',
      screenshotDescription: json['screenshot_description'] as String? ?? '',
      content: json['content'] as String? ?? '',
      keywords: (json['keywords'] as List<dynamic>? ?? []).cast<String>(),
      entities: (json['entities'] as List<dynamic>? ?? []).cast<String>(),
    );
  }
}
