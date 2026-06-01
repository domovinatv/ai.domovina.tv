/// Channel ownership claim — vlasnik dokaže da kontrolira YouTube kanal (UC…)
/// preko server-side OAuth verifikacije (channels.list?mine=true).
///
/// Flow (vidi docs/channel-ownership-and-safe-payout-plan.md §6):
///   1. startClaim(ucId)  → edge fn `youtube-claim/start` vrati authUrl
///                          (scope youtube.readonly, state+PKCE vezan na usera)
///   2. korisnik prođe Google consent → redirect/deep-link s ?code&state
///   3. completeClaim(code, state) → edge fn `youtube-claim/callback`
///                          napravi server-side exchange + UC… match + upsert
///
/// PRINCIP A: channel ID s klijenta NIJE dokaz. Jedini izvor istine je
/// `channels.list?mine=true` koji edge fn pozove s tokenom dobivenim
/// server-side exchange-om. Klijent nikad ne vidi access token.
///
/// Edge fn obrazac (functions.invoke + schema('domovina_ai')) prati
/// CertiliaService / PasskeyService / HandoffService.
library;

import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../main.dart' show log;
import '../models/channel_claim.dart';

class ChannelOwnershipFailure implements Exception {
  final String message;
  const ChannelOwnershipFailure(this.message);
  @override
  String toString() => message;
}

class ChannelOwnershipService {
  static final ChannelOwnershipService instance = ChannelOwnershipService._();
  ChannelOwnershipService._();

  /// Pokreni claim — vrati Google consent URL koji UI otvori (web: redirect;
  /// native: in-app browser → `ai.domovina://` deep link callback).
  /// `state` je server-generiran i vezan na ulogiranog usera + ciljani UC….
  Future<String> startClaim(String ucId) async {
    final client = sb.Supabase.instance.client;
    try {
      final res = await client.functions.invoke(
        'youtube-claim/start',
        body: {'channelId': ucId},
      );
      final data = (res.data as Map).cast<String, dynamic>();
      final authUrl = data['authUrl'] as String?;
      if (authUrl == null || authUrl.isEmpty) {
        throw const ChannelOwnershipFailure(
            'Backend nije vratio URL za autorizaciju.');
      }
      return authUrl;
    } on sb.FunctionException catch (e) {
      log('youtube-claim/start failed: ${e.status} ${e.details}');
      throw ChannelOwnershipFailure(_mapError(e));
    }
  }

  /// Dovrši claim nakon OAuth callbacka. Edge fn validira state+PKCE, napravi
  /// code→token exchange, pozove channels.list?mine=true i usporedi UC….
  Future<ChannelClaim> completeClaim({
    required String code,
    required String state,
  }) async {
    final client = sb.Supabase.instance.client;
    try {
      final res = await client.functions.invoke(
        'youtube-claim/callback',
        body: {'code': code, 'state': state},
      );
      final data = (res.data as Map).cast<String, dynamic>();
      if (data['ok'] != true) {
        // Edge fn vraća kod pod ključem 'error' (ne 'reason').
        final reason = data['error'] as String?;
        if (reason == 'channel_mismatch') {
          final owned = (data['ownedChannels'] as List?)
                  ?.map((e) => (e as Map)['title'] as String?)
                  .whereType<String>()
                  .toList() ??
              const <String>[];
          final suffix = owned.isEmpty
              ? ' Ovaj Google račun ne upravlja nijednim YouTube kanalom.'
              : ' Ovim računom upravljaš kanalima: ${owned.join(', ')}.';
          throw ChannelOwnershipFailure(
              'Prijavljeni Google račun nije vlasnik ovog kanala.$suffix'
              ' Prijavi se Google računom koji je VLASNIK kanala (ne urednik).');
        }
        throw ChannelOwnershipFailure(_mapReason(reason));
      }
      return ChannelClaim.fromJson(
          (data['claim'] as Map).cast<String, dynamic>());
    } on sb.FunctionException catch (e) {
      log('youtube-claim/callback failed: ${e.status} ${e.details}');
      throw ChannelOwnershipFailure(_mapError(e));
    }
  }

