library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Živi status SEPA payment intenta s MPT raila (`GET /api/intents/<sid>`).
///
/// Rail derivira fine-grained progress (join D1 payment_intents ↔
/// monerium_orders ↔ monerium_forwards) i vraća `status.stage` + per-step
/// timeline — isto što renderira i checkout stranica na pay.domovina.ai.
/// Poštene granice (vidi payment-status-timeline.md u rail repou): "blind
/// window" prije Monerium webhooka je stvarno slijep — prvi korak ostaje
/// in_progress dok banka ne isporuči SEPA uplatu.
class PinkaIntentStatus {
  /// awaiting_payment | received_processing | minted | forwarding | settled
  /// | rejected | expired
  final String stage;
  final List<PinkaIntentStep> steps;
  final String? rejectedReason;

  const PinkaIntentStatus({
    required this.stage,
    required this.steps,
    this.rejectedReason,
  });

  bool get isRejected => stage == 'rejected';
  bool get isExpired => stage == 'expired';
}

class PinkaIntentStep {
  /// payment | processing | minted | forwarding | settled
  final String key;

  /// proven | in_progress | waiting | failed
  final String status;

  const PinkaIntentStep({required this.key, required this.status});
}

/// Dohvati status intenta; `null` na bilo koju grešku (UI tada zadrži
/// generički spinner — progress je ukras, `contribution_status` RPC ostaje
/// izvor istine za "plaćeno").
Future<PinkaIntentStatus?> fetchIntentStatus(String statusUrl) async {
  try {
    final res = await http
        .get(Uri.parse(statusUrl))
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body);
    if (body is! Map) return null;
    final status = body['status'];
    if (status is! Map) return null;
    final stage = status['stage'] as String?;
    if (stage == null) return null;
    final steps = <PinkaIntentStep>[
      for (final s in (status['steps'] as List? ?? const []))
        if (s is Map && s['key'] is String && s['status'] is String)
          PinkaIntentStep(
              key: s['key'] as String, status: s['status'] as String),
    ];
    return PinkaIntentStatus(
      stage: stage,
      steps: steps,
      rejectedReason: body['rejected_reason'] as String?,
    );
  } catch (_) {
    return null;
  }
}
