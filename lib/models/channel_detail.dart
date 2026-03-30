/// Model za /channels/{channel_id}.json
class ChannelDetail {
  final String version;
  final String id;
  final String name;
  final String youtubeChannelUrl;
  final int videoCount;
  final int totalDurationSeconds;
  final int? avgMagisteriumScore;
  final String? latestVideoDate;
  final List<ChannelVideo> videos;

  const ChannelDetail({
    required this.version,
    required this.id,
    required this.name,
    required this.youtubeChannelUrl,
    required this.videoCount,
    required this.totalDurationSeconds,
    this.avgMagisteriumScore,
    this.latestVideoDate,
    required this.videos,
  });

  factory ChannelDetail.fromJson(Map<String, dynamic> json) {
    return ChannelDetail(
      version: json['version'] as String? ?? '1.0',
      id: json['id'] as String,
      name: json['name'] as String,
      youtubeChannelUrl: json['youtube_channel_url'] as String? ?? '',
      videoCount: json['video_count'] as int? ?? 0,
      totalDurationSeconds: json['total_duration_seconds'] as int? ?? 0,
      avgMagisteriumScore: json['avg_magisterium_score'] as int?,
      latestVideoDate: json['latest_video_date'] as String?,
      videos: (json['videos'] as List<dynamic>? ?? [])
          .map((e) => ChannelVideo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ChannelVideo {
  final String id;
  final String title;
  final String? titleHr;
  final String? date;
  final int? durationSeconds;
  final String? durationDisplay;
  final int? views;
  final int? likes;
  final String? thumbnail;
  final String? youtubeUrl;
  final String? abstract_;
  final List<String> topics;
  final List<VideoSpeaker> speakers;
  final int? magisteriumScore;
  final VideoPipeline? pipeline;

  const ChannelVideo({
    required this.id,
    required this.title,
    this.titleHr,
    this.date,
    this.durationSeconds,
    this.durationDisplay,
    this.views,
    this.likes,
    this.thumbnail,
    this.youtubeUrl,
    this.abstract_,
    this.topics = const [],
    this.speakers = const [],
    this.magisteriumScore,
    this.pipeline,
  });

  /// Display title — prefer Croatian title.
  String get displayTitle => titleHr ?? title;

  factory ChannelVideo.fromJson(Map<String, dynamic> json) {
    return ChannelVideo(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      titleHr: json['title_hr'] as String?,
      date: json['date'] as String?,
      durationSeconds: json['duration_seconds'] as int?,
      durationDisplay: json['duration_display'] as String?,
      views: json['views'] as int?,
      likes: json['likes'] as int?,
      thumbnail: json['thumbnail'] as String?,
      youtubeUrl: json['youtube_url'] as String?,
      abstract_: json['abstract'] as String?,
      topics: (json['topics'] as List<dynamic>? ?? []).cast<String>(),
      speakers: (json['speakers'] as List<dynamic>? ?? [])
          .map((e) => VideoSpeaker.fromJson(e as Map<String, dynamic>))
          .toList(),
      magisteriumScore: json['magisterium_score'] as int?,
      pipeline: json['pipeline'] != null
          ? VideoPipeline.fromJson(json['pipeline'] as Map<String, dynamic>)
          : null,
    );
  }
}

class VideoSpeaker {
  final String id;
  final String suggestedName;
  final String role;

  const VideoSpeaker({
    required this.id,
    required this.suggestedName,
    required this.role,
  });

  factory VideoSpeaker.fromJson(Map<String, dynamic> json) {
    return VideoSpeaker(
      id: json['id'] as String? ?? '',
      suggestedName: json['suggested_name'] as String? ?? '',
      role: json['role'] as String? ?? '',
    );
  }
}

class VideoPipeline {
  final bool hasTranscript;
  final bool hasDiarized;
  final bool hasSummary;
  final bool hasArticle;
  final bool hasMagisterium;

  const VideoPipeline({
    required this.hasTranscript,
    required this.hasDiarized,
    required this.hasSummary,
    required this.hasArticle,
    required this.hasMagisterium,
  });

  factory VideoPipeline.fromJson(Map<String, dynamic> json) {
    return VideoPipeline(
      hasTranscript: json['has_transcript'] as bool? ?? false,
      hasDiarized: json['has_diarized'] as bool? ?? false,
      hasSummary: json['has_summary'] as bool? ?? false,
      hasArticle: json['has_article'] as bool? ?? false,
      hasMagisterium: json['has_magisterium'] as bool? ?? false,
    );
  }
}
