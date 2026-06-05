library;

/// Owner/admin pogled na kampanju — uključuje i `draft`/`private` (koje javni
/// view ne vraća) + popis vezanih epizoda. Koristi `PinkaAdminClient`.
class PinkaOwnerCampaign {
  final String id;
  final String slug;
  final String type;
  final String title;
  final String? description;
  final int? goalCents;
  final int minContributionCents;
  final String currency;
  final String? coverImageUrl;

  /// draft | active | funded | closed | cancelled
  final String state;

  /// private | unlisted | public
  final String visibility;
  final String? destinationAddress;
  final String? youtubeChannelId;

  /// YouTube video id-evi epizoda vezanih na kampanju (`campaign_subjects`).
  final List<String> episodeRefs;

  final int totalRaisedCents;
  final int contributionCount;
  final int contributorCount;

  // Yield (Aave) — opt-in po kampanji; prinos pripada kampanji.
  final bool yieldEnabled;
  final int principalCents;
  final int accruedYieldCents;
  final String? yieldAtokenAddress;
  final String? yieldLastSyncedAt;

  const PinkaOwnerCampaign({
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
    required this.visibility,
    required this.destinationAddress,
    required this.youtubeChannelId,
    required this.episodeRefs,
    required this.totalRaisedCents,
    required this.contributionCount,
    required this.contributorCount,
    this.yieldEnabled = false,
    this.principalCents = 0,
    this.accruedYieldCents = 0,
    this.yieldAtokenAddress,
    this.yieldLastSyncedAt,
  });

  bool get hasGoal => (goalCents ?? 0) > 0;
  bool get supportsOnchain =>
      destinationAddress != null && destinationAddress!.isNotEmpty;
  double get progress {
    final g = goalCents;
    if (g == null || g <= 0) return 0;
    return (totalRaisedCents / g).clamp(0.0, 1.0);
  }

  /// Red iz `campaigns` selecta s ugniježđenim `campaign_stats(...)` i
  /// `campaign_subjects(subject_type, subject_ref)`.
  factory PinkaOwnerCampaign.fromRow(Map<String, dynamic> json) {
    final rawStats = json['campaign_stats'];
    final statsMap =
        (rawStats is List ? (rawStats.isNotEmpty ? rawStats.first : null) : rawStats)
            as Map?;
    final s = statsMap?.cast<String, dynamic>();

    final rawSubjects = json['campaign_subjects'];
    final episodeRefs = <String>[];
    if (rawSubjects is List) {
      for (final e in rawSubjects) {
        if (e is Map &&
            (e['subject_type'] as String?) == 'podcast_episode') {
          final ref = e['subject_ref'] as String?;
          if (ref != null && ref.isNotEmpty) episodeRefs.add(ref);
        }
      }
    }

    // metadata.yield.enabled
    final meta = (json['metadata'] as Map?)?.cast<String, dynamic>();
    final yieldMeta = (meta?['yield'] as Map?)?.cast<String, dynamic>();
    final yieldEnabled = yieldMeta?['enabled'] == true;

    // yield_positions (1:1 → objekt ili lista)
    final rawYield = json['yield_positions'];
    final yieldMap = (rawYield is List
            ? (rawYield.isNotEmpty ? rawYield.first : null)
            : rawYield) as Map?;
    final yp = yieldMap?.cast<String, dynamic>();

    return PinkaOwnerCampaign(
      id: json['id'] as String,
      slug: (json['slug'] as String?) ?? '',
      type: (json['type'] as String?) ?? 'donation',
      title: (json['title'] as String?) ?? '',
      description: json['description'] as String?,
      goalCents: json['goal_cents'] as int?,
      minContributionCents: (json['min_contribution_cents'] as int?) ?? 100,
      currency: (json['currency'] as String?) ?? 'eur',
      coverImageUrl: json['cover_image_url'] as String?,
      state: (json['state'] as String?) ?? 'draft',
      visibility: (json['visibility'] as String?) ?? 'private',
      destinationAddress: json['destination_address'] as String?,
      youtubeChannelId: json['youtube_channel_id'] as String?,
      episodeRefs: episodeRefs,
      totalRaisedCents: (s?['total_raised_cents'] as int?) ?? 0,
      contributionCount: (s?['contribution_count'] as int?) ?? 0,
      contributorCount: (s?['contributor_count'] as int?) ?? 0,
      yieldEnabled: yieldEnabled,
      principalCents: (yp?['principal_cents'] as int?) ?? 0,
      accruedYieldCents: (yp?['accrued_yield_cents'] as int?) ?? 0,
      yieldAtokenAddress: yp?['atoken_address'] as String?,
      yieldLastSyncedAt: yp?['last_synced_at'] as String?,
    );
  }
}
