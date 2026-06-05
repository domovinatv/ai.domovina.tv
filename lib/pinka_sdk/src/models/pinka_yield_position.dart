library;

/// Stanje yield pozicije kampanje (`pinka_finance.yield_positions`). Javno
/// čitljivo za javne kampanje (transparentnost — sredstva "rade" na Aaveu).
class PinkaYieldPosition {
  final String campaignId;
  final String protocol; // npr. aave_v3_gnosis
  final int principalCents; // neto supplyano
  final int accruedYieldCents; // prinos (balance − principal)
  final int lastBalanceCents; // zadnji očitani aToken saldo
  final String? atokenAddress; // aGnoEURe
  final String status; // idle | active | paused
  final String? lastSyncedAt;

  const PinkaYieldPosition({
    required this.campaignId,
    required this.protocol,
    required this.principalCents,
    required this.accruedYieldCents,
    required this.lastBalanceCents,
    required this.atokenAddress,
    required this.status,
    required this.lastSyncedAt,
  });

  /// Sredstva su trenutno parkirana u protokolu (ima što prikazati na lancu).
  bool get isDeployed => lastBalanceCents > 0 || principalCents > 0;

  factory PinkaYieldPosition.fromJson(Map<String, dynamic> json) {
    return PinkaYieldPosition(
      campaignId: json['campaign_id'] as String,
      protocol: (json['protocol'] as String?) ?? 'aave_v3_gnosis',
      principalCents: (json['principal_cents'] as int?) ?? 0,
      accruedYieldCents: (json['accrued_yield_cents'] as int?) ?? 0,
      lastBalanceCents: (json['last_balance_cents'] as int?) ?? 0,
      atokenAddress: json['atoken_address'] as String?,
      status: (json['status'] as String?) ?? 'idle',
      lastSyncedAt: json['last_synced_at'] as String?,
    );
  }
}
