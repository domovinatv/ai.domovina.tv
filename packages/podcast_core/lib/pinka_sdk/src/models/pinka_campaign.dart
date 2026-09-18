library;

/// Pinka kampanja (red iz `pinka_finance.campaigns` + ugniježđeni
/// `campaign_stats`). Pokriva donacije i crowdfunding; on-chain je dostupan
/// kad kampanja ima [destinationAddress] (per-campaign Gnosis Safe).
class PinkaCampaign {
  final String id;
  final String slug;

  /// donation | crowdfund | tokenization | tickets | realestate
  final String type;
  final String title;
  final String? description;

  /// Cilj u centima; `null` = open-ended donacija (bez progress bara).
  final int? goalCents;
  final int minContributionCents;
  final String currency;
  final String? coverImageUrl;

  /// draft | active | funded | closed | cancelled
  final String state;

  /// Per-campaign Gnosis Safe (javan, verificiran na lancu). `null` → samo SEPA.
  final String? destinationAddress;
  final String chain;

  /// "Anchor" kanal kampanje (UC… id) — za listanje + admin po vlasništvu kanala.
  final String? youtubeChannelId;

  // Denormalizirani agregat (campaign_stats).
  final int totalRaisedCents;
  final int contributionCount;
  final int contributorCount;

  const PinkaCampaign({
    required this.id,
    required this.slug,
    required this.type,
    required this.title,
    required this.description,
    required this.goalCents,
    required this.minContributionCents,
    required this.currency,
    required this.coverImageUrl,
    required this.state,
    required this.destinationAddress,
    required this.chain,
    this.youtubeChannelId,
    required this.totalRaisedCents,
    required this.contributionCount,
    required this.contributorCount,
  });

  bool get hasGoal => (goalCents ?? 0) > 0;

  /// On-chain (EURe) uplata moguća samo kad kampanja ima Safe adresu.
  bool get supportsOnchain =>
      destinationAddress != null && destinationAddress!.isNotEmpty;

  /// 0.0–1.0; 0 kad nema cilja.
  double get progress {
    final g = goalCents;
    if (g == null || g <= 0) return 0;
    return (totalRaisedCents / g).clamp(0.0, 1.0);
  }

  /// Parsira red iz:
  ///  - direktnog `campaigns` selecta s ugniježđenim `campaign_stats(...)`, ILI
  ///  - `active_campaign_for_subject` RPC-a koji vraća stat stupce flat (top-level).
  factory PinkaCampaign.fromRow(Map<String, dynamic> json) {
    // campaign_stats je one-to-one pa PostgREST može vratiti objekt ILI listu.
    final raw = json['campaign_stats'];
    final statsMap =
        (raw is List ? (raw.isNotEmpty ? raw.first : null) : raw) as Map?;
    final s = statsMap?.cast<String, dynamic>();
    // Fallback na flat stupce (RPC), pa tek onda na nested campaign_stats.
    int stat(String key) =>
        (json[key] as int?) ?? (s?[key] as int?) ?? 0;
    return PinkaCampaign(
      id: json['id'] as String,
      slug: (json['slug'] as String?) ?? '',
      type: (json['type'] as String?) ?? 'donation',
      title: (json['title'] as String?) ?? '',
      description: json['description'] as String?,
      goalCents: json['goal_cents'] as int?,
      minContributionCents: (json['min_contribution_cents'] as int?) ?? 100,
      currency: (json['currency'] as String?) ?? 'eur',
      coverImageUrl: json['cover_image_url'] as String?,
      state: (json['state'] as String?) ?? 'active',
      destinationAddress: json['destination_address'] as String?,
      chain: (json['chain'] as String?) ?? 'gnosis',
      youtubeChannelId: json['youtube_channel_id'] as String?,
      totalRaisedCents: stat('total_raised_cents'),
      contributionCount: stat('contribution_count'),
      contributorCount: stat('contributor_count'),
    );
  }
}
