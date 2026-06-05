library;

/// Zahtjev/zapis isplate kampanje (`pinka_finance.payouts`). Owner zatraži,
/// off-chain izvršitelj (pay.domovina.ai/ops) pomiče stanje + tx.
class PinkaPayout {
  final String id;
  final int amountCents;

  /// 0x EVM adresa ili IBAN.
  final String destination;

  /// requested | approved | submitted | confirmed | failed
  final String state;
  final String? txHash;
  final String? createdAt;

  const PinkaPayout({
    required this.id,
    required this.amountCents,
    required this.destination,
    required this.state,
    required this.txHash,
    required this.createdAt,
  });

  /// Doprinosi "u tijeku" (rezerviraju raspoloživo stanje).
  bool get isPending =>
      state == 'requested' || state == 'approved' || state == 'submitted';
  bool get isConfirmed => state == 'confirmed';
  bool get reservesFunds => isPending || isConfirmed;
  bool get isOnchain => destination.startsWith('0x');

  factory PinkaPayout.fromJson(Map<String, dynamic> json) {
    return PinkaPayout(
      id: json['id'] as String,
      amountCents: (json['amount_cents'] as int?) ?? 0,
      destination: (json['destination'] as String?) ?? '',
      state: (json['state'] as String?) ?? 'requested',
      txHash: json['tx_hash'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }
}

/// Sažetak raspoloživosti isplate. Raspoloživo = prikupljeno − isplate
/// + akumulirani prinos (prinos pripada kampanji).
class PinkaPayoutSummary {
  final int raisedCents;
  final int pendingCents;
  final int paidCents;
  final int accruedYieldCents;

  const PinkaPayoutSummary({
    required this.raisedCents,
    required this.pendingCents,
    required this.paidCents,
    this.accruedYieldCents = 0,
  });

  int get availableCents {
    final v = raisedCents - pendingCents - paidCents + accruedYieldCents;
    return v < 0 ? 0 : v;
  }

  /// Iz prikupljenog iznosa + liste isplata (+ opcionalni akumulirani prinos).
  factory PinkaPayoutSummary.from(
    int raisedCents,
    List<PinkaPayout> payouts, {
    int accruedYieldCents = 0,
  }) {
    var pending = 0;
    var paid = 0;
    for (final p in payouts) {
      if (p.isConfirmed) {
        paid += p.amountCents;
      } else if (p.isPending) {
        pending += p.amountCents;
      }
    }
    return PinkaPayoutSummary(
      raisedCents: raisedCents,
      pendingCents: pending,
      paidCents: paid,
      accruedYieldCents: accruedYieldCents,
    );
  }
}
