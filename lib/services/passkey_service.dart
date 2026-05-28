/// Passkey / WebAuthn ceremonija (custom, jer GoTrue nema first-class passwordless
/// passkey login).
///
/// Backend: `passkey` Edge Function na api.domovina.ai (4 grane:
/// register/login × start/finish). Server vraća standardne WebAuthn opcije koje
/// `passkeys` paket konzumira direktno preko `RegisterRequestType.fromJson` /
/// `AuthenticateRequestType.fromJson`; response `.toJson()` je već u shape-u koji
/// `@simplewebauthn/server` finish očekuje.
///
/// Nakon uspjeha server minta GoTrue magic `action_link` (isti session-bridge kao
/// [HandoffService]) — otvaranjem linka sesija stigne preko `onAuthStateChange`.
///
/// rpId: NE šaljemo s klijenta. Server ga derivira iz Origin headera (web:
/// domovina.ai / localhost), a za native (nema Origin) padne na default
/// domovina.ai — što je ispravan RP ID preko associated domains / assetlinks.
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:passkeys_platform_interface/passkeys_platform_interface.dart';
import 'package:passkeys_platform_interface/types/types.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:url_launcher/url_launcher.dart';
import '../main.dart' show log;

/// Greška mapirana na hrvatski tekst + zastavica je li login pao zato što na
/// uređaju nema passkeyja (poziv mjesta odlučuje hoće li ponuditi registraciju).
class PasskeyFailure implements Exception {
  final String message;
  final bool noCredential;
  const PasskeyFailure(this.message, {this.noCredential = false});
  @override
  String toString() => message;
}

class PasskeyService {
  static final PasskeyService instance = PasskeyService._();
  PasskeyService._();

  PasskeysPlatform get _platform => PasskeysPlatform.instance;

  /// Registracija novog passkeyja.
  /// [email] je obavezan za new-signup (account identifier + session bridge).
  /// Za već prijavljenog permanent usera backend ignorira [email] i veže passkey
  /// na postojeći račun. Otvara `action_link` na kraju (sesija stiže async).
  Future<void> registerPasskey({required String email}) async {
    log('PasskeyService.registerPasskey email=$email');

    final options = await _invokeStart('passkey/register/start', {'email': email});
    final challenge = options['challenge'] as String;

    final RegisterResponseType regResponse;
    try {
      await _platform.cancelCurrentAuthenticatorOperation();
      regResponse = await _platform.register(
        RegisterRequestType.fromJson(options),
      );
    } on PlatformException catch (e) {
      log('passkey register PlatformException: ${e.code} ${e.message}');
      throw PasskeyFailure(switch (e.code) {
        'cancelled' => 'Registracija passkeyja je otkazana.',
        'exclude-credentials-match' =>
          'Na ovom uređaju već postoji passkey za ovaj račun.',
        'domain-not-associated' =>
          'Domena nije povezana za passkey (provjeri assetlinks/AASA).',
        'deviceNotSupported' || 'android-passkey-unsupported' =>
          'Ovaj uređaj ne podržava passkey.',
        _ => 'Passkey nije moguće kreirati na ovom uređaju.',
      });
    }

    await _finish('passkey/register/finish', {
      'challenge': challenge,
      'credential': regResponse.toJson(),
      'deviceName': _deviceName(),
    });
  }

  /// Prijava postojećim passkeyom (discoverable credential — OS prikaže picker).
  /// Baca [PasskeyFailure] s `noCredential=true` ako na uređaju nema passkeyja,
  /// pa pozivatelj može ponuditi registraciju.
  Future<void> loginWithPasskey() async {
    log('PasskeyService.loginWithPasskey');

    final options = await _invokeStart('passkey/login/start', {});
    final challenge = options['challenge'] as String;

    final AuthenticateResponseType authResponse;
    try {
      await _platform.cancelCurrentAuthenticatorOperation();
      authResponse = await _platform.authenticate(
        AuthenticateRequestType.fromJson(options),
      );
    } on PlatformException catch (e) {
      log('passkey login PlatformException: ${e.code} ${e.message}');
      if (e.code == 'no-credentials-available' ||
          e.code == 'android-no-credential') {
        throw const PasskeyFailure('Nema passkeyja na ovom uređaju.',
            noCredential: true);
      }
      throw PasskeyFailure(switch (e.code) {
        'cancelled' => 'Prijava passkeyom je otkazana.',
        'domain-not-associated' =>
          'Domena nije povezana za passkey (provjeri assetlinks/AASA).',
        _ => 'Prijava passkeyom nije uspjela.',
      });
    }

    await _finish('passkey/login/finish', {
      'challenge': challenge,
      'credential': authResponse.toJson(),
    });
  }

  // -- helpers --

  Future<Map<String, dynamic>> _invokeStart(
    String fn,
    Map<String, dynamic> body,
  ) async {
    final client = sb.Supabase.instance.client;
    try {
      final res = await client.functions.invoke(fn, body: body);
      final data = (res.data as Map).cast<String, dynamic>();
      final options = (data['options'] as Map).cast<String, dynamic>();
      return options;
    } on sb.FunctionException catch (e) {
      throw PasskeyFailure(_mapStartError(e));
    }
  }

  Future<void> _finish(String fn, Map<String, dynamic> body) async {
    final client = sb.Supabase.instance.client;
    try {
      final res = await client.functions.invoke(fn, body: body);
      final data = (res.data as Map).cast<String, dynamic>();
      final actionLink = data['action_link'] as String?;
      if (actionLink == null || actionLink.isEmpty) {
        throw const PasskeyFailure('Backend nije vratio sign-in link.');
      }
      await _openActionLink(actionLink);
    } on sb.FunctionException catch (e) {
      throw PasskeyFailure(_mapFinishError(e));
    }
  }

  /// Otvori magic `action_link` — isti pattern kao HandoffService.
  /// Web: ista kartica (full navigacija) da supabase_flutter detektira sesiju iz
  /// URL-a po reloadu. Native: vanjski browser → deep link `ai.domovina://`.
  Future<void> _openActionLink(String actionLink) async {
    final uri = Uri.parse(actionLink);
    if (kIsWeb) {
      await launchUrl(uri, webOnlyWindowName: '_self');
    } else {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _mapStartError(sb.FunctionException e) {
    final code = e.details is Map ? (e.details as Map)['error'] : null;
    return switch (code) {
      'email_required' => 'Unesi e-mail za kreiranje računa s passkeyom.',
      _ => 'Priprema passkeyja nije uspjela (${e.status}).',
    };
  }

  String _mapFinishError(sb.FunctionException e) {
    final code = e.details is Map ? (e.details as Map)['error'] : null;
    return switch (code) {
      'verification_failed' => 'Passkey nije verificiran. Pokušaj ponovo.',
      'unknown_credential' =>
        'Ovaj passkey nije prepoznat — možda je vezan uz drugi račun.',
      'user_create_failed' =>
        'Račun s tim e-mailom već postoji — prijavi se passkeyom ili Googleom.',
      'challenge_not_found_or_expired' =>
        'Sesija je istekla. Pokušaj ponovo.',
      _ => 'Dovršetak passkey prijave nije uspio (${e.status}).',
    };
  }

  String _deviceName() {
    if (kIsWeb) return 'Web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'iPhone/iPad',
      TargetPlatform.android => 'Android',
      TargetPlatform.macOS => 'Mac',
      _ => 'Uređaj',
    };
  }
}
