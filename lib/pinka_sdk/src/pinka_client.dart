library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'models/pinka_campaign.dart';
import 'models/pinka_contribution_intent.dart';
import 'models/pinka_link_preview.dart';
import 'models/pinka_onchain_confirm.dart';
import 'models/pinka_public_contribution.dart';
import 'models/pinka_slot.dart';
import 'models/pinka_sponsor_order.dart';
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

  /// Kreira pending doprinos + payment intent na rail-u; vraća SEPA/EPC podatke.
  ///
  /// Gost (bez sesije) donira bez prijave — klijent tada sam šalje anon ključ
  /// kao bearer, a backend vodi gostujuću granu (limit po IP-u). Anonimna
  /// prijava se NE radi (ugovor v2 §9). Gost s [slotKeys] dobiva
  /// [PinkaLoginRequired]: mjesto traži pravi račun.
  /// Ime/poruka/poveznica se šalju samo kad NIJE anonimno (zid skriva anonimne).
  ///
  /// [linkUrl] je MOST prema zasebnom stupcu `contributions.link_url`: edge
  /// funkcija `pinka-contribute` čita samo imenovane ključeve iz body-ja i
  /// nepoznati ključ tiho ignorira, pa je slanje danas bezopasno i postaje
  /// funkcionalno kad backend doda stupac. Dok to ne bude, poveznica mora
  /// stići i kroz `message` (`pinka-webhook` OG preview vadi isključivo
  /// odande) — to radi panel, ne klijent.
  Future<PinkaContributionIntent> contribute({
    required String campaignId,
    required int amountCents,
    String? displayName,
    String? message,
    String? linkUrl,
    bool anonymous = false,
    List<String>? slotKeys,
  }) async {
    final data = await _invokeContribute({
      'campaign_id': campaignId,
      'amount_cents': amountCents,
      'anonymous': anonymous,
      if (slotKeys != null && slotKeys.isNotEmpty) 'slot_keys': slotKeys,
      if (!anonymous && displayName != null && displayName.trim().isNotEmpty)
        'display_name': displayName.trim(),
      if (!anonymous && message != null && message.trim().isNotEmpty)
        'message': message.trim(),
      if (!anonymous && linkUrl != null && linkUrl.trim().isNotEmpty)
        'link_url': linkUrl.trim(),
    });
    return PinkaContributionIntent.fromJson(data);
  }

  /// Kupnja sponzorskog trenutka — grana `sponsor` iste edge funkcije.
  /// Odgovor je isti kao za donaciju, pa ga prikazuje isti SEPA blok
  /// ([PinkaSepaQr]); `holdExpiresAt` kaže do kada je trenutak zaključan.
  ///
  /// Baca [PinkaSlotTaken] (409 `slot_taken`, netko je bio brži),
  /// [PinkaLoginRequired] (401 — gost ili anonimna sesija; checkout traži
  /// pravi račun) ili [PinkaSponsorRejected] (validacija, `too_many_holds`,
  /// rail nedostupan).
  Future<PinkaContributionIntent> contributeSponsor({
    required String campaignId,
    required List<String> slotKeys,
    required PinkaSponsorOrder order,
  }) async {
    final data = await _invokeContribute({
      'campaign_id': campaignId,
      'slot_keys': slotKeys,
      'sponsor': order.toJson(),
    }, sponsor: true);
    return PinkaContributionIntent.fromJson(data);
  }

  /// `pinka-contribute` uz tipizirane greške.
  ///
  /// `functions.invoke` za svaki ne-2xx BACA `FunctionException` (s tijelom
  /// u `details`) — do 7.10.2026. se 409 ovdje tražio u `res.data`, gdje
  /// nikad ne stigne, pa je sudar oko kvadratića na zidu završavao kao
  /// generička „uplata nije kreirana" umjesto ponovnog odabira mjesta.
  Future<Map<String, dynamic>> _invokeContribute(
    Map<String, dynamic> body, {
    bool sponsor = false,
  }) async {
    Map<String, dynamic> data;
    int? status;
    try {
      final res = await _client.functions.invoke(
        config.contributeFn,
        body: body,
      );
      data = (res.data as Map).cast<String, dynamic>();
      status = res.status;
    } on sb.FunctionException catch (e) {
      var details = e.details;
      // Tijelo bez JSON content-typea stiže kao String — bez parsiranja bi
      // cijeli `{"error":…}` postao kod greške i nijedna grana ne bi pogodila.
      if (details is String) {
        try {
          details = jsonDecode(details);
        } catch (_) {}
      }
      data = details is Map
          ? details.cast<String, dynamic>()
          : {'error': details?.toString() ?? 'http_${e.status}'};
      data['error'] ??= 'http_${e.status}';
      status = e.status;
    }
    final err = data['error']?.toString();
    if (err == null) return data;
    _log('contribute rejected ($status) — $err');
    // Ugovor: uspoređuje se PREFIKS do prve dvotočke; baza zna dodati sufiks.
    final colon = err.indexOf(':');
    final code = colon < 0 ? err : err.substring(0, colon);
    final detail = colon < 0 ? null : err.substring(colon + 1).trim();
    if (code == 'slot_taken') {
      final m = RegExp(r'slot_taken:(\S+)').firstMatch(err);
      throw PinkaSlotTaken(m?.group(1));
    }
    if (code == 'login_required') throw const PinkaLoginRequired();
    if (sponsor) {
      throw PinkaSponsorRejected(
        code,
        detail: (detail == null || detail.isEmpty) ? null : detail,
        status: status,
      );
    }
    throw PinkaFailure(err);
  }

  /// OG preview poveznice za živi pregled kartice u obrascu (prije plaćanja).
  /// Server vadi metapodatke i kešira sliku kod nas — klijent nikad ne
  /// dohvaća tuđi URL. `null` na bilo što (nema previewa, greška, limit).
  Future<PinkaLinkPreview?> linkPreview(String url) async {
    try {
      final res = await _client.functions.invoke(
        config.linkPreviewFn,
        body: {'url': url},
      );
      final data = res.data;
      if (data is! Map) return null;
      final p = PinkaLinkPreview.fromJson(data['preview']);
      return (p != null && p.hasContent) ? p : null;
    } catch (e) {
      _log('linkPreview failed — $e');
      return null;
    }
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
  ///
  /// `maxAttempts: null` polla bez limita — SEPA panel tako čeka prvu uplatu
  /// s novog IBAN-a, koju Monerium zna držati na provjeri satima. Tada je
  /// [isCancelled] obavezan: jedini kraj petlje osim `paid`/`failed`/`expired`.
  Future<bool> waitForPaid(
    String contributionId, {
    Duration interval = const Duration(seconds: 3),
    int? maxAttempts = 100,
    bool Function()? isCancelled,
  }) async {
    for (var i = 0; maxAttempts == null || i < maxAttempts; i++) {
      if (isCancelled?.call() ?? false) return false;
      final state = await contributionStatus(contributionId);
      if (state == 'paid') return true;
      if (state == 'failed' || state == 'expired') return false;
      await Future<void>.delayed(interval);
    }
    return false;
  }

  /// Verificira + kreditira in-app on-chain (EURe) donaciju po tx hashu.
  /// Vraća `mined=false` dok je tx još pending (caller polla).
  ///
  /// [contributionId] se šalje kad je uz uplatu vezano MJESTO: bez njega
  /// backend INSERTA novi doprinos, pa bi hold ostao na starom (pending)
  /// doprinosu i istekao — korisnik bi platio i ne bi dobio kvadratić.
  Future<PinkaOnchainConfirm> confirmOnchain({
    required String campaignId,
    required String txHash,
    String? contributionId,
  }) async {
    final res = await _client.functions.invoke(
      config.onchainConfirmFn,
      body: {
        'campaign_id': campaignId,
        'tx_hash': txHash,
        // Null-aware map entry (Dart 3): izostavlja se kad nema mjesta.
        'contribution_id': ?contributionId,
      },
    );
    final data = (res.data as Map).cast<String, dynamic>();
    if (data['error'] != null) throw PinkaFailure(data['error'].toString());
    return PinkaOnchainConfirm.fromJson(data);
  }
}

/// `401 login_required` — gost (bez sesije) je tražio nešto što traži pravi
/// račun: rezervaciju mjesta (`slot_keys`: kvadratić, sjedalo) ili sponzorski
/// checkout. UI tu nudi prijavu, ne generičku grešku.
class PinkaLoginRequired implements Exception {
  const PinkaLoginRequired();
  @override
  String toString() => 'PinkaLoginRequired';
}

class PinkaFailure implements Exception {
  final String code;
  PinkaFailure(this.code);
  @override
  String toString() => 'PinkaFailure($code)';
}
