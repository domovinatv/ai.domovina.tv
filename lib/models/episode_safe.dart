/// Model za domovina_ai.episode_safes — per-epizoda Safe Multisig wallet, te
/// safe_actions audit trail. Vidi docs/channel-ownership-and-safe-payout-plan.md §5, §8.
library;

enum SafeStatus {
  active,
  frozen,
  settled,
  unknown;

  static SafeStatus fromJson(String? raw) => switch (raw) {
        'active' => SafeStatus.active,
        'frozen' => SafeStatus.frozen,
        'settled' => SafeStatus.settled,
        _ => SafeStatus.unknown,
      };
}

class EpisodeSafe {
  final String episodeId;
  final String youtubeChannelId;
  final String safeAddress;
  final int chainId;
  final int threshold;
  final SafeStatus status;

  const EpisodeSafe({
    required this.episodeId,
    required this.youtubeChannelId,
    required this.safeAddress,
    required this.chainId,
    required this.threshold,
    required this.status,
  });

  bool get isActive => status == SafeStatus.active;

  factory EpisodeSafe.fromJson(Map<String, dynamic> json) {
    return EpisodeSafe(
      episodeId: json['episode_id'] as String? ?? '',
      youtubeChannelId: json['youtube_channel_id'] as String? ?? '',
      safeAddress: json['safe_address'] as String? ?? '',
      chainId: json['chain_id'] as int? ?? 0,
      threshold: json['threshold'] as int? ?? 2,
      status: SafeStatus.fromJson(json['status'] as String?),
    );
  }
}

/// Jedna stavka audit traila (proposal/exec) nad Safe-om epizode.
class SafeAction {
  final String id;
  final String episodeId;
  final String action;
  final String? safeTxHash;
  final DateTime? createdAt;

  const SafeAction({
    required this.id,
    required this.episodeId,
    required this.action,
    this.safeTxHash,
    this.createdAt,
  });

  factory SafeAction.fromJson(Map<String, dynamic> json) {
    final c = json['created_at'] as String?;
    return SafeAction(
      id: json['id'] as String? ?? '',
      episodeId: json['episode_id'] as String? ?? '',
      action: json['action'] as String? ?? '',
      safeTxHash: json['safe_tx_hash'] as String?,
      createdAt: c == null ? null : DateTime.tryParse(c),
    );
  }
}
