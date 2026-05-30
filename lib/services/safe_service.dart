/// Safe Multisig — per-epizoda wallet. Vlasnik (nakon claim+KYC) se dodaje
/// kao co-signer (2-of-N), pa povlači sredstva. Vidi
/// docs/channel-ownership-and-safe-payout-plan.md §8.
///
/// On-chain dio (Safe Transaction Service, chain, gas) živi u edge fn
/// `safe-owner-add` — ovaj servis definira samo klijentski interface.
/// Eligibility (ownership∧KYC∧svježina) se RE-PROVJERAVA server-side; klijent
/// gate (PayoutEligibility) je samo UX, ne sigurnosna granica.
library;

import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../main.dart' show log;
import '../models/episode_safe.dart';

class SafeFailure implements Exception {
  final String message;
  const SafeFailure(this.message);
  @override
  String toString() => message;
}

class SafeService {
  static final SafeService instance = SafeService._();
  SafeService._();

  /// Pročitaj Safe metapodatke epizode (javno čitljivo). Null ako Safe još
  /// nije kreiran za tu epizodu.
  Future<EpisodeSafe?> fetchSafe(String episodeId) async {
    final client = sb.Supabase.instance.client;
    try {
      final row = await client
          .schema('domovina_ai')
          .from('episode_safes')
          .select()
          .eq('episode_id', episodeId)
          .maybeSingle();
      return row == null ? null : EpisodeSafe.fromJson(row);
    } catch (e) {
      log('fetchSafe failed: $e');
      return null;
    }
  }

  /// Zatraži dodavanje vlasnikove adrese kao Safe co-signera. Edge fn
  /// re-provjeri eligibility (verified claim ∧ KYC ∧ <90d), predloži
  /// addOwnerWithThreshold i izvrši kad threshold zadovoljen.
  Future<String?> requestOwnerAdd({
    required String episodeId,
    required String address,
  }) async {
    final client = sb.Supabase.instance.client;
    try {
      final res = await client.functions.invoke(
        'safe-owner-add',
        body: {'episodeId': episodeId, 'address': address},
      );
      final data = (res.data as Map).cast<String, dynamic>();
      if (data['ok'] != true) {
        throw SafeFailure(_mapReason(data['reason'] as String?));
      }
      return data['safe_tx_hash'] as String?;
    } on sb.FunctionException catch (e) {
      log('safe-owner-add failed: ${e.status} ${e.details}');
      final code = e.details is Map ? (e.details as Map)['error'] : null;
      throw SafeFailure(_mapReason(code as String?));
    }
  }

  /// Audit trail akcija nad Safe-om epizode (RLS: vlasnik povezane epizode).
  Future<List<SafeAction>> fetchActions(String episodeId) async {
    final client = sb.Supabase.instance.client;
    try {
      final rows = await client
          .schema('domovina_ai')
          .from('safe_actions')
          .select()
          .eq('episode_id', episodeId)
          .order('created_at', ascending: false);
      return (rows as List)
          .map((r) => SafeAction.fromJson((r as Map).cast<String, dynamic>()))
          .toList();
    } catch (e) {
      log('fetchActions failed: $e');
      return const [];
    }
  }

  String _mapReason(String? code) => switch (code) {
        'not_eligible' =>
          'Nisi ispunio uvjete za isplatu (vlasništvo, identitet ili svježina).',
        'no_safe' => 'Za ovu epizodu još ne postoji novčanik.',
        'safe_frozen' => 'Novčanik epizode je trenutno zamrznut.',
        'reverify_needed' =>
          'Vlasništvo treba ponovo potvrditi prije isplate (D4).',
        _ => 'Povezivanje s novčanikom nije uspjelo. Pokušaj ponovo.',
      };
}
