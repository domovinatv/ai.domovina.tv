library;

/// Odgovor `pinka-contribute` edge funkcije — sve potrebno za prikaz SEPA QR-a
/// (EPC069-12) + polling stanja doprinosa.
class PinkaContributionIntent {
  final String contributionId;
  final String sid;
  final String amountEur;
  final int amountCents;
  final String currency;
  final String memo;
  final String iban;
  final String beneficiaryName;
  final String bic;

  /// EPC069-12 payload (10 linija) za bankovni QR sken.
  final String epcQrData;
  final String checkoutUrl;
  final String? statusUrl;
  final String? expiresAt;

  /// Mjesta rezervirana ovom uplatom (grid kvadratići / sjedala) i trenutak
  /// do kojeg hold vrijedi. Hold i vijek intenta umiru istovremeno — backend
  /// ih izjednačuje u `attach_intent`.
  final List<String> slotKeys;
  final DateTime? holdExpiresAt;

  const PinkaContributionIntent({
    required this.contributionId,
    required this.sid,
    required this.amountEur,
    required this.amountCents,
    required this.currency,
    required this.memo,
    required this.iban,
    required this.beneficiaryName,
    required this.bic,
    required this.epcQrData,
    required this.checkoutUrl,
    required this.statusUrl,
    required this.expiresAt,
    this.slotKeys = const [],
    this.holdExpiresAt,
  });

  factory PinkaContributionIntent.fromJson(Map<String, dynamic> json) {
    return PinkaContributionIntent(
      contributionId: json['contribution_id'] as String,
      sid: (json['sid'] as String?) ?? '',
      amountEur: json['amount_eur']?.toString() ?? '',
      amountCents: (json['amount_cents'] as int?) ?? 0,
      currency: (json['currency'] as String?) ?? 'eur',
      memo: (json['memo'] as String?) ?? '',
      iban: (json['iban'] as String?) ?? '',
      beneficiaryName: (json['beneficiary_name'] as String?) ?? '',
      bic: (json['bic'] as String?) ?? '',
      epcQrData: (json['epc_qr_data'] as String?) ?? '',
      checkoutUrl: (json['checkout_url'] as String?) ?? '',
      statusUrl: json['status_url'] as String?,
      expiresAt: json['expires_at'] as String?,
      slotKeys: (json['slot_keys'] as List?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const [],
      holdExpiresAt:
          DateTime.tryParse((json['hold_expires_at'] as String?) ?? ''),
    );
  }
}
