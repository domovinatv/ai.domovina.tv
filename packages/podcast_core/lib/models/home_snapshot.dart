import '../brand/domain_score.dart';
import 'channel_detail.dart';

/// `channels/data/home.json` — gotov izbor epizoda za naslovnicu, koji noćni
/// run generira uz `index.json`.
///
/// Zašto postoji: naslovnica je za hero i railove čekala SVIH 50 listinga
/// kanala (6,9 MB sirovo / 1,3 MB preko žice), a od njih koristi ~150 epizoda
/// sa 6 polja. Ova datoteka nosi samo njih (~10 KB brotli). Mjerenja i plan:
/// `docs/2026-10-08-brzina-ucitavanja-naslovnice.md` (P1).
///
/// **Ugovor (v1)** — pipeline u `episodes` stavlja uniju, bez duplikata:
///  1. sve epizode s datumom unutar zadnjih 45 dana (pokriva hero tier 1 od
///     14 dana i „Upravo stiglo" od 30 dana);
///  2. do 20 epizoda s `has_magisterium` i `magisterium_score ≥ 70`, najbolji
///     score prvi, bilo koji datum (hero tier 2 kad je tier 1 prazan);
///  3. 30 najnovijih epizoda s `has_article` (rail „Najnovije" kad zadnjih 45
///     dana ima malo obrađenih).
///
/// Algoritam izbora hera ostaje u klijentu (`HomeFeed.pickFeaturedCarousel`);
/// pipeline daje bazen, ne odluku. Uz gornja tri pravila taj algoritam nad
/// ovim bazenom vraća isti izbor kao nad cijelim katalogom.
class HomeSnapshot {
  static const int supportedVersion = 1;

  final int version;
  final String? generatedAt;
  final List<HomeSnapshotEpisode> episodes;

  const HomeSnapshot({
    required this.version,
    required this.generatedAt,
    required this.episodes,
  });

  /// `null` za nepoznatu verziju — klijent tada ide starim putem (svi
  /// listinzi), umjesto da krivo pročita novi oblik.
  static HomeSnapshot? tryParse(Map<String, dynamic> json) {
    final version = (json['version'] as num?)?.toInt();
    if (version != supportedVersion) return null;
    final raw = json['episodes'];
    if (raw is! List) return null;
    return HomeSnapshot(
      version: version!,
      generatedAt: json['generated_at'] as String?,
      episodes: [
        for (final e in raw)
          if (e is Map<String, dynamic> && e['id'] is String && e['c'] is String)
            HomeSnapshotEpisode.fromJson(e),
      ],
    );
  }
}

class HomeSnapshotEpisode {
  final String channelId;
  final ChannelVideo video;

  const HomeSnapshotEpisode({required this.channelId, required this.video});

  factory HomeSnapshotEpisode.fromJson(Map<String, dynamic> json) {
    return HomeSnapshotEpisode(
      channelId: json['c'] as String,
      video: ChannelVideo(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        titleHr: json['title_hr'] as String?,
        date: json['date'] as String?,
        durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
        magisteriumScore: domainScoreFromJson(json['magisterium_score']),
        pipeline: VideoPipeline.fromBits((json['p'] as num?)?.toInt() ?? 0),
      ),
    );
  }
}
