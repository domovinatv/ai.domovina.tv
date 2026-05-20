/// MOCK auth servis — simulira Supabase anonymous + linkIdentity flow.
/// Sve linkIdentity metode prikazuju SnackBar i postavljaju in-memory "logged-in"
/// state. Pravi backend swap je dokumentiran u docs/backend-prompts/07-flutter-swap-mocks.md.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_prefs.dart';
import '../main.dart' show log;

const _kAuthMockUserKey = 'auth_mock_user';

/// Provider info — kakav identitet je linkan u mocku.
enum AuthProvider { google, apple, email, passkey }

extension AuthProviderLabel on AuthProvider {
  String get displayName => switch (this) {
        AuthProvider.google => 'Google',
        AuthProvider.apple => 'Apple',
        AuthProvider.email => 'E-mail',
        AuthProvider.passkey => 'Passkey',
      };
}

class MockUser {
  final String id;
  final bool isAnonymous;
  final String? email;
  final String? displayName;
  final AuthProvider? provider;

  const MockUser({
    required this.id,
    required this.isAnonymous,
    this.email,
    this.displayName,
    this.provider,
  });

  Map<String, String> toMap() {
    final m = <String, String>{
      'id': id,
      'isAnonymous': isAnonymous.toString(),
    };
    if (email != null) m['email'] = email!;
    if (displayName != null) m['displayName'] = displayName!;
    if (provider != null) m['provider'] = provider!.name;
    return m;
  }

  static MockUser? fromRaw(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final parts = raw.split('|');
      final map = <String, String>{};
      for (final p in parts) {
        final i = p.indexOf('=');
        if (i > 0) map[p.substring(0, i)] = p.substring(i + 1);
      }
      return MockUser(
        id: map['id'] ?? '',
        isAnonymous: map['isAnonymous'] == 'true',
        email: map['email'],
        displayName: map['displayName'],
        provider: map['provider'] != null
            ? AuthProvider.values.firstWhere(
                (p) => p.name == map['provider'],
                orElse: () => AuthProvider.email,
              )
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  String serialize() => toMap()
      .entries
      .map((e) => '${e.key}=${e.value}')
      .join('|');
}

class AuthService extends ChangeNotifier {
  static final AuthService instance = AuthService._();
  AuthService._();

  MockUser? _user;

  MockUser? get currentUser => _user;
  bool get isAnonymous => _user?.isAnonymous ?? true;
  bool get isSignedIn => _user != null && !_user!.isAnonymous;
  String get userId => _user?.id ?? '';

  Future<void> init() async {
    // Restore persisted user (simulira Supabase session restore)
    final raw = await _load();
    _user = MockUser.fromRaw(raw);

    if (_user == null) {
      // signInAnonymously simulacija
      _user = MockUser(
        id: 'anon-${DateTime.now().millisecondsSinceEpoch}',
        isAnonymous: true,
      );
      await _save(_user!.serialize());
      log('AuthService: created anonymous user ${_user!.id}');
    } else {
      log('AuthService: restored user ${_user!.id} (anon=${_user!.isAnonymous})');
    }
    notifyListeners();
  }

  /// Mock linkIdentity — pokaže SnackBar, postavi user na permanent.
  Future<void> linkIdentity(
    BuildContext context,
    AuthProvider provider, {
    String? mockEmail,
  }) async {
    log('AuthService.linkIdentity($provider)');
    _showSnack(
      context,
      'MOCK: linkIdentity(${provider.displayName})… '
      '(pravi backend bi sad otvorio OAuth)',
    );

    // Simuliraj network latency
    await Future.delayed(const Duration(milliseconds: 700));

    final fakeEmail = mockEmail ?? _fakeEmailFor(provider);
    final fakeName = _fakeNameFor(provider);

    _user = MockUser(
      id: _user?.id ?? 'mock-${DateTime.now().millisecondsSinceEpoch}',
      isAnonymous: false,
      email: fakeEmail,
      displayName: fakeName,
      provider: provider,
    );
    await _save(_user!.serialize());

    if (context.mounted) {
      _showSnack(
        context,
        'MOCK: prijavljen kao $fakeName ($fakeEmail) preko ${provider.displayName}',
        actionLabel: 'OK',
      );
    }
    notifyListeners();
  }

  Future<void> signOut(BuildContext context) async {
    log('AuthService.signOut');
    _user = MockUser(
      id: 'anon-${DateTime.now().millisecondsSinceEpoch}',
      isAnonymous: true,
    );
    await _save(_user!.serialize());
    if (context.mounted) {
      _showSnack(context, 'Odjavljen — nastavljaš kao gost');
    }
    notifyListeners();
  }

  /// Force-promote bez UI feedback-a (interno korišteno nakon M4 handoff consume).
  Future<void> forceSignIn({
    required String id,
    required String displayName,
    required String email,
    required AuthProvider provider,
  }) async {
    _user = MockUser(
      id: id,
      isAnonymous: false,
      email: email,
      displayName: displayName,
      provider: provider,
    );
    await _save(_user!.serialize());
    notifyListeners();
  }

  // -- helpers --

  String _fakeEmailFor(AuthProvider p) => switch (p) {
        AuthProvider.google => 'matija.test@gmail.com',
        AuthProvider.apple => 'matija.test@privaterelay.appleid.com',
        AuthProvider.email => 'matija@example.com',
        AuthProvider.passkey => 'matija.test@passkey.local',
      };

  String _fakeNameFor(AuthProvider p) => switch (p) {
        AuthProvider.google => 'Matija (Google)',
        AuthProvider.apple => 'Matija (Apple)',
        AuthProvider.email => 'Matija',
        AuthProvider.passkey => 'Matija (Passkey)',
      };

  void _showSnack(BuildContext context, String msg, {String? actionLabel}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 3),
        action: actionLabel != null
            ? SnackBarAction(label: actionLabel, onPressed: () {})
            : null,
      ),
    );
  }

  Future<String?> _load() async {
    if (kIsWeb) return getLocalStorageString(_kAuthMockUserKey);
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kAuthMockUserKey);
  }

  Future<void> _save(String value) async {
    if (kIsWeb) {
      setLocalStorageString(_kAuthMockUserKey, value);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAuthMockUserKey, value);
  }
}
