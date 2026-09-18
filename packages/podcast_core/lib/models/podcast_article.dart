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
  final String? themeEn;
  final String? reasonForCut;
  final String? reasonForCutEn;
  final List<PodcastSection> sections;

  const ArticleIteration({
    required this.iterationNumber,
    required this.startTime,
    required this.endTime,
    required this.theme,
    this.themeEn,
    this.reasonForCut,
    this.reasonForCutEn,
    required this.sections,
  });

  factory ArticleIteration.fromJson(Map<String, dynamic> json) {
    return ArticleIteration(
      iterationNumber: json['iteration_number'] as int? ?? 0,
      startTime: json['start_time'] as String? ?? '',
      endTime: json['end_time'] as String? ?? '',
      theme: json['theme'] as String? ?? '',
      themeEn: json['theme_en'] as String?,
      reasonForCut: json['reason_for_cut'] as String?,
      reasonForCutEn: json['reason_for_cut_en'] as String?,
      sections: (json['sections'] as List<dynamic>? ?? [])
          .map((s) => PodcastSection.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}

class PodcastSection {
  final String subtitle;
  final String? subtitleEn;
  final String screenshotTimestamp; // HH:MM:SS
  final String screenshotDescription;
  final String? screenshotDescriptionEn;
  final String content;
  final String? contentEn;
  final List<String> keywords;
  final List<String>? keywordsEn;
  final List<String> entities;
  final List<String>? entitiesEn;

  const PodcastSection({
    required this.subtitle,
    this.subtitleEn,
    required this.screenshotTimestamp,
    required this.screenshotDescription,
    this.screenshotDescriptionEn,
    required this.content,
    this.contentEn,
    required this.keywords,
    this.keywordsEn,
    required this.entities,
    this.entitiesEn,
  });

  static List<String>? _optList(dynamic raw) {
    if (raw is! List) return null;
    return raw.cast<String>();
  }

  factory PodcastSection.fromJson(Map<String, dynamic> json) {
    return PodcastSection(
      subtitle: json['subtitle'] as String? ?? '',
      subtitleEn: json['subtitle_en'] as String?,
      screenshotTimestamp: json['screenshot_timestamp'] as String? ?? '',
      screenshotDescription: json['screenshot_description'] as String? ?? '',
      screenshotDescriptionEn: json['screenshot_description_en'] as String?,
      content: json['content'] as String? ?? '',
      contentEn: json['content_en'] as String?,
      keywords: (json['keywords'] as List<dynamic>? ?? []).cast<String>(),
      keywordsEn: _optList(json['keywords_en']),
      entities: (json['entities'] as List<dynamic>? ?? []).cast<String>(),
      entitiesEn: _optList(json['entities_en']),
    );
  }
}
