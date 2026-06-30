library;

import '../../../../services/locale_service.dart';
import 'pinka_link_preview.dart';

/// Jedan unos na "Zidu podrške" — red iz `pinka_finance.public_contributions`
/// viewa (samo `state='paid'`, ne-anonimni, javne kampanje). Anonimni doprinosi
/// i moderirane poruke su već filtrirani u viewu, ne ovdje.
class PinkaPublicContribution {
  final String id;
  final String? displayName;
  final String? message;
  final int amountCents;
  final String currency;
  final String? createdAt;
  final PinkaLinkPreview? linkPreview;

  const PinkaPublicContribution({
    required this.id,
    required this.displayName,
    required this.message,
    required this.amountCents,
    required this.currency,
    required this.createdAt,
    required this.linkPreview,
  });

  String get displayNameOrAnon {
    final n = displayName?.trim();
    return (n != null && n.isNotEmpty) ? n : appStrings.pinkaAnonymous;
  }

  factory PinkaPublicContribution.fromJson(Map<String, dynamic> json) {
    return PinkaPublicContribution(
      id: json['id'] as String,
      displayName: json['display_name'] as String?,
      message: json['message'] as String?,
      amountCents: (json['amount_cents'] as int?) ?? 0,
      currency: (json['currency'] as String?) ?? 'eur',
      createdAt: json['created_at'] as String?,
      linkPreview: PinkaLinkPreview.fromJson(json['link_preview']),
    );
  }
}
