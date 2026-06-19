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
import '../onboarding/ui/auth_ui.dart';
import 'certilia_service.dart';
import 'favorites_service.dart';
import 'local_prefs.dart';
import 'passkey_service.dart';
import 'watch_progress_service.dart';

/// localStorage ključ — anon user UUID koji čeka migraciju u permanent
/// account-u. Stavi se prije OAuth redirecta, čita se nakon signedIn evenata.
/// Brišemo postavljanjem na prazan string (vidi local_prefs API).
const String _anonPendingMigrationKey = 'auth_anon_pending_migration_id';

/// localStorage ključ — zadnja uspješno korištena metoda prijave
/// (AuthProvider.name). Auth sheet ju ističe "ZADNJI PUT" badgeom da
/// returning user ne otvori slučajno drugi račun drugom metodom.
const String lastProviderKey = 'auth_last_provider';

/// Provider info — kakav identitet je linkan. Mapira na sb.OAuthProvider
/// za Google/Apple; email i passkey su custom flow-ovi.
enum AuthProvider { google, apple, email, passkey, certilia }

extension AuthProviderLabel on AuthProvider {
  String get displayName => switch (this) {
        AuthProvider.google => 'Google',
        AuthProvider.apple => 'Apple',
        AuthProvider.email => 'E-mail',
        AuthProvider.passkey => 'Passkey',
        AuthProvider.certilia => 'eOsobna',
      };

  /// Najbliži supabase_flutter OAuth provider za ovaj enum (null za custom flow-ove).
  sb.OAuthProvider? get oauthProvider => switch (this) {
        AuthProvider.google => sb.OAuthProvider.google,
        AuthProvider.apple => sb.OAuthProvider.apple,
        AuthProvider.email => null,
        AuthProvider.passkey => null,
        AuthProvider.certilia => null,
      };
}

/// Ishod jednog auth pokušaja. Pozivatelj (auth sheet) na temelju statusa
/// odlučuje zatvara li sheet i prikazuje li grešku inline (ne snackbar).
enum AuthFlowStatus {
  /// Sesija je uspostavljena (ili stiže kroz onAuthStateChange unutar sekunde).
  success,

  /// Pokrenut browser redirect (OAuth) — stranica / vanjski browser preuzima.
  redirect,

  /// Magic link + kod su poslani; korisnik nastavlja kroz e-mail.
  /// [AuthFlowResult.message] nosi e-mail adresu.
  emailSent,

  /// Korisnik je odustao (zatvorio dialog/ceremoniju) — nije greška.
  cancelled,

  /// Greška — [AuthFlowResult.message] je human-readable hrvatski tekst.
  failure,
}

class AuthFlowResult {
  final AuthFlowStatus status;
  final String? message;

  /// Passkey login pao jer na uređaju NEMA passkeyja — pozivatelj može
  /// ponuditi kreiranje novog umjesto suhe greške.
  final bool passkeyMissing;

  const AuthFlowResult(this.status, [this.message])
      : passkeyMissing = false;
  const AuthFlowResult.noPasskey(this.message)
      : status = AuthFlowStatus.failure,
        passkeyMissing = true;

  static const success = AuthFlowResult(AuthFlowStatus.success);
  static const redirect = AuthFlowResult(AuthFlowStatus.redirect);
  static const cancelled = AuthFlowResult(AuthFlowStatus.cancelled);
  static AuthFlowResult failure(String message) =>
      AuthFlowResult(AuthFlowStatus.failure, message);
}

/// View model nad sb.User — ostaje isti shape kao mock MockUser tako
/// da pozivajući kod ne treba mijenjati.
class AppUser {
  final String id;
  final bool isAnonymous;
  final String? email;
  final String? displayName;
  final AuthProvider? provider;

  /// KYC: identitet verificiran preko eID-a (Certilia). Iz app_metadata.
  final bool isVerified;

  const AppUser({
    required this.id,
    required this.isAnonymous,
    this.email,
    this.displayName,
    this.provider,
    this.isVerified = false,
  });

  factory AppUser.fromSupabase(sb.User u) {
    final meta = u.userMetadata ?? const {};
    final appMeta = u.appMetadata;
    // Certilia se NE detektira samo preko app_metadata['provider'] — to polje
    // održava i GoTrue (postavi ga prvi provider, npr. 'google') pa ga merge
    // s postojećim računom može pregaziti. kyc_verified piše isključivo
    // certilia edge fn i preživljava merge → robustan signal.
    final isCertilia = appMeta['provider'] == 'certilia' ||
        appMeta['kyc_verified'] == true;

    String? displayName = meta['name'] as String?
        ?? meta['full_name'] as String?
        ?? meta['preferred_username'] as String?
        ?? (isCertilia ? appMeta['full_name'] as String? : null);
    if (displayName == null || displayName.isEmpty) {
      displayName = u.email?.split('@').firstOrNull;
    }

    // Detektiraj koji je provider linked. OAuth identities imaju prednost
    // (merged račun: chip kaže "preko Google", KYC badge ide odvojeno);
    // certilia za synthetic-email usere bez OAuth identiteta.
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
    } else if (isCertilia) {
      provider = AuthProvider.certilia;
    } else if (u.email != null && !u.isAnonymous) {
      provider = AuthProvider.email;
    }

