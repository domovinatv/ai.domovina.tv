# 07 — Flutter swap mocks → real Supabase (v3)

> **Cilj:** kad je backend potpuno spreman, zamijeni mock implementacije u `lib/services/*` za prave Supabase pozive. UI ostaje identičan (svi widgeti pozivaju iste public metode).
>
> **Preduvjet:** koraci 01–06 izvršeni i smoke-testirani.
>
> **v3 napomene:**
> - `profiles` više nema `email` ni `is_anonymous` mirror — koristi `Supabase.instance.client.auth.currentUser.email` (iz `auth.users`).
> - `watch_progress` upsert mora uključiti `episode_title` + `episode_thumbnail_url` (denorm cache).
> - `Continue watching` carousel pita view `domovina_ai.v_continue_watching`, ne raw tablicu.

---

## Korak 1 — Dodaj dependency

```yaml
# pubspec.yaml
dependencies:
  supabase_flutter: ^2.5.0
  passkeys: ^2.0.0           # za WebAuthn integration
  flutter_dotenv: ^5.1.0     # ili build-time --dart-define
```

```bash
flutter pub get
```

## Korak 2 — Env vars

Cloudflare Pages build env vars (već postavljeni iz 05):
```
SUPABASE_URL=https://api.domovina.ai
SUPABASE_ANON_KEY=<anon JWT>
```

Local dev: `.env` u root-u (gitignored), učitati kroz dotenv ILI koristiti `--dart-define`:

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://api.domovina.ai \
  --dart-define=SUPABASE_ANON_KEY=...
```

`scripts/deploy.sh` mora prosljediti env vars u build (`flutter build web --dart-define=...`).

## Korak 3 — Inicijalizacija u `main.dart`

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnon = String.fromEnvironment('SUPABASE_ANON_KEY');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ...
  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnon,
    debug: false,
  );

  // Sign in anonimno ako nema sesije
  if (Supabase.instance.client.auth.currentUser == null) {
    await Supabase.instance.client.auth.signInAnonymously();
  }

  runApp(const DominovinaApp());
}
```

## Korak 4 — Swap servisa

Svaki service file ima `// MOCK:` komentar gdje je mock; zamijeni s pravim pozivom.

### `lib/services/auth_service.dart`

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService extends ChangeNotifier {
  AuthService() {
    // Listen na auth state promjene
    Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      notifyListeners();
    });
  }

  User? get currentUser => Supabase.instance.client.auth.currentUser;
  bool get isAnonymous => currentUser?.isAnonymous ?? true;
  bool get isSignedIn => currentUser != null && !isAnonymous;

  String? get displayName =>
      currentUser?.userMetadata?['name'] as String?
      ?? currentUser?.email;

  Future<void> linkWithGoogle() async {
    await Supabase.instance.client.auth.linkIdentity(OAuthProvider.google);
  }

  Future<void> linkWithApple() async {
    await Supabase.instance.client.auth.linkIdentity(OAuthProvider.apple);
  }

  Future<void> linkWithEmailOtp(String email) async {
    await Supabase.instance.client.auth.signInWithOtp(
      email: email,
      shouldCreateUser: false, // već imamo anonymous user — link, ne create
    );
  }

  Future<void> verifyEmailOtp(String email, String code) async {
    await Supabase.instance.client.auth.verifyOTP(
      email: email,
      token: code,
      type: OtpType.email,
    );
  }

  Future<void> linkWithPasskey() async {
    // Koristi `passkeys` package + custom endpoint
    // (vidi 05-auth-providers.md §Passkey)
    final response = await http.post(
      Uri.parse('https://api.domovina.ai/passkey/register/start'),
      headers: {'Authorization': 'Bearer ${currentUser!.id}'},
    );
    // ... WebAuthn flow ...
  }

  Future<void> signOut() => Supabase.instance.client.auth.signOut();
}
```

### `lib/services/watch_progress_service.dart`

```dart
class WatchProgressService {
  final _client = Supabase.instance.client;

  // OSTAVI localStorage kao backup cache za anonimne (offline-first).
  // Logged-in: piši i u localStorage I u Supabase, ali Supabase je source of truth.

  Future<void> saveProgress({
    required String episodeId,
    required int positionSeconds,
    required int durationSeconds,
    required String channelId,
    required String episodeTitle,        // v3 denorm
    required String? episodeThumbnailUrl, // v3 denorm
  }) async {
    // 1. Uvijek piši lokalno (offline-safe)
    _saveLocal(episodeId, positionSeconds, durationSeconds);

    // 2. Ako je user signed-in (ne anonymous), upsert u Supabase
    final user = _client.auth.currentUser;
    if (user != null && !user.isAnonymous) {
      try {
        await _client.schema('domovina_ai').from('watch_progress').upsert({
          'user_id': user.id,
          'episode_id': episodeId,
          'channel_id': channelId,
          'position_seconds': positionSeconds,
          'duration_seconds': durationSeconds,
          'episode_title': episodeTitle,                 // v3
          'episode_thumbnail_url': episodeThumbnailUrl,  // v3
          'last_watched_at': DateTime.now().toIso8601String(),
          'last_device': _detectDevice(),
        }, onConflict: 'user_id,episode_id');
      } catch (e) {
        log('watch_progress upsert failed (offline?): $e');
      }
    }
  }

