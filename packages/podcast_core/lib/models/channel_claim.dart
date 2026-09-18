/// Model za domovina_ai.channel_claims — claim vlasništva nad YouTube kanalom.
/// Vidi docs/channel-ownership-and-safe-payout-plan.md §5.
library;

/// Status claima (mirror DB check constrainta).
enum ClaimStatus {
  pending,
  verified,
  revoked,
  disputed,
  unknown;

  static ClaimStatus fromJson(String? raw) => switch (raw) {
        'pending' => ClaimStatus.pending,
        'verified' => ClaimStatus.verified,
        'revoked' => ClaimStatus.revoked,
        'disputed' => ClaimStatus.disputed,
        _ => ClaimStatus.unknown,
      };
}

/// Uloga claimanta — prvi verified je primary, ostali collaborator (D2).
enum ClaimRole {
  primary,
  collaborator,
  unknown;

  static ClaimRole fromJson(String? raw) => switch (raw) {
        'primary' => ClaimRole.primary,
        'collaborator' => ClaimRole.collaborator,
        _ => ClaimRole.unknown,
      };
}

class ChannelClaim {
  final String id;
  final String accountId;
  final String youtubeChannelId;
  final String? channelTitle;
  final ClaimRole role;
  final ClaimStatus status;
  final DateTime? verifiedAt;
  final DateTime? lastCheckedAt;

  const ChannelClaim({
    required this.id,
    required this.accountId,
    required this.youtubeChannelId,
    this.channelTitle,
    required this.role,
    required this.status,
    this.verifiedAt,
    this.lastCheckedAt,
  });

  bool get isVerified => status == ClaimStatus.verified;

  /// D4: verified claim stariji od 90 dana mora proći re-verifikaciju prije
  /// payouta. `now` je injektabilan radi testabilnosti.
  bool needsReverify(DateTime now) {
    if (!isVerified || verifiedAt == null) return false;
    return now.difference(verifiedAt!).inDays >= 90;
  }

  factory ChannelClaim.fromJson(Map<String, dynamic> json) {
    DateTime? parse(String? s) => s == null ? null : DateTime.tryParse(s);
    return ChannelClaim(
      id: json['id'] as String? ?? '',
      accountId: json['account_id'] as String? ?? '',
      youtubeChannelId: json['youtube_channel_id'] as String? ?? '',
      channelTitle: json['channel_title'] as String?,
      role: ClaimRole.fromJson(json['role'] as String?),
      status: ClaimStatus.fromJson(json['status'] as String?),
      verifiedAt: parse(json['verified_at'] as String?),
      lastCheckedAt: parse(json['last_checked_at'] as String?),
    );
  }
}
