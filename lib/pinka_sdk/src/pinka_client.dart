library;

import 'dart:async';
import 'dart:developer' as dev;

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'models/pinka_campaign.dart';
import 'models/pinka_contribution_intent.dart';
import 'models/pinka_onchain_confirm.dart';
import 'models/pinka_public_contribution.dart';
import 'models/pinka_slot.dart';
import 'models/pinka_yield_position.dart';
import 'pinka_config.dart';

/// Pinka backend klijent — kampanje, doprinosi (SEPA + on-chain), zid podrške.
///
/// Backend = domovina-api Supabase (schema `pinka_finance`), dijeljen s
/// pinka.io. Rail = pay.domovina.ai (MPT intenti). Sve je RLS-gated; anon
/// sesija je dovoljna za čitanje javnih kampanja i kreiranje doprinosa.
class PinkaClient {
  PinkaClient({sb.SupabaseClient? client, this.config = PinkaConfig.defaults})
      : _injected = client;

  final sb.SupabaseClient? _injected;
  final PinkaConfig config;

  /// Dijeljeni singleton (host već inicijalizira Supabase u `main.dart`).
  static final PinkaClient instance = PinkaClient();

  sb.SupabaseClient get _client => _injected ?? sb.Supabase.instance.client;

  void _log(String m) => dev.log(m, name: 'pinka');

  /// Aktivna javna kampanja za dani subjekt. [subjectRefs] može sadržavati više
  /// kandidata (npr. kanal: [UC id, interni channel id]) — vraća prvu koja
  /// matcha. Razrješava i legacy `subject_ref` i `campaign_subjects` join
  /// (multi-episode) preko `active_campaign_for_subject` RPC-a. `null` kad
  /// subjekt nema kampanju (UI se tada sakrije).
  Future<PinkaCampaign?> campaignForSubject({
    required String subjectType,
    required List<String> subjectRefs,
  }) async {
    final refs = subjectRefs.where((r) => r.trim().isNotEmpty).toSet().toList();
    if (refs.isEmpty) return null;
    try {
      final data = await _client.schema(config.schema).rpc(
        config.activeCampaignForSubjectRpc,
        params: {'p_subject_type': subjectType, 'p_subject_refs': refs},
      );
      final row = data is List ? (data.isNotEmpty ? data.first : null) : data;
      if (row is! Map) return null;
      return PinkaCampaign.fromRow(row.cast<String, dynamic>());
    } catch (e) {
      _log('campaignForSubject($subjectType) failed — $e');
      return null;
    }
  }

