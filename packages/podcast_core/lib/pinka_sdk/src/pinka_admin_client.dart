library;

import 'dart:developer' as dev;

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'models/pinka_owner_campaign.dart';
import 'models/pinka_payout.dart';
import 'pinka_client.dart' show PinkaFailure;
import 'pinka_config.dart';

/// Admin površina Pinka SDK-a — upravljanje kampanjama za **verificiranog
/// vlasnika kanala** (Faza A: upravljanje postojećim kampanjama; bez kreiranja).
///
/// Odvojeno od read/contribute [PinkaClient]a da read SDK ostane čist. Autorizacija
/// je server-side: RLS dopušta update vlasniku kanala (campaigns.youtube_channel_id
/// match na verificirani `channel_claims`), a write na epizode ide kroz SECURITY
/// DEFINER RPC-eve. `account_id` nikad ne prelazi na klijent.
class PinkaAdminClient {
  PinkaAdminClient({sb.SupabaseClient? client, this.config = PinkaConfig.defaults})
      : _injected = client;

  final sb.SupabaseClient? _injected;
  final PinkaConfig config;

  static final PinkaAdminClient instance = PinkaAdminClient();

  sb.SupabaseClient get _client => _injected ?? sb.Supabase.instance.client;

  void _log(String m) => dev.log(m, name: 'pinka.admin');

  static const String _ownerSelect =
      'id, slug, type, title, description, goal_cents, min_contribution_cents, '
      'currency, cover_image_url, state, visibility, destination_address, '
      'youtube_channel_id, metadata, '
      'campaign_stats(total_raised_cents, contribution_count, contributor_count), '
      'campaign_subjects(subject_type, subject_ref), '
      'yield_positions(principal_cents, accrued_yield_cents, atoken_address, last_synced_at, status)';

