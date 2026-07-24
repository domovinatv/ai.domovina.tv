/// Matcha kanonski YouTube channel ID `UC` + 22 znaka (base64url alfabet).
final RegExp kYoutubeChannelIdPattern = RegExp(r'^UC[0-9A-Za-z_-]{22}$');

/// Vrati validan `UC…` ID iz eksplicitnog polja, ili ga izvuci iz
/// `youtube_channel_url` (npr. `https://www.youtube.com/channel/UC…`).
/// Handle/`/c/` URL-ovi nemaju UC ID pa vraćaju null. Vidi
/// docs/channel-ownership-and-safe-payout-plan.md (Faza 0).
String? canonicalUcId(String? explicit, String? url) {
  if (explicit != null && kYoutubeChannelIdPattern.hasMatch(explicit)) {
    return explicit;
  }
  if (url != null) {
    final m = RegExp(r'/channel/(UC[0-9A-Za-z_-]{22})').firstMatch(url);
    if (m != null) return m.group(1);
  }
  return null;
}

/// Model za /channels/data/{channel_id}.json
class ChannelDetail {
  final String version;
  final String id;
  final String name;
  final String? avatarSquare;
  final String? avatarCover;
  final String youtubeChannelUrl;

  /// Kanonski YouTube channel ID (`UC…`). Izvor: pipeline upisuje yt-dlp
  /// `channel_id` u channel.json. Potreban za ownership verifikaciju
  /// (`channels.list?mine=true` match). Null dok pipeline ne upiše polje
  /// (osim ako se da izvući iz `/channel/UC…` URL-a).
  final String? youtubeChannelId;
  final String? youtubePlaylistUrl;
  final String? description;
  final List<String> tags;
  final int? followerCount;
  final int videoCount;
  final int totalDurationSeconds;
  final int? avgMagisteriumScore;
  final String? latestVideoDate;
  final List<ChannelVideo> videos;

  const ChannelDetail({
    required this.version,
    required this.id,
    required this.name,
    this.avatarSquare,
    this.avatarCover,
    required this.youtubeChannelUrl,
    this.youtubeChannelId,
    this.youtubePlaylistUrl,
    this.description,
    this.tags = const [],
    this.followerCount,
    required this.videoCount,
    required this.totalDurationSeconds,
    this.avgMagisteriumScore,
    this.latestVideoDate,
    required this.videos,
  });

  /// True kad je kanal audio-only izvor (podcast feed, npr. launchedfm.com /
  /// subclub.com) — `youtube_channel_url` host nije youtube.com/youtu.be.
  /// Pouzdano na razini KANALA (vlastiti URL kanala), za razliku od per-epizoda
  /// heuristike koja false-pozitivira (i video epizode na tim kanalima imaju
  /// ne-YouTube URL). Koristi se da channel listing prikaže "Audio Only"
  /// placeholder umjesto generičkog video placeholdera kad epizoda nema thumbnail.
  bool get isAudioSource {
    final host = Uri.tryParse(youtubeChannelUrl)?.host ?? '';
    return host.isNotEmpty &&
        !host.contains('youtube.com') &&
        !host.contains('youtu.be');
  }

  factory ChannelDetail.fromJson(Map<String, dynamic> json) {
    return ChannelDetail(
      version: json['version'] as String? ?? '1.0',
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      avatarSquare: json['avatar_square'] as String?,
      avatarCover: json['avatar_cover'] as String?,
      youtubeChannelUrl: json['youtube_channel_url'] as String? ?? '',
      youtubeChannelId: canonicalUcId(
        json['youtube_channel_id'] as String?,
        json['youtube_channel_url'] as String?,
      ),
      youtubePlaylistUrl: json['youtube_playlist_url'] as String?,
      description: json['description'] as String?,
      tags: (json['tags'] as List<dynamic>? ?? []).cast<String>(),
      followerCount: json['follower_count'] as int?,
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
  final List<String> speakers;
  final int? magisteriumScore;
  final VideoPipeline? pipeline;

  /// Izvor epizode (npr. `youtube`/`beamly`) i direktni audio link — prisutni
  /// samo ako ih pipeline upiše u channel listing (trenutno još nije slučaj;
  /// detekcija pada na [isAudioOnly] heuristiku po [youtubeUrl] hostu).
  final String? source;
  final String? soundLink;

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
    this.source,
    this.soundLink,
  });

  /// Display title — prefer Croatian title.
  String get displayTitle => titleHr ?? title;

  /// True SAMO kad channel listing eksplicitno nosi [soundLink] (trenutno ne).
  /// NE smije se izvoditi heuristikom iz [youtubeUrl] hosta — i video epizode
  /// na ne-YouTube kanalima (npr. subclub.com) imaju takav URL, pa bi se sve
  /// lažno označilo kao audio. Autoritativna audio-vs-video odluka je probe na
  /// episode ekranu (`EpisodeData.isAudioOnly` — postoji li `audio.mp3`); u
  /// channel listingu nema pouzdanog signala dok ga pipeline ne doda.
  bool get isAudioOnly => soundLink != null && soundLink!.isNotEmpty;

  factory ChannelVideo.fromJson(Map<String, dynamic> json) {
    // speakers can be List<String> or List<{id, suggested_name, role}>
    final rawSpeakers = json['speakers'] as List<dynamic>? ?? [];
    final speakers = rawSpeakers.map((s) {
      if (s is String) return s;
      if (s is Map<String, dynamic>) {
        return s['suggested_name'] as String? ?? s['name'] as String? ?? '';
      }
      return s.toString();
    }).toList();

    return ChannelVideo(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      titleHr: json['title_hr'] as String?,
      date: json['date'] as String?,
      // num.toInt() (ne `as int?`) — X/Twitter izvor daje decimalne vrijednosti.
      durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
      durationDisplay: json['duration_display'] as String?,
      views: (json['views'] as num?)?.toInt(),
      likes: (json['likes'] as num?)?.toInt(),
      thumbnail: json['thumbnail'] as String?,
      youtubeUrl: json['youtube_url'] as String?,
      abstract_: json['abstract'] as String?,
      topics: (json['topics'] as List<dynamic>? ?? []).cast<String>(),
      speakers: speakers,
      magisteriumScore: json['magisterium_score'] as int?,
      pipeline: json['pipeline'] != null
          ? VideoPipeline.fromJson(json['pipeline'] as Map<String, dynamic>)
          : null,
      source: json['source'] as String? ?? json['_source'] as String?,
      soundLink:
          json['sound_link'] as String? ?? json['_sound_link'] as String?,
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