  /// Doprinosi za "Zid podrške" — javni view (samo plaćeni, ne-anonimni).
  /// Najnoviji prvi (live wall s arrive animacijom).
  Future<List<PinkaPublicContribution>> wall(
    String campaignId, {
    int limit = 50,
  }) async {
    try {
      final rows = await _client
          .schema(config.schema)
          .from('public_contributions')
          .select(
            'id, display_name, message, link_preview, amount_cents, '
            'currency, created_at',
          )
          .eq('campaign_id', campaignId)
          .order('created_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .map((r) => PinkaPublicContribution.fromJson(
                (r as Map).cast<String, dynamic>(),
              ))
          .toList();
    } catch (e) {
      _log('wall($campaignId) failed — $e');
      return const [];
    }
  }

  /// Mapa mjesta kampanje (grid kvadratića ili raspored sjedala) + cjenovne
  /// zone. `null` ako kampanja nema mapu — tada nema ni grida za crtati.
  ///
  /// Grid mod se pali PODACIMA, ne feature flagom: nema mape → legacy prikaz,
  /// ima mape → server je izvor istine. Zato nema flaga koji bi trebalo držati
  /// usklađenim s backendom.
  Future<PinkaSlotMap?> slotMap(String campaignId) async {
    try {
      final maps = await _client
          .schema(config.schema)
          .from('slot_maps')
          .select('id, kind, width, height')
          .eq('campaign_id', campaignId)
          .limit(1);
      final list = maps as List;
      if (list.isEmpty) return null;
      final mapRow = (list.first as Map).cast<String, dynamic>();

      final zoneRows = await _client
          .schema(config.schema)
          .from('slot_zones')
          .select('zone_index, price_cents, label_key')
          .eq('map_id', mapRow['id'])
          .order('zone_index', ascending: true);
      final zones = (zoneRows as List)
          .map((r) => PinkaSlotZone.fromJson((r as Map).cast<String, dynamic>()))
          .toList();

      return PinkaSlotMap.fromJson(mapRow, zones);
    } catch (e) {
      _log('slotMap($campaignId) failed — $e');
      return null;
    }
  }

  /// Sva mjesta kampanje iz javnog viewa. View već mapira istekli hold u
  /// `free`, pa klijent ne mora uspoređivati vrijeme ni čistiti zombije.
  ///
  /// Limit je namjerno visok: grid je 120×120 = 14.400 redova i dohvaća se
  /// odjednom, jer se crta kao JEDAN CustomPainter pass.
  Future<List<PinkaSlot>> slots(String campaignId, {int limit = 20000}) async {
    try {
      final rows = await _client
          .schema(config.schema)
          .from('public_slots')
          .select(
            'slot_key, label, pos_x, pos_y, token_id, zone_index, '
            'price_cents, state, display_name, message, verified, '
            'minted_at, onchain_token_address',
          )
          .eq('campaign_id', campaignId)
          // Slobodna mjesta su većina i nose nula informacije — crtaju se kao
          // prazna ćelija. Dohvaćamo samo ona koja nešto znače.
          .neq('state', 'free')
          .limit(limit);
      return (rows as List)
          .map((r) => PinkaSlot.fromJson((r as Map).cast<String, dynamic>()))
          .toList();
    } catch (e) {
      _log('slots($campaignId) failed — $e');
      return const [];
    }
  }

  /// Yield (Aave) pozicija kampanje — javno čitljiva za javne kampanje.
  /// `null` ako kampanja nema poziciju (yield isključen / još ne supplyano).
  Future<PinkaYieldPosition?> yieldPosition(String campaignId) async {
    try {
      final row = await _client
          .schema(config.schema)
          .from('yield_positions')
          .select(
            'campaign_id, protocol, principal_cents, accrued_yield_cents, '
            'last_balance_cents, atoken_address, status, last_synced_at',
          )
          .eq('campaign_id', campaignId)
          .maybeSingle();
      if (row == null) return null;
      return PinkaYieldPosition.fromJson(row.cast<String, dynamic>());
    } catch (e) {
      _log('yieldPosition failed — $e');
      return null;
    }
  }

  /// Osiguraj barem anonimnu sesiju prije poziva edge fn-a.
  Future<void> ensureSession() async {
    final auth = _client.auth;
    if (auth.currentSession != null) return;
    try {
      await auth.signInAnonymously();
    } catch (e) {
      _log('anon sign-in failed — $e');
    }
  }

  /// Kreira pending doprinos + payment intent na rail-u; vraća SEPA/EPC podatke.
  /// Ime/poruka se šalju samo kad NIJE anonimno (zid skriva anonimne).
  Future<PinkaContributionIntent> contribute({
    required String campaignId,
    required int amountCents,
    String? displayName,
    String? message,
    bool anonymous = false,
    List<String>? slotKeys,
  }) async {
    await ensureSession();
    final res = await _client.functions.invoke(
      config.contributeFn,
      body: {
        'campaign_id': campaignId,
        'amount_cents': amountCents,
        'anonymous': anonymous,
        if (slotKeys != null && slotKeys.isNotEmpty) 'slot_keys': slotKeys,
        if (!anonymous && displayName != null && displayName.trim().isNotEmpty)
          'display_name': displayName.trim(),
        if (!anonymous && message != null && message.trim().isNotEmpty)
          'message': message.trim(),
      },
    );
    final data = (res.data as Map).cast<String, dynamic>();
    if (data['error'] != null) {
      final err = data['error'].toString();
      // Backend vraća 409 za sudar oko mjesta. Tipiziramo ga da panel može
      // osvježiti mapu i tražiti novi odabir umjesto da prikaže sirovu poruku.
      if (err.contains('slot_taken')) {
        final m = RegExp(r'slot_taken:(\S+)').firstMatch(err);
        throw PinkaSlotTaken(m?.group(1));
      }
      throw PinkaFailure(err);
    }
    return PinkaContributionIntent.fromJson(data);
  }

  /// Stanje doprinosa preko guest-pollable SECURITY DEFINER RPC-a (anon ne može
  /// čitati `contributions` red kroz RLS). Vraća 'pending' | 'paid' | … | null.
  Future<String?> contributionStatus(String contributionId) async {
    try {
      final data = await _client.schema(config.schema).rpc(
        config.contributionStatusRpc,
        params: {'p_contribution_id': contributionId},
      );
      final row = data is List ? (data.isNotEmpty ? data.first : null) : data;
      if (row is Map) return row['state'] as String?;
      return null;
    } catch (e) {
      _log('contributionStatus failed — $e');
      return null;
    }
  }

  /// Poll dok doprinos ne postane 'paid' (ili istek). Default ~5 min.
  Future<bool> waitForPaid(
    String contributionId, {
    Duration interval = const Duration(seconds: 3),
    int maxAttempts = 100,
  }) async {
    for (var i = 0; i < maxAttempts; i++) {
      final state = await contributionStatus(contributionId);
      if (state == 'paid') return true;
      if (state == 'failed' || state == 'expired') return false;
      await Future<void>.delayed(interval);
    }
    return false;
  }

  /// Verificira + kreditira in-app on-chain (EURe) donaciju po tx hashu.
  /// Vraća `mined=false` dok je tx još pending (caller polla).
  Future<PinkaOnchainConfirm> confirmOnchain({
    required String campaignId,
    required String txHash,
  }) async {
    final res = await _client.functions.invoke(
      config.onchainConfirmFn,
      body: {'campaign_id': campaignId, 'tx_hash': txHash},
    );
    final data = (res.data as Map).cast<String, dynamic>();
    if (data['error'] != null) throw PinkaFailure(data['error'].toString());
    return PinkaOnchainConfirm.fromJson(data);
  }
}

class PinkaFailure implements Exception {
  final String code;
  PinkaFailure(this.code);
  @override
  String toString() => 'PinkaFailure($code)';
}
