/// Kandidat u glasanju o sljedećem kanalu (`domovina_ai.vote_candidates`
/// + agregat iz `domovina_ai.vote_tallies`).
///
/// Plan: `docs/plans/2026-08-08-glasanje-o-kanalima.md` §5, §7.1, §8.4.
///
/// Redak koji vraća `domovina_ai.round_leaderboard(...)` je kandidat **spojen**
/// s tallyjem svog kola, pa jedan model pokriva oboje: bez tallyja je
/// [up] = [down] = 0 (kandidat na kojeg u ovom kolu nitko nije glasao).
library;

import 'vote_round.dart';

/// Smjer glasa — mirror DB check constrainta `direction in (-1, 1)`.
const int kVoteDirectionUp = 1;
const int kVoteDirectionDown = -1;

/// Status kandidata kroz fulfillment petlju (§9).
enum VoteCandidateStatus {
  /// U igri — jedini status na koji se smije glasati.
  candidate,

  /// Pobijedio kolo, čeka operatera.
  winner,

  /// Pipeline ga obrađuje („U obradi").
  onboarding,

  /// Gotov — [VoteCandidate.onboardedChannelId] vodi na `/c/<id>`.
  onboarded,

  /// Povučen (nestao iz registra, počeo se pratiti, ili vlasnik ne želi).
  withdrawn,

  unknown;

  static VoteCandidateStatus fromJson(String? raw) => switch (raw) {
        'candidate' => VoteCandidateStatus.candidate,
        'winner' => VoteCandidateStatus.winner,
        'onboarding' => VoteCandidateStatus.onboarding,
        'onboarded' => VoteCandidateStatus.onboarded,
        'withdrawn' => VoteCandidateStatus.withdrawn,
        _ => VoteCandidateStatus.unknown,
      };
}

/// Što kandidat zapravo jest u registru — pipeline ne guta sve isto (§11.3).
enum VoteSourceType {
  channel,
  playlist,
  audioPrimary,
  unknown;

  static VoteSourceType fromJson(String? raw) => switch (raw) {
        'channel' => VoteSourceType.channel,
        'playlist' => VoteSourceType.playlist,
        'audio-primary' => VoteSourceType.audioPrimary,
        _ => VoteSourceType.unknown,
      };
}

class VoteCandidate {
  /// Registry slug — koristi se **DOSLOVNO** (primarni ključ u bazi i u
  /// ruti `/glasanje/:slug`), nikad kroz `-`↔`_` transformaciju.
  final String slug;

  final String displayName;
  final String youtubeUrl;
  final String? youtubeChannelId;

  /// CDN avatar (`cdn.domovina.ai/registry/avatars/<slug>.jpg`, §8.4).
  /// **Nikad YouTube URL izravno** — CORS puca.
  final String? avatarUrl;

  final List<String> tags;
  final List<String> voditelji;
  final int? subscribers;
  final int? episodesEstimate;
  final int? qualityScore;
  final int? tier;
  final String? notes;
  final VoteSourceType sourceType;
  final VoteCandidateStatus status;
  final String? onboardedChannelId;

  /// Agregat kola (`vote_tallies`). Bez retka u tallyju su nule.
  final int up;
  final int down;

  /// Mjesto na ljestvici koje je **server** izračunao (`round_leaderboard.rank`,
  /// ugovor v1.1). Klijent ga nikad ne izvodi iz redoslijeda liste jer sortovi
  /// `random` / `least_votes` ne slažu redoslijed po rangu.
  final int? rank;

  const VoteCandidate({
    required this.slug,
    required this.displayName,
    this.youtubeUrl = '',
    this.youtubeChannelId,
    this.avatarUrl,
    this.tags = const [],
    this.voditelji = const [],
    this.subscribers,
    this.episodesEstimate,
    this.qualityScore,
    this.tier,
    this.notes,
    this.sourceType = VoteSourceType.unknown,
    this.status = VoteCandidateStatus.candidate,
    this.onboardedChannelId,
    this.up = 0,
    this.down = 0,
    this.rank,
  });

