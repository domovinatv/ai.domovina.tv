import 'dart:async';
import 'dart:developer';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../models/pinka.dart';

/// pinka.finance klijent — kampanja po epizodi, kreiranje doprinosa (preko
/// `pinka-contribute` edge fn) i polling stanja doprinosa.
///
/// Podatkovni tok: vidi domovina-api/docs/pinka-finance-platform-plan.md.
class PinkaService {
  static final PinkaService instance = PinkaService._();
  PinkaService._();

  sb.SupabaseClient get _client => sb.Supabase.instance.client;

  /// Aktivna javna kampanja za danu epizodu (subject_ref = youtubeId), s
  /// ugniježđenim agregatom. Vraća null ako epizoda nema kampanju (panel se
  /// tada uopće ne prikazuje).
  Future<PinkaCampaign?> campaignForEpisode(String youtubeId) async {
    try {
      final row = await _client
          .schema('pinka_finance')
          .from('campaigns')
          .select(
            'id, slug, title, goal_cents, min_contribution_cents, currency, '
            'campaign_stats(total_raised_cents, contributor_count)',
          )
          .eq('subject_type', 'podcast_episode')
          .eq('subject_ref', youtubeId)
          .eq('state', 'active')
          .maybeSingle();
      if (row == null) return null;
      return PinkaCampaign.fromRow(row);
    } catch (e) {
      log('pinka: campaignForEpisode failed — $e');
      return null;
    }
  }

  /// Kreira pending doprinos + payment intent na rail-u; vraća QR/EPC podatke.
  Future<PinkaContribution> contribute({
    required String campaignId,
    required int amountCents,
    String? displayName,
    String? message,
    bool anonymous = false,
  }) async {
    final res = await _client.functions.invoke(
      'pinka-contribute',
      body: {
        'campaign_id': campaignId,
        'amount_cents': amountCents,
        if (displayName != null && displayName.isNotEmpty)
          'display_name': displayName,
        if (message != null && message.isNotEmpty) 'message': message,
        'anonymous': anonymous,
      },
    );
    final data = (res.data as Map).cast<String, dynamic>();
    if (data['error'] != null) {
      throw PinkaFailure(data['error'].toString());
    }
    return PinkaContribution.fromJson(data);
  }

  /// Trenutno stanje doprinosa ('pending' | 'paid' | …). RLS dopušta vlasniku
  /// (anon ili prijavljeni) čitanje vlastitog doprinosa.
  Future<String?> contributionState(String contributionId) async {
    try {
      final row = await _client
          .schema('pinka_finance')
          .from('contributions')
          .select('state')
          .eq('id', contributionId)
          .maybeSingle();
      return row?['state'] as String?;
    } catch (e) {
      log('pinka: contributionState failed — $e');
      return null;
    }
  }

  /// Poll dok doprinos ne postane 'paid' (ili istek pokušaja). Vraća true ako
  /// je potvrđeno. Default: ~3 min (60 × 3 s).
  Future<bool> waitForPaid(
    String contributionId, {
    Duration interval = const Duration(seconds: 3),
    int maxAttempts = 60,
  }) async {
    for (var i = 0; i < maxAttempts; i++) {
      final state = await contributionState(contributionId);
      if (state == 'paid') return true;
      if (state == 'failed' || state == 'expired') return false;
      await Future<void>.delayed(interval);
    }
    return false;
  }
}

class PinkaFailure implements Exception {
  final String code;
  PinkaFailure(this.code);
  @override
  String toString() => 'PinkaFailure($code)';
}
