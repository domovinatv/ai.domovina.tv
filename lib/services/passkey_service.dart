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
import 'locale_service.dart';

/// Greška mapirana na hrvatski tekst + zastavica je li login pao zato što na
/// uređaju nema passkeyja (poziv mjesta odlučuje hoće li ponuditi registraciju).
/// [unsupported] = backend još nema endpoint (graceful degradacija u UI-ju).
class PasskeyFailure implements Exception {
  final String message;
  final bool noCredential;
  final bool unsupported;
  const PasskeyFailure(
    this.message, {
    this.noCredential = false,
    this.unsupported = false,
  });
  @override
  String toString() => message;
}

/// Jedan registrirani passkey (red iz public.user_passkeys) — za Moj račun.
class PasskeyInfo {
  final String id;
  final String? deviceName;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;

  const PasskeyInfo({
    required this.id,
    this.deviceName,
    this.createdAt,
    this.lastUsedAt,
  });

  factory PasskeyInfo.fromJson(Map<String, dynamic> json) => PasskeyInfo(
        id: json['id'] as String,
        deviceName: json['device_name'] as String?,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
        lastUsedAt: DateTime.tryParse(json['last_used_at'] as String? ?? ''),
      );
}

class PasskeyService {
  static final PasskeyService instance = PasskeyService._();
  PasskeyService._();

  PasskeysPlatform get _platform => PasskeysPlatform.instance;

  /// Single-flight guard: samo jedna WebAuthn ceremonija u isto vrijeme.
  /// Bez ovoga drugi tap na tile (dok traje async register/start) pokrene
  /// drugi `navigator.credentials.create()` → browser baci
  /// `OperationError: A request is already pending` (pogoršano password
  /// manager-ima poput LastPass-a koji presreću ceremoniju).
  bool _ceremonyInProgress = false;