  /// Sve kampanje ankerirane na dani kanal (UC… id). RLS vraća i `draft`/`private`
  /// kad je pozivatelj verificirani vlasnik tog kanala.
  Future<List<PinkaOwnerCampaign>> listCampaignsForChannel(
    String youtubeChannelId,
  ) async {
    try {
      final rows = await _client
          .schema(config.schema)
          .from('campaigns')
          .select(_ownerSelect)
          .eq('youtube_channel_id', youtubeChannelId)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false);
      return (rows as List)
          .map((r) =>
              PinkaOwnerCampaign.fromRow((r as Map).cast<String, dynamic>()))
          .toList();
    } catch (e) {
      _log('listCampaignsForChannel failed — $e');
      return const [];
    }
  }

  /// Jedna kampanja po id-u (owner view).
  Future<PinkaOwnerCampaign?> getCampaign(String id) async {
    try {
      final row = await _client
          .schema(config.schema)
          .from('campaigns')
          .select(_ownerSelect)
          .eq('id', id)
          .maybeSingle();
      if (row == null) return null;
      return PinkaOwnerCampaign.fromRow(row.cast<String, dynamic>());
    } catch (e) {
      _log('getCampaign failed — $e');
      return null;
    }
  }

  /// Uredi tekst/cilj kampanje (raw UPDATE; RLS dopušta vlasniku). NIKAD ne šalje
  /// `slug` (immutable trigger u bazi).
  Future<void> updateCampaign(
    String id, {
    String? title,
    String? description,
    int? goalCents,
    int? minContributionCents,
    String? coverImageUrl,
  }) async {
    final patch = <String, dynamic>{
      'title': ?title,
      'description': ?description,
      'goal_cents': ?goalCents,
      'min_contribution_cents': ?minContributionCents,
      'cover_image_url': ?coverImageUrl,
    };
    if (patch.isEmpty) return;
    await _update(id, patch);
  }

  /// Promijeni stanje kampanje (draft → active → closed …).
  Future<void> setState(String id, String state) => _update(id, {'state': state});

  /// Promijeni vidljivost (private | unlisted | public).
  Future<void> setVisibility(String id, String visibility) =>
      _update(id, {'visibility': visibility});

  Future<void> _update(String id, Map<String, dynamic> patch) async {
    try {
      await _client
          .schema(config.schema)
          .from('campaigns')
          .update(patch)
          .eq('id', id);
    } catch (e) {
      _log('_update($id) failed — $e');
      rethrow;
    }
  }

  /// Zamijeni cijeli set epizoda kampanje (`campaign_subjects`,
  /// subject_type='podcast_episode'). Baca [PinkaFailure] s kodom
  /// `episode_taken` ako je neka epizoda već u drugoj kampanji.
  Future<void> setCampaignEpisodes(
    String campaignId,
    List<String> episodeYoutubeIds,
  ) async {
    await _rpc(config.setCampaignEpisodesRpc, {
      'p_campaign_id': campaignId,
      'p_episode_ids': episodeYoutubeIds,
    });
  }

  Future<void> attachEpisode(String campaignId, String youtubeId) async {
    await _rpc(config.attachSubjectRpc, {
      'p_campaign_id': campaignId,
      'p_subject_type': 'podcast_episode',
      'p_subject_ref': youtubeId,
    });
  }

  Future<void> detachEpisode(String campaignId, String youtubeId) async {
    await _rpc(config.detachSubjectRpc, {
      'p_campaign_id': campaignId,
      'p_subject_type': 'podcast_episode',
      'p_subject_ref': youtubeId,
    });
  }

  // ── Isplate (payout request) ──────────────────────────────────────────────

  /// Povijest isplata kampanje (RLS: vlasnik kampanje/kanala).
  Future<List<PinkaPayout>> listPayouts(String campaignId) async {
    try {
      final rows = await _client
          .schema(config.schema)
          .from('payouts')
          .select('id, amount_cents, destination, state, tx_hash, created_at')
          .eq('campaign_id', campaignId)
          .order('created_at', ascending: false);
      return (rows as List)
          .map((r) => PinkaPayout.fromJson((r as Map).cast<String, dynamic>()))
          .toList();
    } catch (e) {
      _log('listPayouts failed — $e');
      return const [];
    }
  }

  /// Zatraži isplatu (vlasnik ∧ KYC). [destination] = 0x adresa ili IBAN.
  /// Vraća payout id. Baca [PinkaFailure] s kodom: `kyc_required`,
  /// `invalid_destination`, `invalid_amount`, `amount_exceeds_available`,
  /// `not_authorized`.
  Future<String> requestPayout({
    required String campaignId,
    required String destination,
    required int amountCents,
  }) async {
    try {
      final data = await _client.schema(config.schema).rpc(
        config.requestPayoutRpc,
        params: {
          'p_campaign_id': campaignId,
          'p_destination': destination,
          'p_amount_cents': amountCents,
        },
      );
      return data?.toString() ?? '';
    } on sb.PostgrestException catch (e) {
      const codes = [
        'kyc_required',
        'invalid_destination',
        'invalid_amount',
        'amount_exceeds_available',
        'not_authorized',
      ];
      for (final c in codes) {
        if (e.message.contains(c)) throw PinkaFailure(c);
      }
      _log('requestPayout failed — ${e.message}');
      rethrow;
    }
  }

  // ── Yield (Aave oplodnja) ─────────────────────────────────────────────────

  /// Uključi/isključi oplodnju sredstava kampanje (per-campaign opt-in).
  Future<void> setCampaignYield(String campaignId, bool enabled) async {
    await _rpc(config.setCampaignYieldRpc, {
      'p_campaign_id': campaignId,
      'p_enabled': enabled,
    });
  }

  Future<void> _rpc(String fn, Map<String, dynamic> params) async {
    try {
      await _client.schema(config.schema).rpc(fn, params: params);
    } on sb.PostgrestException catch (e) {
      // RPC RAISE poruke ('episode_taken', 'not_authorized', …) stižu u message.
      final msg = e.message;
      if (msg.contains('episode_taken')) throw PinkaFailure('episode_taken');
      if (msg.contains('not_authorized')) throw PinkaFailure('not_authorized');
      _log('$fn failed — $msg');
      rethrow;
    }
  }
}
