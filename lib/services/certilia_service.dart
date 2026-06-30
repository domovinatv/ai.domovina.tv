/// Certilia / NIAS eID login → Supabase sesija.
///
/// flutter_certilia SDK (proxy-only) odradi OIDC flow preko certilia.domovina.ai
/// i vrati CertiliaUser + idToken. idToken šaljemo edge fn-u `certilia` koji ga
/// verificira (JWKS), upserta GoTrue usera (OIB-derived email) i vrati email_otp
/// → verifyOTP postavi Supabase sesiju (isti bridge kao passkey).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_certilia/flutter_certilia.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../main.dart' show log;
import 'locale_service.dart';

/// URL certilia-server proxyja. Override preko --dart-define (deploy.sh embeda).
const String certiliaServerUrl = String.fromEnvironment(
  'CERTILIA_SERVER_URL',
  defaultValue: 'https://certilia.domovina.ai',
);

class CertiliaFailure implements Exception {
  final String message;
  const CertiliaFailure(this.message);
  @override
  String toString() => message;
}

class CertiliaService {
  static final CertiliaService instance = CertiliaService._();
  CertiliaService._();

  /// Runtime tip se razlikuje (web client vs webview wrapper), ali metode i
  /// getteri (authenticate / currentIdToken / logout) su isti.
  dynamic _sdk;

  Future<dynamic> _ensureSdk() async {
    _sdk ??= await CertiliaSDK.initialize(
      serverUrl: certiliaServerUrl,
      scopes: const ['openid', 'profile', 'eid', 'email', 'offline_access'],
      enableLogging: false,
    );
    return _sdk;
  }

  /// Prijava eOsobnom. Otvara Certilia popup (web) / WebView (native), pa
  /// bridgea identitet na Supabase sesiju. Sesija stiže preko onAuthStateChange.
  Future<void> signInWithCertilia(BuildContext context, {String? anonId}) async {
    final sdk = await _ensureSdk();
    if (!context.mounted) return;

    final CertiliaUser user;
    try {
      user = await sdk.authenticate(context);
    } on CertiliaAuthenticationException {
      throw CertiliaFailure(appStrings.serviceCertiliaCancelled);
    } on CertiliaNetworkException catch (e) {
      log('certilia network: ${e.statusCode} ${e.message}');
      throw CertiliaFailure(appStrings.serviceCertiliaServerUnavailable);
    } catch (e) {
      log('certilia authenticate error: $e');
      throw CertiliaFailure(appStrings.serviceCertiliaFailed);
    }

    final idToken = sdk.currentIdToken as String?;
    if (idToken == null || idToken.isEmpty) {
      throw CertiliaFailure(appStrings.serviceCertiliaMissingToken);
    }
    log('CertiliaService: authenticated sub=${user.sub} hasOib=${user.oib != null}');

    final client = sb.Supabase.instance.client;
    final Map<String, dynamic> data;
    try {
      final res = await client.functions.invoke('certilia', body: {
        'idToken': idToken,
        'anonId': anonId,
      });
      data = (res.data as Map).cast<String, dynamic>();
    } on sb.FunctionException catch (e) {
      log('certilia bridge failed: ${e.status} ${e.details}');
      throw CertiliaFailure(_mapBridgeError(e));
    }

    final emailOtp = data['email_otp'] as String?;
    final email = data['email'] as String?;
    if (emailOtp == null || emailOtp.isEmpty || email == null) {
      throw CertiliaFailure(appStrings.serviceBackendNoSignInData);
    }
    try {
      await client.auth.verifyOTP(
        type: sb.OtpType.magiclink,
        email: email,
        token: emailOtp,
      );
      // Uspjeh → onAuthStateChange postavi permanent sesiju + migracija.
    } on sb.AuthException catch (e) {
      log('certilia verifyOTP error: ${e.message}');
      throw CertiliaFailure(appStrings.serviceCertiliaFinishFailed);
    }
  }

  String _mapBridgeError(sb.FunctionException e) {
    final code = e.details is Map ? (e.details as Map)['error'] : null;
    return switch (code) {
      'invalid_token' => appStrings.serviceCertiliaInvalidToken,
      'no_oib_claim' => appStrings.serviceCertiliaNoOib,
      _ => appStrings.serviceCertiliaLinkFailedWithStatus('${e.status}'),
    };
  }
}