  /// D4: ponovi verifikaciju ako je claim stariji od 90 dana.
  Future<ChannelClaim> reverify(String claimId) async {
    final client = sb.Supabase.instance.client;
    try {
      final res = await client.functions.invoke(
        'youtube-claim/reverify',
        body: {'claimId': claimId},
      );
      final data = (res.data as Map).cast<String, dynamic>();
      if (data['ok'] != true) {
        throw ChannelOwnershipFailure(_mapReason(data['reason'] as String?));
      }
      return ChannelClaim.fromJson(
          (data['claim'] as Map).cast<String, dynamic>());
    } on sb.FunctionException catch (e) {
      log('youtube-claim/reverify failed: ${e.status} ${e.details}');
      throw ChannelOwnershipFailure(_mapError(e));
    }
  }

  /// Otkvači (odreci se) vlastitog claima — soft-revoke (status='revoked') na
  /// serveru. Oslobađa kanal za novi claim. RLS/ownership provjeren server-side.
  Future<void> revokeClaim(String claimId) async {
    final client = sb.Supabase.instance.client;
    try {
      final res = await client.functions.invoke(
        'youtube-claim/revoke',
        body: {'claimId': claimId},
      );
      final data = (res.data as Map).cast<String, dynamic>();
      if (data['ok'] != true) {
        throw const ChannelOwnershipFailure('Otkvačivanje vlasništva nije uspjelo.');
      }
    } on sb.FunctionException catch (e) {
      log('youtube-claim/revoke failed: ${e.status} ${e.details}');
      throw ChannelOwnershipFailure(_mapError(e));
    }
  }

  /// Pročitaj claim trenutnog usera za dani kanal (null ako nema).
  /// RLS osigurava da user vidi samo svoje claimove.
  Future<ChannelClaim?> myClaimFor(String ucId) async {
    final client = sb.Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null || user.isAnonymous) return null;
    try {
      final row = await client
          .schema('domovina_ai')
          .from('channel_claims')
          .select()
          .eq('youtube_channel_id', ucId)
          .eq('account_id', user.id)
          .maybeSingle();
      return row == null ? null : ChannelClaim.fromJson(row);
    } catch (e) {
      log('myClaimFor failed: $e');
      return null;
    }
  }

  /// Svi claimovi trenutnog usera (za "Moji kanali" ekran).
  Future<List<ChannelClaim>> myClaims() async {
    final client = sb.Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null || user.isAnonymous) return const [];
    try {
      final rows = await client
          .schema('domovina_ai')
          .from('channel_claims')
          .select()
          .eq('account_id', user.id)
          .neq('status', 'revoked')
          .order('created_at', ascending: false);
      return (rows as List)
          .map((r) => ChannelClaim.fromJson((r as Map).cast<String, dynamic>()))
          .toList();
    } catch (e) {
      log('myClaims failed: $e');
      return const [];
    }
  }

  String _mapError(sb.FunctionException e) {
    final code = e.details is Map ? (e.details as Map)['error'] : null;
    return _mapReason(code as String?);
  }

  String _mapReason(String? code) => switch (code) {
        'channel_mismatch' =>
          'Prijavljeni YouTube račun nije vlasnik ovog kanala.',
        'no_channel' => 'Na ovom Google računu nema YouTube kanala.',
        'invalid_state' => 'Sesija autorizacije je istekla. Pokušaj ponovo.',
        'already_claimed' => 'Ovaj kanal je već preuzeo drugi korisnik.',
        'not_signed_in' => 'Za preuzimanje kanala moraš biti prijavljen.',
        _ => 'Provjera vlasništva nije uspjela. Pokušaj ponovo.',
      };
}
