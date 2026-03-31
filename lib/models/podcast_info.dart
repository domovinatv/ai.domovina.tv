/// Model za info.json — yt-dlp metadata
class PodcastInfo {
  final String id;
  final String title;
  final String channel;
  final String channelId;
  final String uploader;
  final String uploadDate; // YYYYMMDD
  final int duration; // seconds
  final String durationString;
  final int viewCount;
  final int likeCount;
  final int? commentCount;
  final String description;
  final String thumbnail;
  final String webpageUrl;
  final List<String> tags;
  final List<String> categories;
  final List<YtChapter> chapters;
  final List<YtThumbnail> thumbnails;

  const PodcastInfo({
    required this.id,
    required this.title,
    required this.channel,
    required this.channelId,
    required this.uploader,
    required this.uploadDate,
    required this.duration,
    required this.durationString,
    required this.viewCount,
    required this.likeCount,
    this.commentCount,
    required this.description,
    required this.thumbnail,
    required this.webpageUrl,
    required this.tags,
    required this.categories,
    required this.chapters,
    required this.thumbnails,
  });

  factory PodcastInfo.fromJson(Map<String, dynamic> json) {
    return PodcastInfo(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      channel: json['channel'] as String? ?? '',
      channelId: json['channel_id'] as String? ?? '',
      uploader: json['uploader'] as String? ?? '',
      uploadDate: json['upload_date'] as String? ?? '',
      duration: json['duration'] as int? ?? 0,
      durationString: json['duration_string'] as String? ?? '',
      viewCount: json['view_count'] as int? ?? 0,
      likeCount: json['like_count'] as int? ?? 0,
      commentCount: json['comment_count'] as int?,
      description: json['description'] as String? ?? '',
      thumbnail: json['thumbnail'] as String? ?? '',
      webpageUrl: json['webpage_url'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>? ?? []).cast<String>(),
      categories: (json['categories'] as List<dynamic>? ?? []).cast<String>(),
      chapters: (json['chapters'] as List<dynamic>? ?? [])
          .map((c) => YtChapter.fromJson(c as Map<String, dynamic>))
          .toList(),
      thumbnails: (json['thumbnails'] as List<dynamic>? ?? [])
          .map((t) => YtThumbnail.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Parses uploadDate (YYYYMMDD) into DateTime
  DateTime get uploadDateTime {
    final s = uploadDate;
    if (s.length == 8) {
      return DateTime(
        int.parse(s.substring(0, 4)),
        int.parse(s.substring(4, 6)),
        int.parse(s.substring(6, 8)),
      );
    }
    return DateTime.now();
  }
}

class YtChapter {
  final double startTime;
  final String title;

  const YtChapter({required this.startTime, required this.title});

  factory YtChapter.fromJson(Map<String, dynamic> json) {
    return YtChapter(
      startTime: (json['start_time'] as num?)?.toDouble() ?? 0,
      title: json['title'] as String? ?? '',
    );
  }
}

class YtThumbnail {
  final String url;
  final int? width;
  final int? height;

  const YtThumbnail({required this.url, this.width, this.height});

  factory YtThumbnail.fromJson(Map<String, dynamic> json) {
    return YtThumbnail(
      url: json['url'] as String? ?? '',
      width: json['width'] as int?,
      height: json['height'] as int?,
    );
  }
}
