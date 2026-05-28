/// Real Supabase auth servis — preservira public API mock varijante
/// (currentUser/isAnonymous/isSignedIn/linkIdentity/signOut)
/// tako da pozivajući widgeti (AccountChip, auth_sheet, M2/M3/M4) rade
/// bez izmjena.
///
/// PII princip (v3): email i is_anonymous žive samo u auth.users.
/// Display name iz user_metadata['name'] (postavlja ga OAuth provider).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../main.dart' show log, rootScaffoldMessengerKey;
import 'favorites_service.dart';
import 'local_prefs.dart';
import 'passkey_service.dart';
import 'watch_progress_service.dart';

/// localStorage ključ — anon user UUID koji čeka migraciju u permanent
/// account-u. Stavi se prije OAuth redirecta, čita se nakon signedIn evenata.
/// Brišemo postavljanjem na prazan string (vidi local_prefs API).
const String _anonPendingMigrationKey = 'auth_anon_pending_migration_id';

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

    // Backfill + anon→permanent merge. Pokriva tri scenarija:
    //   1. Transition anon → permanent (linkIdentity ili signInWithOAuth)
    //   2. Restore permanent session (drugi browser, postojeci OAuth user)
    //   3. Cross-device sign-in s lokalnom poviješću koja nije sinkronizirana
    // Fire-and-forget — UI ne čeka.
    if (next != null && !next.isAnonymous) {
      _runMigrations(next.id);
      _migrateAnonDataIfPending(next.id);
    }
  }

  void _runMigrations(String userId) {
    WatchProgressService.instance.migrateToSupabase(userId);
    FavoritesService.instance.migrateToSupabase(userId);
  }

  /// Anon UUID je spremljen u localStorage prije OAuth redirecta (vidi
  /// linkIdentity). Nakon povratka na permanent sesiju pozovi server RPC
  /// koji prebaci watch_progress / sessions / handoff / onboarding redove
  /// s anon → permanent userom i obriše anon auth.users red.
  ///
  /// RPC spec: `docs/backend-prompts/08-anon-data-migration-rpc.md`.
  Future<void> _migrateAnonDataIfPending(String permanentId) async {
    final pendingAnonId = getLocalStorageString(_anonPendingMigrationKey);
    if (pendingAnonId == null) return;
    if (pendingAnonId == permanentId) {
      // Returning user signed in s istim ID-em — anon nikad nije bio kreiran
      // ili je već migriran. Cleanup ključa.
      setLocalStorageString(_anonPendingMigrationKey, '');
      return;
    }

    log('AuthService: migrating anon data $pendingAnonId → $permanentId');
    try {
      final client = sb.Supabase.instance.client;
      final result = await client
          .schema('domovina_ai')
          .rpc('migrate_anon_data', params: {'p_anon_id': pendingAnonId});
      log('AuthService: migrate_anon_data result=$result');
      setLocalStorageString(_anonPendingMigrationKey, '');
    } on sb.PostgrestException catch (e) {
      // RPC još ne postoji na backendu (PGRST202) ili je vratio business error.
      // Nije fatalno — anon data ostaje u DB-u, može se cleanupati kasnije.
      log('AuthService: migrate_anon_data Postgrest error: '
          '${e.code} ${e.message}');
      // Ne brišemo ključ ako je transient error — pokušaj će se ponoviti
      // pri sljedećem _setUser pozivu. Brišemo ga samo za poznate "ne pokušavaj
      // ponovo" slučajeve (RPC ne postoji još).
      if (e.code == 'PGRST202') {
        // Function not found. Cleanup da ne loop-amo.
        setLocalStorageString(_anonPendingMigrationKey, '');
      }
    } catch (e) {
      log('AuthService: migrate_anon_data unexpected: $e');
    }
  }

  /// Sign-in s OAuth/email providerom. Naziv je legacy ("linkIdentity")
  /// ali ponašanje je sad: UVIJEK signInWithOAuth, nikad GoTrue manual linking.
  ///
  /// Razlog: linkIdentity ne radi za "returning user u novom browseru" slučaj
  /// jer GoTrue baca identity_already_exists ako je Google account već vezan
  /// na nekog user-a. Umjesto toga koristimo:
  ///   1. Save trenutni anon UUID u localStorage
  ///   2. signInWithOAuth → Google → callback s novom permanent sesijom
  ///      (ili sign-in postojećeg permanent user-a)
  ///   3. Nakon signedIn evenata, _migrateAnonDataIfPending poziva server RPC
  ///      koji prebaci watch_progress/sessions/handoff iz anon → permanent.
  ///
  /// Spec migracije: docs/backend-prompts/08-anon-data-migration-rpc.md.
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
          final oauth = provider.oauthProvider!;
          final currentUser = client.auth.currentUser;
          final isAnon = currentUser?.isAnonymous == true;
          log('AuthService.linkIdentity: $provider isWeb=$kIsWeb '
              'currentUser=${currentUser?.id} anon=$isAnon');

          if (isAnon && currentUser != null) {
            setLocalStorageString(_anonPendingMigrationKey, currentUser.id);
            log('AuthService.linkIdentity: saved pending anon=${currentUser.id}');
          }

          await client.auth.signInWithOAuth(
            oauth,
            redirectTo: kIsWeb
                ? '${Uri.base.origin}/auth/callback'
                : 'ai.domovina://auth/callback',
          );
          // OAuth flow je redirect-based na webu → app će se reload-ati,
          // session listener iz init() će handlati state + migraciju.
          if (context.mounted) {
            _snack(context, 'Otvaram ${provider.displayName} prijavu…');
          }
          break;

        case AuthProvider.email:
          final email = await _promptForEmail(context, mockEmail);
          if (email == null || !context.mounted) return;
          final currentUser = client.auth.currentUser;
          if (currentUser?.isAnonymous == true && currentUser != null) {
            setLocalStorageString(_anonPendingMigrationKey, currentUser.id);
            log('AuthService.linkIdentity(email): saved pending anon=${currentUser.id}');
          }
          await client.auth.signInWithOtp(
            email: email,
            shouldCreateUser: true,
            emailRedirectTo: kIsWeb ? null : 'ai.domovina://auth/callback',
          );
          if (context.mounted) {
            _snack(context, 'Kod i magic link poslani na $email.');
            // Ponudi ručni unos koda (e-mail nosi i link i 6-znamenkasti kod).
            await _promptForOtpAndVerify(context, email);
          }
          break;

        case AuthProvider.passkey:
          await _registerPasskey(context);
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

  /// Registracija passkeyja (poziva se iz auth_sheet primary gumba).
  ///   - Permanent user → dodaj passkey na postojeći račun (bez email prompta).
  ///   - Anon/novi → prompt za email (treba za session bridge), spremi anon UUID
  ///     za migraciju, pa registriraj → novi permanent račun.
  /// Sesija stiže async preko onAuthStateChange (action_link).
  Future<void> _registerPasskey(BuildContext context) async {
    final client = _client();
    if (client == null) {
      _snack(context, 'Supabase nije konfiguriran.');
      return;
    }
    final current = client.auth.currentUser;
    final isPermanent = current != null && !current.isAnonymous;

    String? email;
    if (isPermanent) {
      email = current.email;
      if (email == null || email.isEmpty) {
        _snack(context, 'Tvoj račun nema e-mail — passkey trenutno nije moguć.');
        return;
      }
    } else {
      email = await _promptForEmail(context, null);
      if (email == null || !context.mounted) return;
      // Spremi anon UUID za migraciju nakon što stigne permanent sesija.
      if (current?.isAnonymous == true && current != null) {
        setLocalStorageString(_anonPendingMigrationKey, current.id);
        log('_registerPasskey: saved pending anon=${current.id}');
      }
    }

    try {
      await PasskeyService.instance.registerPasskey(email: email);
      if (context.mounted) {
        _snack(context, isPermanent
            ? 'Passkey je dodan na tvoj račun.'
            : 'Otvaram prijavu — passkey je kreiran…');
      }
    } on PasskeyFailure catch (e) {
      log('_registerPasskey PasskeyFailure: ${e.message}');
      if (context.mounted) _snack(context, e.message);
    }
  }

  /// Prijava postojećim passkeyom (returning sign-in). Sesija stiže async.
  Future<void> signInWithPasskey(BuildContext context) async {
    final client = _client();
    if (client == null) {
      _snack(context, 'Supabase nije konfiguriran.');
      return;
    }
    try {
      await PasskeyService.instance.loginWithPasskey();
      if (context.mounted) _snack(context, 'Prijava passkeyom u tijeku…');
    } on PasskeyFailure catch (e) {
      log('signInWithPasskey PasskeyFailure: ${e.message}');
      if (context.mounted) _snack(context, e.message);
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
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.pop(ctx, controller.text.trim()),
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

  /// Prikaži SnackBar preko GLOBALNOG ScaffoldMessenger key-a (ne preko
  /// context-a) — feedback radi i kad je sheet/dialog već zatvoren pa je
  /// proslijeđeni context unmountan. [context] se zadržava radi potpisa.
  /// Dijalog za ručni unos 6-znamenkastog OTP koda iz magic link e-maila.
  /// Verificira preko verifyOTP(type: email); sesija stigne preko onAuthStateChange.
  /// (Alternativa kliku na link u e-mailu — radi i ako se link otvori u drugom
  /// pregledniku/uređaju.)
  Future<void> _promptForOtpAndVerify(BuildContext context, String email) async {
    final client = _client();
    if (client == null) return;
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unesi kod iz e-maila'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Poslali smo 6-znamenkasti kod na $email. '
              'Upiši ga ovdje — ili samo klikni link u e-mailu.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              maxLength: 6,
              onSubmitted: (_) => Navigator.pop(ctx, controller.text.trim()),
              decoration: const InputDecoration(
                hintText: '123456',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Odustani'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Potvrdi'),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    log('AuthService: verifyOTP email=$email');
    try {
      await client.auth.verifyOTP(
        type: sb.OtpType.email,
        email: email,
        token: code,
      );
      // Uspjeh → onAuthStateChange postavi permanent sesiju + migracija.
      _showSnack('Prijava uspješna.');
    } on sb.AuthException catch (e) {
      log('verifyOTP error: ${e.message}');
      _showSnack('Kod nije ispravan ili je istekao.');
    }
  }

  void _snack(BuildContext context, String msg, {String? actionLabel}) =>
      _showSnack(msg, actionLabel: actionLabel);

  void _showSnack(String msg, {String? actionLabel}) {
    rootScaffoldMessengerKey.currentState?.showSnackBar(
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
