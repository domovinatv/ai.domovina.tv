/// MOCK handoff servis — generira 6-znamenkasti kod, drži ga 5 minuta in-memory.
/// U pravom backendu RPC `create_handoff_token` vraća kod, `consume_handoff_token`
/// ga konzumira (vidi docs/backend-prompts/06-handoff-rpc.md).
library;

import 'dart:math';
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

  final Map<String, HandoffToken> _tokens = {};
  final _rand = Random();

  /// Generiraj novi kod za trenutnog usera. Prethodne nepotrosene kodove istog
  /// usera obrise (kao u SQL RPC).
  Future<String> createCode() async {
    final user = AuthService.instance.currentUser;
    if (user == null) throw StateError('Nema usera za handoff');

    // Cleanup
    _tokens.removeWhere((_, t) => t.sourceUserId == user.id && !t.consumed);
    _tokens.removeWhere((_, t) => t.isExpired);

    String code;
    var tries = 0;
    do {
      code = (_rand.nextInt(1000000)).toString().padLeft(6, '0');
      tries++;
    } while (_tokens.containsKey(code) && tries < 5);

    _tokens[code] = HandoffToken(
      code: code,
      sourceUserId: user.id,
      sourceDisplayName: user.displayName,
      sourceEmail: user.email,
      sourceProvider: user.provider,
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );

    // Simuliraj network latency
    await Future.delayed(const Duration(milliseconds: 400));
    return code;
  }

  /// Konzumiraj kod — vraća source user info. U pravom backendu sljedeći korak
  /// je redirect na magic link koji završi sign-in.
  Future<HandoffToken> consumeCode(String code) async {
    final clean = code.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length != 6) {
      throw const FormatException('Kod mora imati točno 6 znamenki');
    }

    await Future.delayed(const Duration(milliseconds: 400));

    final t = _tokens[clean];
    if (t == null) throw StateError('Kod ne postoji ili je istekao');
    if (t.consumed) throw StateError('Kod je već iskorišten');
    if (t.isExpired) throw StateError('Kod je istekao (5 min limit)');

    t.consumed = true;
    return t;
  }
}
