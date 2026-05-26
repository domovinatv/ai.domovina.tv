/// Real Supabase auth servis — preservira public API mock varijante
/// (currentUser/isAnonymous/isSignedIn/linkIdentity/signOut/forceSignIn)
/// tako da pozivajući widgeti (AccountChip, auth_sheet, M2/M3/M4) rade
/// bez izmjena.
///
/// PII princip (v3): email i is_anonymous žive samo u auth.users.
/// Display name iz user_metadata['name'] (postavlja ga OAuth provider).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../main.dart' show log;
import 'favorites_service.dart';
import 'watch_progress_service.dart';

/// Provider info — kakav identitet je linkan. Mapira na sb.OAuthProvider
/// za Google/Apple; email i passkey su custom flow-ovi.
enum AuthProvider { google, apple, email, passkey }

extension AuthProviderLabel on AuthProvider {
  String get displayName => switch (this) {
        AuthProvider.google => 'Google',
        AuthProvider.apple => 'Apple',
        AuthProvider.email => 'E-mail',
        AuthProvider.passkey => 'Passkey',
      };

  /// Najbliži supabase_flutter OAuth provider za ovaj enum (null za email/passkey).
  sb.OAuthProvider? get oauthProvider => switch (this) {
        AuthProvider.google => sb.OAuthProvider.google,
        AuthProvider.apple => sb.OAuthProvider.apple,
        AuthProvider.email => null,
        AuthProvider.passkey => null,
      };
}

/// View model nad sb.User — ostaje isti shape kao mock MockUser tako
/// da pozivajući kod ne treba mijenjati.
class AppUser {
  final String id;
  final bool isAnonymous;
  final String? email;
  final String? displayName;
  final AuthProvider? provider;

  const AppUser({
    required this.id,
    required this.isAnonymous,
    this.email,
    this.displayName,
    this.provider,
  });

  factory AppUser.fromSupabase(sb.User u) {
    final meta = u.userMetadata ?? const {};
    String? displayName = meta['name'] as String?
        ?? meta['full_name'] as String?
        ?? meta['preferred_username'] as String?;
    if (displayName == null || displayName.isEmpty) {
      displayName = u.email?.split('@').firstOrNull;
    }

    // Detektiraj koji je provider linked. Identities sadrži OAuth providere;
    // ako nema OAuth identiteta a postoji email → magic link.
    AuthProvider? provider;
    final identities = u.identities ?? const [];
    final providerNames = identities
        .map((i) => i.provider)
        .where((p) => p != 'email')
        .toList();
    if (providerNames.contains('google')) {
      provider = AuthProvider.google;
    } else if (providerNames.contains('apple')) {
      provider = AuthProvider.apple;
    } else if (u.email != null && !u.isAnonymous) {
      provider = AuthProvider.email;
    }

    return AppUser(
      id: u.id,
      isAnonymous: u.isAnonymous,
      email: u.email,
      displayName: displayName,
      provider: provider,
    );
  }
}

class AuthService extends ChangeNotifier {
  static final AuthService instance = AuthService._();
  AuthService._();

  AppUser? _user;

  AppUser? get currentUser => _user;
  bool get isAnonymous => _user?.isAnonymous ?? true;
  bool get isSignedIn => _user != null && !_user!.isAnonymous;
  String get userId => _user?.id ?? '';

  bool _initialized = false;

  /// Pozove se iz main.dart NAKON Supabase.initialize() + signInAnonymously().
  /// Pretplaća se na auth state changes i drži _user u syncu.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final client = sb.Supabase.instance.client;
      _setUser(client.auth.currentUser);

