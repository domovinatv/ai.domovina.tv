/// Cross-device handoff.
///
/// [createCode] (izvorni uređaj, prijavljen) poziva `domovina_ai.create_handoff_token`
/// RPC koji vraća `{code, expires_at}` (TTL 5 min) — prethodne nepotrošene
/// kodove istog usera RPC automatski briše.
///
/// [consumeCode] (uređaj koji prima) poziva `handoff-consume` Edge Function
/// (`/functions/v1/handoff-consume`). Funkcija interno radi consume preko
/// service_role-a i vrati magic `action_link`; otvaranjem tog linka Supabase
/// postavi sesiju izvornog usera na ovom uređaju.
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:url_launcher/url_launcher.dart';
import '../main.dart' show log;
import 'auth_service.dart';

/// Rezultat generiranja koda na izvornom uređaju.
class HandoffCode {
  final String code;
  final DateTime expiresAt;

  const HandoffCode({required this.code, required this.expiresAt});

  Duration get remaining => expiresAt.difference(DateTime.now());
  bool get isExpired => remaining.isNegative;
}

class HandoffService {
  static final HandoffService instance = HandoffService._();
  HandoffService._();

  /// Generira novi handoff kod preko RPC. Vraća 6-znamenkasti kod + istek.
  Future<HandoffCode> createCode() async {
    final user = AuthService.instance.currentUser;
    if (user == null) throw StateError('Nema usera za handoff');

    try {
      final client = sb.Supabase.instance.client;
      final result =
          await client.schema('domovina_ai').rpc('create_handoff_token');
      final map = (result as Map).cast<String, dynamic>();
      return HandoffCode(
        code: map['code'] as String,
        expiresAt: DateTime.parse(map['expires_at'] as String),
      );
    } on sb.PostgrestException catch (e) {
      log('create_handoff_token RPC failed: ${e.message}');
      throw StateError('Backend ne odgovara: ${e.message}');
    }
  }

  /// Konzumira kod na uređaju koji prima. Poziva `handoff-consume` Edge
  /// Function (supabase_flutter automatski šalje trenutni access token kao
  /// pozivatelja), dobije `action_link` i otvori ga da Supabase završi sign-in.
  /// Vraća `user_id` izvornog usera. Sama sesija stiže asinkrono preko
  /// `onAuthStateChange` (vidi AuthService.init).
  Future<String> consumeCode(String code) async {
    final clean = code.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length != 6) {
      throw const FormatException('Kod mora imati točno 6 znamenki');
    }

    final client = sb.Supabase.instance.client;
    try {
      final res = await client.functions.invoke(
        'handoff-consume',
        body: {'code': clean, 'device': _detectDevice()},
      );
      final data = (res.data as Map).cast<String, dynamic>();
      final actionLink = data['action_link'] as String?;
      if (actionLink == null || actionLink.isEmpty) {
        throw StateError('Backend nije vratio sign-in link');
      }
      await _openActionLink(actionLink);
      return data['user_id'] as String? ?? '';
    } on sb.FunctionException catch (e) {
      log('handoff-consume failed: status=${e.status} details=${e.details}');
      throw StateError(_mapError(e));
    }
  }

  /// Otvori magic `action_link`. Web: ista kartica (full navigacija) da
  /// supabase_flutter detektira sesiju iz URL-a po reloadu. Mobile/TV: vanjski
  /// browser → magic link → redirect na `ai.domovina://auth/callback`.
  Future<void> _openActionLink(String actionLink) async {
    final uri = Uri.parse(actionLink);
    if (kIsWeb) {
      await launchUrl(uri, webOnlyWindowName: '_self');
    } else {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _mapError(sb.FunctionException e) {
    final details = e.details;
    final code = details is Map ? details['error'] as String? : null;
    return switch (code) {
      'not_authenticated' =>
        'Ovaj uređaj nema aktivnu sesiju — osvježi stranicu i pokušaj ponovo',
      'invalid_code_format' => 'Kod mora imati 6 znamenki',
      'invalid_or_expired_code' => 'Kod ne postoji ili je istekao',
      _ => switch (e.status) {
          401 => 'Ovaj uređaj nema aktivnu sesiju — osvježi i pokušaj ponovo',
          405 => 'Greška u pozivu (405)',
          _ => 'Prijenos nije uspio (${e.status})',
        },
    };
  }

  String _detectDevice() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      TargetPlatform.macOS => 'macos',
      _ => 'web',
    };
  }
}