    return AppUser(
      id: u.id,
      isAnonymous: u.isAnonymous,
      email: u.email,
      displayName: displayName,
      provider: provider,
      isVerified: appMeta['kyc_verified'] == true,
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
    // Anon → permanent tranzicija unutar appa (link/prijava bez reloada):
    // potvrdi uspjeh korisniku + zapamti zadnju metodu za sheet hint.
    // (OAuth redirect path ima vlastitu potvrdu u AuthCallbackScreen.)
    final wasAnonymous = _user?.isAnonymous ?? false;
    if (wasAnonymous && next != null && !next.isAnonymous) {
      _showSnack(
          'Prijavljen si kao ${next.displayName ?? next.email ?? 'korisnik'}.');
      if (next.provider != null) {
        setLocalStorageString(lastProviderKey, next.provider!.name);
      }
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
    // Prvo gurni lokalnu povijest gore (idempotent, gate-an per user), pa
    // povuci remote natrag u lokalni cache da resume putanja (getSync) vidi
    // pozicije s drugih uređaja / nakon force-quita.
    WatchProgressService.instance
        .migrateToSupabase(userId)
        .then((_) => WatchProgressService.instance.hydrateFromSupabase());
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
  Future<AuthFlowResult> linkIdentity(
    BuildContext context,
    AuthProvider provider, {
    String? mockEmail,
  }) async {
    log('AuthService.linkIdentity($provider)');
    final client = _client();
    if (client == null) {
      return AuthFlowResult.failure(
          'Supabase nije konfiguriran — prijava nije moguća.');
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
          // Web: slijedi full-page redirect (session listener iz init()
          // handla state + migraciju po povratku). Native: otvoren je
          // vanjski browser pa korisniku treba hint gdje nastaviti.
          if (!kIsWeb) {
            _showSnack('Nastavi prijavu u pregledniku…');
          }
          return AuthFlowResult.redirect;

        case AuthProvider.email:
          // Primarni e-mail flow vodi auth sheet (in-sheet koraci preko
          // sendEmailOtp/verifyEmailOtp). Ovaj fallback samo pošalje link.
          final email = mockEmail ?? await _promptForEmail(context, null);
          if (email == null) return AuthFlowResult.cancelled;
          return await sendEmailOtp(email);

        case AuthProvider.passkey:
          return await _registerPasskey(context);

        case AuthProvider.certilia:
          return await signInWithCertilia(context);
      }
    } on sb.AuthException catch (e) {
      log('linkIdentity AuthException: ${e.message} '
          '(code: ${e.code}, status: ${e.statusCode})');
      return AuthFlowResult.failure(friendlyAuthError(e));
    } catch (e, stackTrace) {
      log('linkIdentity neocekivana greska: $e\n$stackTrace');
      return AuthFlowResult.failure(
          'Neočekivana greška pri prijavi. Pokušaj ponovo.');
    }
  }

  /// Mapiranje GoTrue grešaka na hrvatske poruke razumljive korisniku.
  /// Sirove engleske poruke ([sb.AuthException.message]) nikad ne idu u UI.
  static String friendlyAuthError(sb.AuthException e) {
    final byCode = switch (e.code) {
      'over_email_send_rate_limit' ||
      'over_request_rate_limit' ||
      'over_sms_send_rate_limit' =>
        'Previše pokušaja — pričekaj minutu pa pokušaj ponovo.',
      'email_address_invalid' || 'validation_failed' =>
        'E-mail adresa ne izgleda ispravno. Provjeri unos.',
      'otp_expired' => 'Kod je istekao — zatraži novi.',
      'otp_disabled' => 'Prijava kodom trenutno nije dostupna.',
      'user_banned' => 'Ovaj račun je privremeno blokiran.',
      'signup_disabled' => 'Registracija novih računa trenutno nije moguća.',
      'provider_disabled' => 'Ova metoda prijave trenutno nije dostupna.',
      'email_not_confirmed' => 'E-mail adresa još nije potvrđena.',
      _ => null,
    };
    if (byCode != null) return byCode;
    if (e is sb.AuthRetryableFetchException) {
      return 'Nema veze s poslužiteljem. Provjeri internet pa pokušaj ponovo.';
    }
    return 'Prijava nije uspjela. Pokušaj ponovo.';
  }

  /// Registracija passkeyja (poziva se iz auth_sheet primary gumba).
  ///   - Permanent user → dodaj passkey na postojeći račun (bez email prompta).
  ///   - Anon/novi → prompt za email (treba za session bridge), spremi anon UUID
  ///     za migraciju, pa registriraj → novi permanent račun.
  /// Sesija stiže async preko onAuthStateChange (action_link).
  Future<AuthFlowResult> _registerPasskey(BuildContext context) async {
    final client = _client();
    if (client == null) {
      return AuthFlowResult.failure('Supabase nije konfiguriran.');
    }
    final current = client.auth.currentUser;
    final isPermanent = current != null && !current.isAnonymous;

    String? email;
    if (isPermanent) {
      email = current.email;
      if (email == null || email.isEmpty) {
        return AuthFlowResult.failure(
            'Tvoj račun nema e-mail — passkey trenutno nije moguć.');
      }
    } else {
      email = await _promptForEmail(context, null);
      if (email == null) return AuthFlowResult.cancelled;
      // Spremi anon UUID za migraciju nakon što stigne permanent sesija.
      if (current?.isAnonymous == true && current != null) {
        setLocalStorageString(_anonPendingMigrationKey, current.id);
        log('_registerPasskey: saved pending anon=${current.id}');
      }
    }

    try {
      await PasskeyService.instance.registerPasskey(email: email);
      return AuthFlowResult(
        AuthFlowStatus.success,
        isPermanent ? 'Passkey je dodan na tvoj račun.' : 'Passkey je kreiran.',
      );
    } on PasskeyFailure catch (e) {
      log('_registerPasskey PasskeyFailure: ${e.message}');
      return AuthFlowResult.failure(e.message);
    }
  }

  /// Prijava postojećim passkeyom (returning sign-in). Sesija stiže async.
  Future<AuthFlowResult> signInWithPasskey(BuildContext context) async {
    final client = _client();
    if (client == null) {
      return AuthFlowResult.failure('Supabase nije konfiguriran.');
    }
    try {
      await PasskeyService.instance.loginWithPasskey();
      return AuthFlowResult.success;
    } on PasskeyFailure catch (e) {
      log('signInWithPasskey PasskeyFailure: ${e.message}');
      if (e.noCredential) return AuthFlowResult.noPasskey(e.message);
      return AuthFlowResult.failure(e.message);
    }
  }

  /// Prijava hrvatskom eOsobnom (Certilia/NIAS). Spremi anon UUID za migraciju
  /// pa pokreni Certilia OIDC flow + bridge. Po uspjehu je sesija već
  /// postavljena (verifyOTP unutar CertiliaService).
  Future<AuthFlowResult> signInWithCertilia(BuildContext context) async {
    final client = _client();
    if (client == null) {
      return AuthFlowResult.failure('Supabase nije konfiguriran.');
    }
    final current = client.auth.currentUser;
    String? anonId;
    if (current?.isAnonymous == true && current != null) {
      anonId = current.id;
      setLocalStorageString(_anonPendingMigrationKey, current.id);
      log('signInWithCertilia: saved pending anon=${current.id}');
    }
    try {
      await CertiliaService.instance
          .signInWithCertilia(context, anonId: anonId);
      return AuthFlowResult.success;
    } on CertiliaFailure catch (e) {
      log('signInWithCertilia CertiliaFailure: ${e.message}');
      return AuthFlowResult.failure(e.message);
    }
  }

  /// Pošalje magic link + 6-znamenkasti kod na [email] i spremi anon UUID
  /// za migraciju. Sheet zatim vodi korisnika kroz [verifyEmailOtp] (ručni
  /// unos koda) — ili korisnik klikne link iz e-maila.
  Future<AuthFlowResult> sendEmailOtp(String email) async {
    log('AuthService.sendEmailOtp($email)');
    final client = _client();
    if (client == null) {
      return AuthFlowResult.failure('Supabase nije konfiguriran.');
    }
    final currentUser = client.auth.currentUser;
    if (currentUser?.isAnonymous == true && currentUser != null) {
      setLocalStorageString(_anonPendingMigrationKey, currentUser.id);
      log('sendEmailOtp: saved pending anon=${currentUser.id}');
    }
    try {
      await client.auth.signInWithOtp(
        email: email,
        shouldCreateUser: true,
        emailRedirectTo: kIsWeb ? null : 'ai.domovina://auth/callback',
      );
      return AuthFlowResult(AuthFlowStatus.emailSent, email);
    } on sb.AuthException catch (e) {
      log('sendEmailOtp AuthException: ${e.message} (code: ${e.code})');
      return AuthFlowResult.failure(friendlyAuthError(e));
    } catch (e) {
      log('sendEmailOtp unexpected: $e');
      return AuthFlowResult.failure(
          'Slanje e-maila nije uspjelo. Pokušaj ponovo.');
    }
  }

  /// Verificira 6-znamenkasti kod iz e-maila. Po uspjehu sesija stiže preko
  /// onAuthStateChange (permanent user + migracija anon podataka).
  Future<AuthFlowResult> verifyEmailOtp(String email, String code) async {
    log('AuthService.verifyEmailOtp email=$email');
    final client = _client();
    if (client == null) {
      return AuthFlowResult.failure('Supabase nije konfiguriran.');
    }
    try {
      await client.auth.verifyOTP(
        type: sb.OtpType.email,
        email: email,
        token: code,
      );
      return const AuthFlowResult(AuthFlowStatus.success, 'Prijava uspješna.');
    } on sb.AuthException catch (e) {
      log('verifyEmailOtp error: ${e.message} (code: ${e.code})');
      return AuthFlowResult.failure(
          'Kod nije ispravan ili je istekao — provjeri unos ili zatraži novi.');
    } catch (e) {
      log('verifyEmailOtp unexpected: $e');
      return AuthFlowResult.failure('Provjera koda nije uspjela.');
    }
  }

  /// Sve povezane prijavne metode trenutnog usera (za Moj račun ekran).
  /// GoTrue identities (google/apple/email) + certilia iz app_metadata.
  /// Passkey nije GoTrue identity — vidi se kroz PasskeyService.listPasskeys.
  List<AuthProvider> get linkedProviders {
    final u = _client()?.auth.currentUser;
    if (u == null || u.isAnonymous) return const [];
    final providers = <AuthProvider>{};
    for (final identity in u.identities ?? const <sb.UserIdentity>[]) {
      switch (identity.provider) {
        case 'google':
          providers.add(AuthProvider.google);
        case 'apple':
          providers.add(AuthProvider.apple);
        case 'email':
          providers.add(AuthProvider.email);
      }
    }
    // kyc_verified piše samo certilia edge fn — robusnije od 'provider' polja
    // koje GoTrue merge može pregaziti (isti email → Google ostane provider).
    if (u.appMetadata['provider'] == 'certilia' ||
        u.appMetadata['kyc_verified'] == true) {
      providers.add(AuthProvider.certilia);
    }
    return providers.toList();
  }

  /// Trajno briše račun i sve podatke (App Store Guideline 5.1.1(v)).
  /// Edge fn `account-delete` verificira JWT i obriše auth.users red —
  /// FK-ovi s ON DELETE CASCADE čiste platform tablice. Nakon brisanja
  /// lokalna sesija je nevažeća → očisti i nastavi kao novi gost.
  /// Spec: docs/backend-prompts/10-account-management.md.
  Future<AuthFlowResult> deleteAccount() async {
    log('AuthService.deleteAccount');
    final client = _client();
    if (client == null) {
      return AuthFlowResult.failure('Supabase nije konfiguriran.');
    }
    try {
      await client.functions.invoke('account-delete');
      log('AuthService.deleteAccount: backend confirmed');
    } on sb.FunctionException catch (e) {
      log('deleteAccount FunctionException: ${e.status} ${e.details}');
      if (e.status == 404) {
        return AuthFlowResult.failure(
            'Brisanje računa kroz aplikaciju još nije dostupno. '
            'Pošalji zahtjev na privacy@italk.hr i izbrisat ćemo ga ručno.');
      }
      return AuthFlowResult.failure(
          'Brisanje računa nije uspjelo (${e.status}). Pokušaj ponovo.');
    } catch (e) {
      log('deleteAccount unexpected: $e');
      return AuthFlowResult.failure(
          'Brisanje računa nije uspjelo. Pokušaj ponovo.');
    }

    try {
      await client.auth.signOut();
    } catch (e) {
      // Sesija je možda već server-side mrtva — lokalni cleanup je dovoljan.
      log('deleteAccount signOut: $e');
    }
    try {
      await client.auth.signInAnonymously();
    } catch (e) {
      log('deleteAccount: anon re-signin failed — $e');
    }
    return const AuthFlowResult(
        AuthFlowStatus.success, 'Račun je trajno izbrisan.');
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

  Future<String?> _promptForEmail(BuildContext context, String? prefill) {
    return showAuthInputDialog(
      context,
      title: 'Tvoj e-mail',
      message: 'Pošaljemo ti link i 6-znamenkasti kod za prijavu.',
      hint: 'ime@primjer.com',
      icon: Icons.alternate_email,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      confirmLabel: 'Pošalji',
    );
  }

  /// Prikaži SnackBar preko GLOBALNOG ScaffoldMessenger key-a (ne preko
  /// context-a) — feedback radi i kad je sheet/dialog već zatvoren pa je
  /// proslijeđeni context unmountan. [context] se zadržava radi potpisa.
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
