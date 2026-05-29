/// pinka.finance modeli — kampanja vezana uz epizodu + rezultat doprinosa.
/// Backend: schema pinka_finance u domovina-api; rail: pay.domovina.ai.
library;

class PinkaCampaign {
  final String id;
  final String slug;
  final String title;
  final int? goalCents;
  final int minContributionCents;
  final String currency;
  final int totalRaisedCents;
  final int contributorCount;

  const PinkaCampaign({
    required this.id,
    required this.slug,
    required this.title,
    required this.goalCents,
    required this.minContributionCents,
    required this.currency,
    required this.totalRaisedCents,
    required this.contributorCount,
  });

  /// 0.0–1.0; 0 kad nema cilja (open-ended donacija).
  double get progress {
    final g = goalCents;
    if (g == null || g <= 0) return 0;
    return (totalRaisedCents / g).clamp(0.0, 1.0);
  }

  bool get hasGoal => (goalCents ?? 0) > 0;

  /// Red iz `pinka_finance.campaigns` + ugniježđeni `campaign_stats`.
  factory PinkaCampaign.fromRow(Map<String, dynamic> json) {
    final stats = (json['campaign_stats'] as Map?)?.cast<String, dynamic>();
    return PinkaCampaign(
      id: json['id'] as String,
      slug: (json['slug'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      goalCents: json['goal_cents'] as int?,
      minContributionCents: (json['min_contribution_cents'] as int?) ?? 100,
      currency: (json['currency'] as String?) ?? 'eur',
      totalRaisedCents: (stats?['total_raised_cents'] as int?) ?? 0,
      contributorCount: (stats?['contributor_count'] as int?) ?? 0,
    );
  }
}

/// Odgovor `pinka-contribute` edge funkcije — sve za prikaz QR-a + polling.
class PinkaContribution {
  final String contributionId;
  final String sid;
  final String amountEur;
  final String memo;
  final String iban;
  final String beneficiaryName;
  final String bic;
  final String epcQrData;
  final String checkoutUrl;
  final String? expiresAt;

  const PinkaContribution({
    required this.contributionId,
    required this.sid,
    required this.amountEur,
    required this.memo,
    required this.iban,
    required this.beneficiaryName,
    required this.bic,
    required this.epcQrData,
    required this.checkoutUrl,
    required this.expiresAt,
  });

  factory PinkaContribution.fromJson(Map<String, dynamic> json) {
    return PinkaContribution(
      contributionId: json['contribution_id'] as String,
      sid: json['sid'] as String,
      amountEur: (json['amount_eur']?.toString()) ?? '',
      memo: (json['memo'] as String?) ?? '',
      iban: (json['iban'] as String?) ?? '',
      beneficiaryName: (json['beneficiary_name'] as String?) ?? '',
      bic: (json['bic'] as String?) ?? '',
      epcQrData: (json['epc_qr_data'] as String?) ?? '',
      checkoutUrl: (json['checkout_url'] as String?) ?? '',
      expiresAt: json['expires_at'] as String?,
    );
  }
}