  /// Registracija novog passkeyja.
  /// [email] je obavezan za new-signup (account identifier + session bridge).
  /// Za već prijavljenog permanent usera backend ignorira [email] i veže passkey
  /// na postojeći račun. Otvara `action_link` na kraju (sesija stiže async).
  Future<void> registerPasskey({required String email}) async {
    log('PasskeyService.registerPasskey email=$email');
    if (_ceremonyInProgress) {
      throw PasskeyFailure(appStrings.servicePasskeyRequestInProgress);
    }
    _ceremonyInProgress = true;
    try {
      final options =
          await _invokeStart('passkey/register/start', {'email': email});
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
          'cancelled' || 'NotAllowedError' =>
            appStrings.servicePasskeyRegisterCancelled,
          'OperationError' =>
            appStrings.servicePasskeyPasswordManagerBlockRegister,
          'exclude-credentials-match' || 'InvalidStateError' =>
            appStrings.servicePasskeyAlreadyExists,
          'domain-not-associated' =>
            appStrings.servicePasskeyDomainNotAssociated,
          'deviceNotSupported' || 'android-passkey-unsupported' =>
            appStrings.servicePasskeyDeviceUnsupported,
          _ => appStrings.servicePasskeyCreateFailed,
        });
      }

      await _finish('passkey/register/finish', {
        'challenge': challenge,
        'credential': regResponse.toJson(),
        'deviceName': _deviceName(),
      });
    } finally {
      _ceremonyInProgress = false;
    }
  }

  /// Prijava postojećim passkeyom (discoverable credential — OS prikaže picker).
  /// Baca [PasskeyFailure] s `noCredential=true` ako na uređaju nema passkeyja,
  /// pa pozivatelj može ponuditi registraciju.
  Future<void> loginWithPasskey() async {
    log('PasskeyService.loginWithPasskey');
    if (_ceremonyInProgress) {
      throw PasskeyFailure(appStrings.servicePasskeyRequestInProgress);
    }
    _ceremonyInProgress = true;
    try {
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
          throw PasskeyFailure(appStrings.servicePasskeyNoneOnDevice,
              noCredential: true);
        }
        throw PasskeyFailure(switch (e.code) {
          'cancelled' || 'NotAllowedError' =>
            appStrings.servicePasskeyLoginCancelled,
          'OperationError' =>
            appStrings.servicePasskeyPasswordManagerBlockLogin,
          'domain-not-associated' =>
            appStrings.servicePasskeyDomainNotAssociated,
          _ => appStrings.servicePasskeyLoginFailed,
        });
      }

      await _finish('passkey/login/finish', {
        'challenge': challenge,
        'credential': authResponse.toJson(),
      });
    } finally {
      _ceremonyInProgress = false;
    }
  }

  /// Lista passkeyja trenutnog (signed-in) usera — za Moj račun ekran.
  /// Backend: `passkey/list` grana (JWT iz sesije; spec u
  /// docs/backend-prompts/10-account-management.md). Dok grana ne postoji,
  /// edge fn vraća 404 → [PasskeyFailure.unsupported].
  Future<List<PasskeyInfo>> listPasskeys() async {
    final client = sb.Supabase.instance.client;
    try {
      final res = await client.functions.invoke('passkey/list', body: {});
      final data = (res.data as Map).cast<String, dynamic>();
      return (data['passkeys'] as List? ?? const [])
          .map((row) =>
              PasskeyInfo.fromJson((row as Map).cast<String, dynamic>()))
          .toList();
    } on sb.FunctionException catch (e) {
      log('listPasskeys FunctionException: ${e.status}');
      if (e.status == 404) {
        throw PasskeyFailure(
            appStrings.servicePasskeyManageUnavailable,
            unsupported: true);
      }
      throw PasskeyFailure(
          appStrings.servicePasskeyFetchFailedWithStatus('${e.status}'));
    }
  }

  /// Ukloni passkey [id] s računa. Backend: `passkey/delete` grana.
  Future<void> deletePasskey(String id) async {
    final client = sb.Supabase.instance.client;
    try {
      await client.functions.invoke('passkey/delete', body: {'id': id});
    } on sb.FunctionException catch (e) {
      log('deletePasskey FunctionException: ${e.status}');
      if (e.status == 404) {
        throw PasskeyFailure(
            appStrings.servicePasskeyRemoveUnavailable,
            unsupported: true);
      }
      throw PasskeyFailure(
          appStrings.servicePasskeyRemoveFailedWithStatus('${e.status}'));
    }
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
    final Map<String, dynamic> data;
    try {
      final res = await client.functions.invoke(fn, body: body);
      data = (res.data as Map).cast<String, dynamic>();
    } on sb.FunctionException catch (e) {
      throw PasskeyFailure(_mapFinishError(e));
    }

    // PRIMARNO: verificiraj email_otp direktno (session u responseu, bez
    // redirecta). Redirect/action_link na webu ne radi jer je link server-
    // generiran pa PKCE klijent ne uhvati sesiju iz URL-a.
    final emailOtp = data['email_otp'] as String?;
    final email = data['email'] as String?;
    if (emailOtp != null && emailOtp.isNotEmpty && email != null) {
      try {
        await client.auth.verifyOTP(
          type: sb.OtpType.magiclink,
          email: email,
          token: emailOtp,
        );
        return; // sesija postavljena → onAuthStateChange odradi ostalo
      } on sb.AuthException catch (e) {
        log('passkey verifyOTP error: ${e.message}');
        throw PasskeyFailure(appStrings.servicePasskeyFinishFailed);
      }
    }

    // Fallback: otvori action_link (native deep link / stariji backend).
    final actionLink = data['action_link'] as String?;
    if (actionLink == null || actionLink.isEmpty) {
      throw PasskeyFailure(appStrings.serviceBackendNoSignInData);
    }
    await _openActionLink(actionLink);
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
      'email_required' => appStrings.servicePasskeyEmailRequired,
      _ => appStrings.servicePasskeyPrepareFailedWithStatus('${e.status}'),
    };
  }

  String _mapFinishError(sb.FunctionException e) {
    final code = e.details is Map ? (e.details as Map)['error'] : null;
    return switch (code) {
      'verification_failed' => appStrings.servicePasskeyNotVerified,
      'unknown_credential' => appStrings.servicePasskeyUnknownCredential,
      'user_create_failed' => appStrings.servicePasskeyAccountExists,
      'challenge_not_found_or_expired' => appStrings.serviceSessionExpired,
      _ => appStrings.servicePasskeyFinishFailedWithStatus('${e.status}'),
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