      client.auth.onAuthStateChange.listen((data) {
        log('AuthService: auth event ${data.event} '
            'user=${data.session?.user.id} '
            'anon=${data.session?.user.isAnonymous}');
        _setUser(data.session?.user);
      });
    } catch (e) {
      // Supabase nije inicijaliziran (no env) — ostani s null user-om;
      // mock fallback opisno bi mogao biti dodatak, ali za sad samo log.
      log('AuthService.init: Supabase unavailable — $e');
    }
  }

  void _setUser(sb.User? u) {
    final next = u == null ? null : AppUser.fromSupabase(u);
    if (next?.id == _user?.id && next?.isAnonymous == _user?.isAnonymous) {
      // Manje stvarne promjene (npr. metadata) — i dalje refresh
      // jer chip moze imati novi displayName.
    }
    _user = next;
    notifyListeners();

    // Step 9 (handoff prompt): backfill localStorage → Supabase za non-anon
    // user-a. Per-user gate flag u localStorage cini ovo idempotent;
    // pokriva i transition anon→permanent i restore-sa-permanent-session
    // (npr. korisnik koji se logirao na drugom uredjaju ima local povijest
    // koja jos nije sinkronizirana). Fire-and-forget — UI ne ceka.
    if (next != null && !next.isAnonymous) {
      _runMigrations(next.id);
    }
  }

  void _runMigrations(String userId) {
    WatchProgressService.instance.migrateToSupabase(userId);
    FavoritesService.instance.migrateToSupabase(userId);
  }

  /// Anonymous → permanent flow. Za Google/Apple koristi linkIdentity
  /// (Supabase otvori OAuth redirect). Za email šalje magic link / OTP.
  /// Passkey je još uvijek mock fallback dok ne ide nativni WebAuthn flow
  /// kroz custom edge function — vidi docs/backend-prompts/05-auth-providers.md.
  Future<void> linkIdentity(
    BuildContext context,
    AuthProvider provider, {
    String? mockEmail,
  }) async {
    log('AuthService.linkIdentity($provider)');
    final client = _client();
    if (client == null) {
      _snack(context, 'Supabase nije konfiguriran — nije moguće povezati račun.');
      return;
    }

    try {
      switch (provider) {
        case AuthProvider.google:
        case AuthProvider.apple:
          log('AuthService.linkIdentity: Zapoceto za $provider (isWeb: $kIsWeb)');
          final oauth = provider.oauthProvider!;
          final isAnon = client.auth.currentUser?.isAnonymous == true;
          log('AuthService.linkIdentity: currentUser anon=$isAnon, id=${client.auth.currentUser?.id}');
          
          if (isAnon) {
            log('AuthService.linkIdentity: Pozivam client.auth.linkIdentity($oauth)...');
            final res = await client.auth.linkIdentity(
              oauth,
              redirectTo: kIsWeb ? '${Uri.base.origin}/auth/callback' : 'ai.domovina://auth/callback',
            );
            log('AuthService.linkIdentity: linkIdentity zavrsen. Rezultat: $res');
          } else {
            log('AuthService.linkIdentity: Pozivam client.auth.signInWithOAuth($oauth)...');
            final res = await client.auth.signInWithOAuth(
              oauth,
              redirectTo: kIsWeb ? '${Uri.base.origin}/auth/callback' : 'ai.domovina://auth/callback',
            );
            log('AuthService.linkIdentity: signInWithOAuth zavrsen. Rezultat: $res');
          }
          // OAuth flow je redirect-based na webu → app će se reload-ati,
          // session listener iz init() će handlati state.
          if (context.mounted) {
            log('AuthService.linkIdentity: Prikazujem snackbar o otvaranju prijave');
            _snack(context, 'Otvaram ${provider.displayName} prijavu…');
          }
          break;

        case AuthProvider.email:
          final email = await _promptForEmail(context, mockEmail);
          if (email == null || !context.mounted) return;
          await client.auth.signInWithOtp(
            email: email,
            shouldCreateUser: true,
            emailRedirectTo: kIsWeb ? null : 'ai.domovina://auth/callback',
          );
          if (context.mounted) {
            _snack(
              context,
              'Magic link je poslan na $email — provjeri inbox.',
              actionLabel: 'OK',
            );
          }
          break;

        case AuthProvider.passkey:
          // TODO: implementirati WebAuthn preko passkeys package + custom
          // /passkey/register/start endpoint. Vidi 05-auth-providers.md §Passkey.
          _snack(
            context,
            'Passkey još nije dostupan — koristi Google, Apple ili e-mail za sada.',
          );
          break;
      }
    } on sb.AuthException catch (e) {
      log('linkIdentity AuthException: ${e.message} (status: ${e.statusCode})');
      if (context.mounted) {
        _snack(context, 'Greška (AuthException): ${e.message}');
      }
    } catch (e, stackTrace) {
      log('linkIdentity neocekivana greska: $e\n$stackTrace');
      if (context.mounted) {
        _snack(context, 'Neočekivana greška pri prijavi.');
      }
    }
  }

  Future<void> signOut(BuildContext context) async {
    log('AuthService.signOut');
    final client = _client();
    if (client == null) return;
    try {
      await client.auth.signOut();
      // Odmah kreiraj novu anonymous sesiju da app ostane funkcionalan.
      await client.auth.signInAnonymously();
      if (context.mounted) {
        _snack(context, 'Odjavljen — nastavljaš kao gost');
      }
    } on sb.AuthException catch (e) {
      log('signOut error: ${e.message}');
    }
  }

  /// FALLBACK za M4 handoff kad edge function /handoff/consume nije available.
  /// Pravi flow je: edge function consume RPC + generira magic link → session
  /// se prebaci preko onAuthStateChange listenera u init(). Dok edge function
  /// ne postoji, handoff_service poziva forceSignIn nakon RPC consume da
  /// barem prikaže success screen (no real session switch — UI-only).
  Future<void> forceSignIn({
    required String id,
    required String displayName,
    required String email,
    required AuthProvider provider,
  }) async {
    log('AuthService.forceSignIn (UI fallback): $id');
    // Ne mijenjamo stvarnu Supabase sesiju — to mora ići preko magic link-a
    // iz edge function-a. Samo updateamo UI state s prikazom target user-a.
    _user = AppUser(
      id: id,
      isAnonymous: false,
      email: email,
      displayName: displayName,
      provider: provider,
    );
    notifyListeners();
  }

  // -- helpers --

  sb.SupabaseClient? _client() {
    try {
      return sb.Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _promptForEmail(BuildContext context, String? prefill) async {
    final controller = TextEditingController(text: prefill ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('E-mail za magic link'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            hintText: 'ime@primjer.com',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Odustani'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Pošalji'),
          ),
        ],
      ),
    );
    return result == null || result.isEmpty ? null : result;
  }

  void _snack(BuildContext context, String msg, {String? actionLabel}) {
    if (!context.mounted) return;
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
}
