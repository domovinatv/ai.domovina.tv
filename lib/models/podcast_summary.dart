/// Model za .wav.canary.summary.json — Gemini AI sažetak
class PodcastSummary {
  final String version;
  final DateTime generatedAt;
  final String model;
  final SummarySource source;
  final SummaryContent summary;

  const PodcastSummary({
    required this.version,
    required this.generatedAt,
    required this.model,
    required this.source,
    required this.summary,
  });

  factory PodcastSummary.fromJson(Map<String, dynamic> json) {
    return PodcastSummary(
      version: json['version'] as String,
      generatedAt: DateTime.parse(json['generated_at'] as String),
      model: json['model'] as String,
      source: SummarySource.fromJson(json['source'] as Map<String, dynamic>),
      summary: SummaryContent.fromJson(json['summary'] as Map<String, dynamic>),
    );
  }
}

class SummarySource {
  final String filename;
  final String channel;
  final String youtubeId;
  final String title;
  final String uploadDate; // YYYY-MM-DD
  final int durationSeconds;

  const SummarySource({
    required this.filename,
    required this.channel,
    required this.youtubeId,
    required this.title,
    required this.uploadDate,
    required this.durationSeconds,
  });

  factory SummarySource.fromJson(Map<String, dynamic> json) {
    return SummarySource(
      filename: json['filename'] as String,
      channel: json['channel'] as String,
      youtubeId: json['youtube_id'] as String,
      title: json['title'] as String,
      uploadDate: json['upload_date'] as String,
      durationSeconds: json['duration_seconds'] as int,
    );
  }
}

class SummaryContent {
  final String titleHr;
  final String abstractHr;
  final List<String> keyTopics;
  final List<SummarySpeaker> speakers;
  final List<String> keyPoints;
  final List<String> mentionedPeople;
  final List<String> mentionedPlaces;
  final List<String> mentionedOrganizations;
  final String language;
  final String contentType;
  final String sentiment;

  const SummaryContent({
    required this.titleHr,
    required this.abstractHr,
    required this.keyTopics,
    required this.speakers,
    required this.keyPoints,
    required this.mentionedPeople,
    required this.mentionedPlaces,
    required this.mentionedOrganizations,
    required this.language,
    required this.contentType,
    required this.sentiment,
  });

  factory SummaryContent.fromJson(Map<String, dynamic> json) {
    return SummaryContent(
      titleHr: json['title_hr'] as String,
      abstractHr: json['abstract_hr'] as String,
      keyTopics: (json['key_topics'] as List<dynamic>).cast<String>(),
      speakers: (json['speakers'] as List<dynamic>)
          .map((s) => SummarySpeaker.fromJson(s as Map<String, dynamic>))
          .toList(),
      keyPoints: (json['key_points'] as List<dynamic>).cast<String>(),
      mentionedPeople: (json['mentioned_people'] as List<dynamic>).cast<String>(),
      mentionedPlaces: (json['mentioned_places'] as List<dynamic>).cast<String>(),
      mentionedOrganizations:
          (json['mentioned_organizations'] as List<dynamic>).cast<String>(),
      language: json['language'] as String,
      contentType: json['content_type'] as String,
      sentiment: json['sentiment'] as String,
    );
  }
}

class SummarySpeaker {
  final String id;
  final String suggestedName;
  final String role;

  const SummarySpeaker({
    required this.id,
    required this.suggestedName,
    required this.role,
  });

  factory SummarySpeaker.fromJson(Map<String, dynamic> json) {
    return SummarySpeaker(
      id: json['id'] as String,
      suggestedName: json['suggested_name'] as String,
      role: json['role'] as String,
    );
  }
}