  /// Rangiranje je **neto 👍−👎**, bez Wilsona i bez težina (§7.1).
  int get net => up - down;

  /// Ukupno glasova na kandidatu — druga polovica kvoruma (§7.2).
  int get totalVotes => up + down;

  /// Smije li se glasati na ovog kandidata. Pobjednik proglašen usred kola
  /// izlazi iz igre → server vraća `candidate_not_available` (§6.4).
  bool get isVotable => status == VoteCandidateStatus.candidate;

  /// Zadovoljava li kandidat kvorum kola (§7.2) — oboje mora vrijediti.
  bool meetsQuorum(VoteRound round) =>
      net >= round.effectiveQuorumNet &&
      totalVotes >= round.effectiveQuorumTotal;

  /// Optimistički pomak tallyja odmah nakon tapa, prije nego server potvrdi
  /// (`VotingService.castVote` ga vraća na staro ako RPC padne).
  VoteCandidate withOptimisticVote(int direction) => copyWith(
        up: direction > 0 ? up + 1 : up,
        down: direction < 0 ? down + 1 : down,
      );

  VoteCandidate copyWith({
    int? up,
    int? down,
    VoteCandidateStatus? status,
    String? onboardedChannelId,
  }) =>
      VoteCandidate(
        slug: slug,
        displayName: displayName,
        youtubeUrl: youtubeUrl,
        youtubeChannelId: youtubeChannelId,
        avatarUrl: avatarUrl,
        tags: tags,
        voditelji: voditelji,
        subscribers: subscribers,
        episodesEstimate: episodesEstimate,
        qualityScore: qualityScore,
        tier: tier,
        notes: notes,
        sourceType: sourceType,
        status: status ?? this.status,
        onboardedChannelId: onboardedChannelId ?? this.onboardedChannelId,
        up: up ?? this.up,
        down: down ?? this.down,
        rank: rank,
      );

  factory VoteCandidate.fromJson(Map<String, dynamic> json) {
    int? asInt(Object? v) => v is int ? v : int.tryParse('${v ?? ''}');
    List<String> asList(Object? v) => v is List
        ? v.map((e) => '$e').where((e) => e.isNotEmpty).toList(growable: false)
        : const [];

    return VoteCandidate(
      slug: json['slug'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      youtubeUrl: json['youtube_url'] as String? ?? '',
      youtubeChannelId: json['youtube_channel_id'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      tags: asList(json['tags']),
      voditelji: asList(json['voditelji']),
      subscribers: asInt(json['subscribers']),
      episodesEstimate: asInt(json['episodes_estimate']),
      qualityScore: asInt(json['quality_score']),
      tier: asInt(json['tier']),
      notes: json['notes'] as String?,
      sourceType: VoteSourceType.fromJson(json['source_type'] as String?),
      status: VoteCandidateStatus.fromJson(json['status'] as String?),
      onboardedChannelId: json['onboarded_channel_id'] as String?,
      up: asInt(json['up']) ?? 0,
      down: asInt(json['down']) ?? 0,
      rank: asInt(json['rank']),
    );
  }
}

/// Redoslijed ljestvice. Postoji zbog §3.1 — uz 181 kandidata i jedan glas
/// dnevno vrh se cementira, pa rep mora imati vlastiti ulaz.
enum VoteSort {
  /// Neto silazno, tie-break `up desc → quality_score desc → slug asc` (§7.1).
  leaderboard('leaderboard'),

  /// Nasumično promiješan bazen.
  random('random'),

  /// Bottom-N shuffle — kandidati s najmanje glasova.
  leastVotes('least_votes');

  const VoteSort(this.wire);

  /// Vrijednost koja ide u `round_leaderboard(p_sort => …)`.
  final String wire;
}
