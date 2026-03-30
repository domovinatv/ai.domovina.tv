/// Model za /channels/index.json
class ChannelIndex {
  final String version;
  final int channelCount;
  final List<ChannelSummary> channels;

  const ChannelIndex({
    required this.version,
    required this.channelCount,
    required this.channels,
  });

  factory ChannelIndex.fromJson(Map<String, dynamic> json) {
    return ChannelIndex(
      version: json['version'] as String? ?? '1.0',
      channelCount: json['channel_count'] as int? ?? 0,
      channels: (json['channels'] as List<dynamic>? ?? [])
          .map((e) => ChannelSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ChannelSummary {
  final String id;
  final String name;
  final String youtubeChannelUrl;
  final int videoCount;
  final int totalDurationSeconds;
  final int? avgMagisteriumScore;
  final LatestVideo? latestVideo;

  const ChannelSummary({
    required this.id,
    required this.name,
    required this.youtubeChannelUrl,
    required this.videoCount,
    required this.totalDurationSeconds,
    this.avgMagisteriumScore,
    this.latestVideo,
  });

  String get durationDisplay {
    final h = totalDurationSeconds ~/ 3600;
    final m = (totalDurationSeconds % 3600) ~/ 60;
    return '${h}h ${m}m';
  }

  factory ChannelSummary.fromJson(Map<String, dynamic> json) {
    final lv = json['latest_video'];
    return ChannelSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      youtubeChannelUrl: json['youtube_channel_url'] as String? ?? '',
      videoCount: json['video_count'] as int? ?? 0,
      totalDurationSeconds: json['total_duration_seconds'] as int? ?? 0,
      avgMagisteriumScore: json['avg_magisterium_score'] as int?,
      latestVideo: lv != null && lv is Map<String, dynamic>
          ? LatestVideo.fromJson(lv)
          : null,
    );
  }
}

class LatestVideo {
  final String id;
  final String date;
  final String title;

  const LatestVideo({
    required this.id,
    required this.date,
    required this.title,
  });

  factory LatestVideo.fromJson(Map<String, dynamic> json) {
    return LatestVideo(
      id: json['id'] as String,
      date: json['date'] as String? ?? '',
      title: json['title'] as String? ?? '',
    );
  }
}
