/// Cross-device handoff. createCode poziva `domovina_ai.create_handoff_token`
/// RPC i vraća 6-znamenkasti kod. consumeCode pokuša pozvati edge function
/// `https://api.domovina.ai/handoff/consume` (koja interno radi
/// consume_handoff_token RPC s service_role i vraća magic link za sign-in).
///
/// Ako edge function vraća 404 (još nije deployan), fallback je UI-only
/// forceSignIn preko AuthService — pokaže se success screen ali stvarna
/// Supabase sesija ostaje neizmijenjena. Vidi docs/backend-prompts/06.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../main.dart' show log;
import 'auth_service.dart';

class HandoffToken {
  final String code;
  final String sourceUserId;
  final String? sourceDisplayName;
  final String? sourceEmail;
  final AuthProvider? sourceProvider;
  final DateTime expiresAt;
  bool consumed;

  HandoffToken({
    required this.code,
    required this.sourceUserId,
    this.sourceDisplayName,
    this.sourceEmail,
    this.sourceProvider,
    required this.expiresAt,
    this.consumed = false,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class HandoffService {
  static final HandoffService instance = HandoffService._();
  HandoffService._();

  String get _supabaseBase {
    // SUPABASE_URL is the Kong gateway base; edge function is /handoff/consume.
    return const String.fromEnvironment('SUPABASE_URL');
  }

  /// Generira novi handoff kod preko RPC. Prethodne nepotrošene kodove istog
  /// usera RPC automatski briše (vidi 06-handoff-rpc.md).
  Future<String> createCode() async {
    final user = AuthService.instance.currentUser;
    if (user == null) throw StateError('Nema usera za handoff');

    try {
      final client = sb.Supabase.instance.client;
      final result = await client
          .schema('domovina_ai')
          .rpc('create_handoff_token');
      return result as String;
    } on sb.PostgrestException catch (e) {
      log('create_handoff_token RPC failed: ${e.message}');
      throw StateError('Backend ne odgovara: ${e.message}');
    }
  }

  /// Konzumira kod. Prvi pokušaj ide preko edge function-a koji obrne magic
  /// link i sign-ina trenutnu sesiju kao target user. Ako 404 → fallback
  /// na force UI sign-in (mock until edge function lands).
  Future<HandoffToken> consumeCode(String code) async {
    final clean = code.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length != 6) {
      throw const FormatException('Kod mora imati točno 6 znamenki');
    }

    // Pokušaj 1: edge function. Vraća { user_id, source_display_name?, source_email?, action_link? }
    try {
      final response = await http
          .post(
            Uri.parse('$_supabaseBase/handoff/consume'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'code': clean, 'device': _detectDevice()}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        // Ako edge function vraća action_link, otvori ga da Supabase završi sign-in.
        // Browser će se preusmjeriti, session listener u AuthService.init handlat će rest.
        final actionLink = body['action_link'] as String?;
        if (actionLink != null && actionLink.isNotEmpty) {
          log('handoff: redirecting to action_link');
          // TODO: navigator.location.replace(actionLink) — za sad samo log
          //       i fallback na force sign-in; integracija deeplink-a dolazi
          //       kad edge function bude testiran.
        }
        return HandoffToken(
          code: clean,
          sourceUserId: body['user_id'] as String? ?? '',
          sourceDisplayName: body['source_display_name'] as String?,
          sourceEmail: body['source_email'] as String?,
          sourceProvider: _parseProvider(body['source_provider'] as String?),
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
          consumed: true,
        );
      }

      if (response.statusCode == 404) {
        log('handoff: edge function 404 — fallback to RPC + UI-only force sign-in');
        return _consumeViaRpcFallback(clean);
      }

      throw StateError('Edge function vratio ${response.statusCode}');
    } on FormatException {
      rethrow;
    } catch (e) {
      log('handoff consume edge failed ($e) — fallback to RPC');
      return _consumeViaRpcFallback(clean);
    }
  }

  /// RPC fallback — poziva consume_handoff_token direktno (security definer).
  /// Vraća source user_id; force sign-in u UI je responsibility caller-a.
  Future<HandoffToken> _consumeViaRpcFallback(String code) async {
    try {
      final client = sb.Supabase.instance.client;
      final result = await client.schema('domovina_ai').rpc(
        'consume_handoff_token',
        params: {'p_code': code, 'p_device': _detectDevice()},
      );
      final map = result is Map<String, dynamic>
          ? result
          : (result as Map).cast<String, dynamic>();
      return HandoffToken(
        code: code,
        sourceUserId: map['user_id'] as String? ?? '',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        consumed: true,
      );
    } on sb.PostgrestException catch (e) {
      // 'invalid_or_expired_code' iz RPC-a — bubble up s human message
      if (e.message.contains('invalid_or_expired')) {
        throw StateError('Kod ne postoji ili je istekao');
      }
      throw StateError(e.message);
    }
  }

  AuthProvider? _parseProvider(String? raw) {
    if (raw == null) return null;
    return AuthProvider.values.firstWhere(
      (p) => p.name == raw,
      orElse: () => AuthProvider.email,
    );
  }

  String _detectDevice() {
    // Match watch_progress device_type enum.
    return 'web';
  }
}
