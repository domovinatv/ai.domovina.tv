/// Model javnog profila govornika ("person hub") — agregira SVE epizode u
/// kojima jedna osoba GOVORI (diarizirani govornik), kroz sve kanale, iza
/// stabilnog slug-a.
///
/// Mapira se 1:1 na `GET https://mcp.domovina.ai/api/person/{slug}` iz
/// domovina-rag. Ruta u aplikaciji: `/p/:slug` (npr. `/p/don-tomislav-lukac`).
///
/// VAŽNO: person slug je primarni ključ u bazi i koristi se DOSLOVNO (s
/// crticama) — NE transformira se kao channel slug (`-`↔`_`). Kad gradiš link
/// na profil iz imena govornika, reproduciraj [personSlug] točno.
library;

/// ASCII-fold imena → stabilni slug. Mora se poklapati s backend logikom koja
/// generira primarni ključ (npr. "don Tomislav Lukač" → "don-tomislav-lukac",
/// "Željka Markić" → "zeljka-markic"). Ako slug ne postoji na serveru → 404 i
/// profil pokaže prazno stanje.
String personSlug(String name) {
  const fold = {
    'č': 'c', 'ć': 'c', 'š': 's', 'ž': 'z', 'đ': 'd',
    'Č': 'c', 'Ć': 'c', 'Š': 's', 'Ž': 'z', 'Đ': 'd',
  };
  var s = name.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');
  s = s.split('').map((ch) => fold[ch] ?? ch).join();
  s = s
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return s;
}

/// Jedna epizoda u kojoj osoba govori.
class PersonEpisode {
  final String youtubeId;
  final String? title;
  final String channel;
  final String uploadDate;

  /// Najranija sekunda u kojoj osoba govori u toj epizodi.
  final int firstTs;

  /// Gotov deep-link na player rutu (`/v/:id/t/:sec`). Koristi se direktno.
  final String deepLink;

  const PersonEpisode({
    required this.youtubeId,
    required this.title,
    required this.channel,
    required this.uploadDate,
    required this.firstTs,
    required this.deepLink,
  });

  /// In-app ruta iz [deepLink] (path bez sheme/hosta), npr.
  /// `https://domovina.ai/v/ID/t/6` → `/v/ID/t/6`. Fallback na `/v/:id` ako
  /// deep_link nije upotrebljiv.
  String get routePath {
    final dl = deepLink.trim();
    if (dl.isNotEmpty) {
      final uri = Uri.tryParse(dl);
      if (uri != null && uri.path.startsWith('/v/')) return uri.path;
    }
    return '/v/$youtubeId';
  }

  factory PersonEpisode.fromJson(Map<String, dynamic> json) {
    return PersonEpisode(
      youtubeId: json['youtube_id'] as String? ?? '',
      title: json['title'] as String?,
      channel: json['channel'] as String? ?? '',
      uploadDate: json['upload_date'] as String? ?? '',
      firstTs: (json['first_ts'] as num?)?.toInt() ?? 0,
      deepLink: json['deep_link'] as String? ?? '',
    );
  }
}

/// Broj epizoda na jednom kanalu (raspodjela "gostuje na").
class PersonChannelCount {
  final String channel;
  final int count;

  const PersonChannelCount({required this.channel, required this.count});

  /// Channel slug → route slug za `/c/:slug` (kanali koriste `-` umjesto `_`).
  String get channelRouteSlug => channel.replaceAll('_', '-');

  factory PersonChannelCount.fromJson(Map<String, dynamic> json) {
    return PersonChannelCount(
      channel: json['channel'] as String? ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Broj epizoda u jednom mjesecu ("2019-01") — za timeline graf.
class PersonMonthCount {
  final String month;
  final int count;

  const PersonMonthCount({required this.month, required this.count});

  factory PersonMonthCount.fromJson(Map<String, dynamic> json) {
    return PersonMonthCount(
      month: json['month'] as String? ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Cijeli profil govornika.
class PersonHub {
  final String name;
  final String slug;
  final String? avatarUrl;
  final int channelCount;
  final int episodeCount;
  final List<PersonChannelCount> channels;
  final List<PersonEpisode> episodes;
  final List<PersonMonthCount> timeline;

  const PersonHub({
    required this.name,
    required this.slug,
    required this.avatarUrl,
    required this.channelCount,
    required this.episodeCount,
    required this.channels,
    required this.episodes,
    required this.timeline,
  });

  factory PersonHub.fromJson(Map<String, dynamic> json) {
    final rawChannels = json['channels'] as List<dynamic>? ?? const [];
    final rawEpisodes = json['episodes'] as List<dynamic>? ?? const [];
    final rawTimeline = json['timeline'] as List<dynamic>? ?? const [];
    return PersonHub(
      name: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      channelCount: (json['channel_count'] as num?)?.toInt() ?? 0,
      episodeCount: (json['episode_count'] as num?)?.toInt() ?? 0,
      channels: rawChannels
          .map((e) => PersonChannelCount.fromJson(e as Map<String, dynamic>))
          .toList(),
      episodes: rawEpisodes
          .map((e) => PersonEpisode.fromJson(e as Map<String, dynamic>))
          .toList(),
      timeline: rawTimeline
          .map((e) => PersonMonthCount.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