  Future<List<WatchProgress>> continueWatching() async {
    final user = _client.auth.currentUser;
    if (user == null || user.isAnonymous) {
      return _loadLocal();
    }
    // v3 — pita view koji već filtrira (not completed AND position > 30s)
    final rows = await _client
        .schema('domovina_ai')
        .from('v_continue_watching')
        .select()
        .limit(20);
    return rows.map((r) => WatchProgress.fromJson(r)).toList();
  }
}
```

### `lib/services/favorites_service.dart`

```dart
Future<void> toggle(String episodeId) async {
  final user = _client.auth.currentUser;
  final activeAccountId = await _activeAccountId();

  if (user == null || user.isAnonymous) {
    // Lokalno only
    return _toggleLocal(episodeId);
  }

  final exists = await _client
      .schema('domovina_ai')
      .from('favorites')
      .select('episode_id')
      .eq('owner_id', activeAccountId)
      .eq('episode_id', episodeId)
      .maybeSingle();

  if (exists != null) {
    await _client.schema('domovina_ai').from('favorites').delete()
      .eq('owner_id', activeAccountId)
      .eq('episode_id', episodeId);
  } else {
    await _client.schema('domovina_ai').from('favorites').insert({
      'owner_id': activeAccountId,
      'episode_id': episodeId,
      'created_by': user.id,
    });
  }
}
```

### `lib/services/handoff_service.dart`

```dart
Future<String> createCode() async {
  final result = await _client
      .schema('domovina_ai')
      .rpc('create_handoff_token');
  return result as String;
}

Future<void> consumeCode(String code) async {
  final response = await http.post(
    Uri.parse('https://api.domovina.ai/handoff/consume'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'code': code, 'device': _detectDevice()}),
  );
  if (response.statusCode != 200) {
    throw Exception('Invalid or expired code');
  }
  final body = jsonDecode(response.body);
  // Otvori action_link da završi sign-in
  final url = body['action_link'] as String;
  // Web: window.location.replace(url) — GoTrue redirect završi flow
  // Native: WebView / launchUrl + listen na deeplink callback
}
```

### `lib/services/onboarding_state.dart`

```dart
Future<void> markShown(String momentId) async {
  // localStorage uvijek (za anonymous offline-first)
  _localMarkShown(momentId);

  // Telemetry — može i za anonymous, RLS dopušta user_id = auth.uid()
  final user = _client.auth.currentUser;
  if (user != null) {
    try {
      await _client.schema('domovina_ai').from('onboarding_events').insert({
        'user_id': user.id,
        'event': 'moment_shown',
        'moment_id': momentId,
      });
    } catch (_) { /* telemetry je best-effort */ }
  }
}
```

### Napomena za PII queries (v3 princip 1)

Ako negdje u Flutter kodu trebaš user-ov email:

```dart
// ✅ ISPRAVNO — iz auth session-a (auth.users je sole PII location)
final email = Supabase.instance.client.auth.currentUser?.email;

// ❌ KRIVO — profiles tablica više nema email mirror u v3
// final prof = await client.from('profiles').select('email')...
```

## Korak 5 — Realtime cross-device sync

```dart
// EpisodeScreen / EpisodeSimpleScreen
final user = Supabase.instance.client.auth.currentUser;
if (user != null && !user.isAnonymous) {
  _realtimeSub = Supabase.instance.client
      .channel('user-state-${user.id}')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'domovina_ai',
        table: 'watch_progress',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: user.id,
        ),
        callback: (payload) {
          final updatedEpisode = payload.newRecord['episode_id'];
          final updatedDevice = payload.newRecord['last_device'];
          if (updatedEpisode == widget.youtubeId && updatedDevice != _myDevice) {
            // Drugi uređaj pomaknuo poziciju → seek
            _player.seek(Duration(seconds: payload.newRecord['position_seconds']));
          }
        },
      )
      .subscribe();
}
```

## Korak 6 — Migration cleanup

Nakon swap-a, mock data u localStorage treba migrirati u Supabase za usere koji se prvi put loginiraju:

```dart
// auth_service.dart — nakon successful linkIdentity:
await _migrateLocalToSupabase();

Future<void> _migrateLocalToSupabase() async {
  final progress = _loadLocalProgress();
  if (progress.isEmpty) return;

  await _client.schema('domovina_ai').from('watch_progress').upsert(
    progress.map((p) => {...p, 'user_id': currentUser!.id}).toList(),
  );

  final favorites = _loadLocalFavorites();
  if (favorites.isNotEmpty) {
    final activeAccountId = await _activeAccountId();
    await _client.schema('domovina_ai').from('favorites').upsert(
      favorites.map((f) => {
        'owner_id': activeAccountId,
        'episode_id': f,
        'created_by': currentUser!.id,
      }).toList(),
    );
  }
}
```

## Korak 7 — Smoke test cijelog flow-a

```
1. Otvori app u incognito → anonymous session se kreira
2. Pusti episode 30s → watch_progress lokalno (provjeri u DevTools localStorage)
3. M2 sheet → klik Google → OAuth flow → vraćeno na app
4. handle_user_promoted trigger okida → personal account + slug → migrate trigger
5. localStorage podaci sad i u Supabase tablicama
6. Otvori isti link u drugom browseru → loginaj se istim Google → vidi continue watching
7. M4 handoff → kreiraj kod na desktopu → unesi na mobitelu → session se prebaci
```

## Korak 8 — Skini mock fallback-e iz koda

Nakon što real backend radi, `Future.delayed(Duration(milliseconds: 600))` simulacije u mock fileovima zamijeni za prave async pozive (već gore). Snackbar uspjeha postaje "Uspješno prijavljen kao X" umjesto "Mock: ...".

---

## Done

Cijeli auth flow je live. Sljedeći refactor: napraviti `domovina_ai_v_continue_watching` view, optimizirati realtime channelove, dodati org switcher (Faze 7-9 iz auth plana).
