# Supabase Implementation Guide — DOMOVINA.ai

Tehnička analiza DOMOVINA backenda naspram **Lovable Supabase best practices** — provjerenih obrazaca za React + Supabase monorepo (migration-first workflow, SECURITY DEFINER RLS helpers, per-role grants, queue-based email infra, itd.).

Dva repozitorija u igri:

| Repo | Putanja | Uloga |
|------|---------|-------|
| **domovina-api** | `/Users/ms/git/domovinatv/domovina-api` | **Backend** — self-hosted Supabase as code (migracije, RLS, RPC, deploy scripts, Cloudflare Tunnel, Coolify) |
| **domovina.ai** | `/Users/ms/git/domovinatv/domovina.ai` | **Frontend** — Flutter client (web/mobile/TV), consumira backend preko `api.domovina.ai` |

> **Referentni standard:** ovaj dokument mjeri DOMOVINA backend naspram Lovable Supabase best practices — kanonskih obrazaca za React + Supabase monorepo aplikacije.

> **Ključna arhitektonska razlika:** Lovable best-practice obrazac je monorepo (jedna app + jedna baza). DOMOVINA je **1 backend → N frontends** (`domovina.ai`, `domovina.energy`, `domovina.tv` dijele isti Supabase preko Kong gateway-a). Zato je backend **odvojen repo** (`domovina-api`) — to je namjerna, ispravna odluka, ne nedostatak. Sva schema/RLS/RPC logika živi u `domovina-api`, a Flutter samo poziva.

---

## 0. Executive summary

### Headline nalaz: backend je zreliji nego što se mislilo

Prva iteracija ovog dokumenta pretpostavila je da migracije ne postoje (gledala samo frontend repo). **Krivo.** Backend repo `domovina-api` **već prati gotovo sve Lovable Supabase best practices**:

- ✅ Migration-first workflow — 7 `.sql` migracija, `YYYYMMDDhhmmss_<area>_<what>` naming, immutable, tracking u `supabase_migrations.schema_migrations`
- ✅ SECURITY DEFINER RLS helpers (`is_account_member()`, `has_role_on_account()`, `log_event()`) **sa `set search_path = ''`** (injection-safe)
- ✅ `(select auth.uid())` InitPlan optimizacija u svim policy-jima
- ✅ Soft-delete (`deleted_at IS NULL` posvuda), immutable slug trigger, append-only `activity_events`
- ✅ Per-role grants migracija (anon/authenticated/service_role)
- ✅ `config.toml`, deploy scripts s transaction-safe apply + pre-migration backup, offline secrets generation
- ✅ Handoff RPC-ovi postoje (`create_handoff_token()` vraća `jsonb {code, expires_at}`, `consume_handoff_token()` s `FOR UPDATE SKIP LOCKED`)
- ✅ Cloudflare Tunnel + Zero Trust Access + WAF, Coolify automation, cron backup

Backend je **production-ready za MVP**. Pravi posao nije "izgraditi backend od nule" — nego (1) popraviti **contract mismatch-eve** između frontenda i backenda, (2) dovršiti par planiranih komada (Edge Function, anon-migracija, pg_cron), (3) urediti **frontend repo strukturu** + type safety.

### 🔴 KRITIČNO — Frontend ↔ Backend contract mismatch-evi

Ovo su nalazi koji **trenutno lome funkcionalnost** ili će je slomiti čim se backend deploya kako je konfiguriran. Detalji u §2.

| # | Mismatch | Frontend pretpostavlja | Backend stvarno | Posljedica |
|---|----------|------------------------|-----------------|-----------|
| **M1** | **Anonymous auth** | `main.dart` zove `signInAnonymously()` | `ENABLE_ANONYMOUS_USERS=false` | **Anon login pada** → cijeli offline-first flow ne radi protiv produkcije |
| **M2** | **`domovina_ai` schema exposure** | servisi zovu `.schema('domovina_ai').from(...)` | `PGRST_DB_SCHEMAS=public,storage,graphql_public` — **`domovina_ai` NIJE exposan** | **Sve watch_progress/favorites/handoff REST query-je vraćaju 404/PGRST106** |
| **M3** | **`migrate_anon_data()` RPC** | `auth_service.dart:178` ga zove | **Ne postoji** u 7 migracija | Anon→permaneti gube watch_progress (frontend ima PGRST202 fallback, ali feature je broken) |
| **M4** | **`consume_handoff_token()` poziv** | `handoff_service.dart` ga zove kao RPC fallback | RPC ima `revoke execute ... from authenticated` — **samo service_role smije** | RPC fallback baca `permission denied`; jedini ispravan put je Edge Function koja **ne postoji** |
| **M5** | **`watch_progress.owner_id`** | guide §3/§5 (prošla verzija) pisao `owner_id` + `personal_account_id_for()` | Backend tablica koristi **`user_id`** (FK na profiles), ne owner_id/account model | Modeli i RLS pretpostavke se ne poklapaju — favorites koriste `owner_id` (account), watch_progress koristi `user_id` (profile) |
| **M6** | **`favorites` za anon** | frontend gate-a anon favorites lokalno | Backend RLS: `is_account_member(owner_id)` — treba personal account | OK dizajn, ali ovisi o M1/M3 (anon user nema account dok se ne promovira) |

### Što frontend (domovina.ai) već ima (DONE)

- `supabase_flutter ^2.5.0` u `lib/main.dart`
- Service singletons: `AuthService`, `WatchProgressService`, `FavoritesService`, `HandoffService`
- Google/Apple/email magic link wired; dual-write (localStorage + remote)
- Graceful degradation kad Supabase nije dostupan

### Što fali (po repu)

**Backend (`domovina-api`):**

| # | Gap | Status |
|---|-----|--------|
| B1 | `migrate_anon_data()` RPC | Ne postoji — treba migracija |
| B2 | `ENABLE_ANONYMOUS_USERS` | `false` — treba odluka (vidi §2 M1) |
| B3 | `domovina_ai` u `PGRST_DB_SCHEMAS` | Nije exposan (vidi §2 M2) |
| B4 | Edge Function `handoff-consume` | Planiran M5, ne postoji |
| B5 | `pg_cron` za `cleanup_expired_handoffs()` | Komentiran u migraciji, nije aktiviran |
| B6 | Generated types export | Nema `supabase gen types` artefakta za frontend |
| B7 | CI/CD za migracije | Manualan (`db-migrate.sh`); nema GitHub Action / migration tests |
| B8 | Queue-based email (pgmq + DLQ + send_log) | Nema — GoTrue direkt na Resend SMTP |
| B9 | Google OAuth Cloud Console | TODO.md — pending |

**Frontend (`domovina.ai`):**

| # | Gap | Status |
|---|-----|--------|
| F1 | Repo struktura — `client.schema()` raspršen po servisima | Treba `lib/data/` sloj (vidi §4) |
| F2 | Generated/typed modeli | Hand-written; treba `freezed` (vidi §5) |
| F3 | `OnboardingState` čist localStorage | Nema upisa u `domovina_ai.onboarding_events` |
| F4 | Lokalni Supabase za dev | Testira protiv produkcije |
| F5 | Auth hydration nije paralelan | Sekvencijalni fetch profile/account/memberships |
| F6 | Error poruke nelokalizirane | Raw `AuthException` |
| F7 | Realtime sync | 5s debounced upsert, nema live cross-device |

### Sažeti plan

```
Phase 0: Contract fixes    (1-2 dana)  → §2   ★ NAJVIŠI PRIORITET (lomi funkcionalnost)
Phase 1: Backend dovršetak (2-3 dana)  → §3
Phase 2: Frontend struktura(2-3 dana)  → §4
Phase 3: Type safety       (1-2 dana)  → §5   ★ cross-repo type contract
Phase 4: Auth hardening    (1-2 dana)  → §6
Phase 5: Realtime          (1-2 dana)  → §7
Phase 6: CI/CD             (1-2 dana)  → §8
Phase 7: Email infra       (3-5 dana)  → §9   (odgodi dok ne šalješ emaile)
Phase 8: Observability     (1-2 dana)  → §10
```

---

## 1. Backend repo (domovina-api) — snapshot trenutnog stanja

Da bi frontend rad imao smisla, evo što backend **stvarno** ima (provjereno čitanjem svih 7 migracija).

### 1.1 Schema (provjereno)

**`public` schema** — identitet + org model:
- `profiles` (PK = `auth.users.id`, locale/timezone/notification_prefs/onboarding_completed_at, soft-delete)
- `accounts` (unified user+org, `citext` slug s `slug_format` CHECK, `search_text` generated GIN trgm, `visibility_level` enum, soft-delete)
- `accounts_memberships` (N:M, `member_role` enum owner/admin/member, PK `(account_id, user_id)`)
- `activity_events` (append-only, `bigserial`, event_type tekst, jsonb payload)

**`domovina_ai` schema** — watch state + MVP:
- `watch_progress` — **PK `(user_id, episode_id)`**, `position_seconds`/`duration_seconds`, `percent_complete` i `completed` su **generated columns**, denorm `episode_title`/`episode_thumbnail_url`, `last_device` enum
- `watch_sessions` — append-only audit (pause_count, seek_count, completed_normally)
- `favorites` — **PK `(owner_id, episode_id)`** gdje `owner_id` → `accounts.id` (per-account/org!), `created_by` → profiles
- `handoff_tokens` — PK `code` (6-digit CHECK regex), 5-min expiry, `consumed_at`/`consumed_by_device`
- `onboarding_events` — telemetrija (event, moment_id, provider, jsonb properties)
- **View `v_continue_watching`** — `not completed and position_seconds > 30 order by last_watched_at desc`

> **Pažnja na asimetriju vlasništva:** `watch_progress` je vezan na **`user_id`** (profile, per-user), a `favorites` na **`owner_id`** (account, može biti org). To je namjeran dizajn — progress je privatan, favoriti se dijele među članovima accounta. Frontend modeli moraju to poštovati (vidi §5).

### 1.2 Triggers (provjereno)

- `on_auth_user_created` (AFTER INSERT auth.users) → `handle_new_user()`: uvijek kreira profile; ako **nije anonymous**, kreira personal account + slug + `member.joined` event
- `on_auth_user_promoted` (AFTER UPDATE OF is_anonymous) → `handle_user_promoted()`: okida na `is_anonymous true→false`, kreira personal account idempotentno
- `trg_guard_slug_immutable` (BEFORE UPDATE accounts) → odbija slug promjenu
- `trg_check_membership_is_org` → membership ne smije na personal account
- `trg_log_membership`, `trg_log_completion` → auto activity events
- `touch_updated_at()` triggeri za `updated_at`

> **Bitno za M3:** backend već ima `handle_user_promoted()` koji kreira personal account na promociju. Ali **ne migrira watch_progress podatke** s anon user_id na novi — to je upravo ono što `migrate_anon_data()` treba raditi (vidi §3.1).

### 1.3 RPC (provjereno)

- `domovina_ai.create_handoff_token()` → `jsonb {code, expires_at}`, `grant ... to authenticated` ✅
- `domovina_ai.consume_handoff_token(p_code, p_device)` → `jsonb {user_id, success}`, `FOR UPDATE SKIP LOCKED`, **`revoke ... from authenticated`** (service_role only) ⚠️
- `domovina_ai.cleanup_expired_handoffs()` → int, pozива se iz pg_cron (još neaktiviran)
- `public.generate_unique_slug()`, `public.log_event()` — helpers

### 1.4 Auth & infra config (provjereno)

- `ENABLE_EMAIL_SIGNUP=true`, `ENABLE_EMAIL_AUTOCONFIRM=false`, magic link live (Resend SMTP)
- `ENABLE_ANONYMOUS_USERS=false` ⚠️ (vidi M1)
- `PGRST_DB_SCHEMAS=public,storage,graphql_public` ⚠️ (vidi M2 — `domovina_ai` fali)
- Google OAuth — dokumentiran, Cloud Console pending
- `additional_redirect_urls` uključuje sve domene + `localhost:3000/5173` (ali **ne** `ai.domovina://` deep link — vidi §6)
- Deploy: `scripts/db-migrate.sh` (backup → transaction apply → tracking insert), `db-status.sh`, `db-dump.sh`, offline `build-coolify-env.sh`
- Cloudflare Tunnel + Zero Trust Access (Studio) + WAF (block bare root)

---

## 2. Phase 0 — Contract fixes (NAJVIŠI PRIORITET)

Ovo se mora riješiti prije svega ostalog jer trenutno lomi runtime. Svaki fix navodi **u kojem repu** se radi.

### M1 — Anonymous auth: `false` na backendu vs `signInAnonymously()` na frontendu

**Problem:** `domovina.ai/lib/main.dart` zove `Supabase.instance.client.auth.signInAnonymously()` da omogući offline-first watch progress. Backend ima `ENABLE_ANONYMOUS_USERS=false` → poziv vraća `422 anonymous_provider_disabled`.

**Odluka — dvije opcije:**

**Opcija A (preporučeno) — uključi anonymous na backendu**
- Repo: `domovina-api`
- U Coolify env (preko `build-coolify-env.sh` ili Coolify UI): `ENABLE_ANONYMOUS_USERS=true`
- Backend već ima `handle_new_user()` koji NE kreira account za anon (ispravno) i `handle_user_promoted()` koji kreira account na promociju — **dizajn je već spreman za anon**. Samo flag treba upaliti.
- Dodaj rate-limit na anon signup (Cloudflare WAF na `/auth/v1/signup`) jer anon korisnici mogu napuhati `auth.users`.
- Dodaj pg_cron cleanup za stale anon korisnike (npr. anon bez aktivnosti > 90 dana, bez promocije).

**Opcija B — makni anon iz frontenda, koristi client-side UUID**
- Repo: `domovina.ai`
- Watch progress ostaje lokalan dok se korisnik ne uloguje; nema remote write za anon.
- Manje korisno (gubi cross-device prije logina), ali nula backend rizika.

> **Preporuka: Opcija A.** Backend dizajn (`handle_user_promoted` + anon-aware `handle_new_user`) je očito napravljen s anon-om na umu — flag je vjerojatno slučajno ostao `false`. Provjeri zašto je postavljen na false prije paljenja.

### M2 — `domovina_ai` nije exposan kroz PostgREST

**Problem:** Frontend servisi koriste `client.schema('domovina_ai').from('watch_progress')`. PostgREST izlaže schema samo ako je u `PGRST_DB_SCHEMAS`. Trenutno: `public,storage,graphql_public`. **`domovina_ai` fali** → svaki REST poziv na te tablice vraća `PGRST106 (schema not in search path)` ili 404.

**Fix:**
- Repo: `domovina-api`
- Coolify env: `PGRST_DB_SCHEMAS=public,domovina_ai,storage,graphql_public`
- Restart PostgREST servisa (Coolify Deploy ili `scripts/coolify-restart.sh`)
- Verifikacija: `curl -H "Accept-Profile: domovina_ai" -H "apikey: $ANON" https://api.domovina.ai/rest/v1/watch_progress?limit=1` — mora vratiti `[]` ili rows, ne PGRST106
- Provjeri da grants migracija (`20260520120600`) već daje `usage` na schema `domovina_ai` za `authenticated`/`anon` (jest — potvrđeno).

> Memory zapis `db_schema_split.md` već kaže da `PGRST_DB_SCHEMAS` mora biti `public,domovina_ai`. Ovo je regresija/propust u trenutnom backend env-u — provjeri Coolify env vs `.env.example` (`.env.example` ima samo `public,storage,graphql_public`).

### M3 — `migrate_anon_data()` RPC ne postoji

**Problem:** `auth_service.dart:178` zove `client.schema('domovina_ai').rpc('migrate_anon_data', {'p_anon_id': ...})`. Funkcija ne postoji → PGRST202. Frontend ima graceful fallback ("ne pokušavaj ponovo"), ali korisnik gubi watch_progress kad anon→permanent.

**Fix:** Nova migracija u `domovina-api`. Vidi gotov SQL u §3.1. Mora poštovati backend model (`watch_progress.user_id`, ne owner_id).

### M4 — `consume_handoff_token()` revoked za authenticated

**Problem:** `handoff_service.dart` pokušava (1) Edge Function `/handoff/consume` (404, ne postoji), pa (2) RPC fallback `consume_handoff_token` koji je `revoke ... from authenticated` → `permission denied`. Oba puta failaju; ostaje samo UI-only `forceSignIn()` koji ne mijenja stvarnu sesiju.

**Fix:** Implementiraj Edge Function `handoff-consume` u `domovina-api` (§3.2). To je jedini ispravan put jer consume mora (a) raditi kao service_role, (b) generirati session bridge (magic link / token). RPC ostaje service_role-only (ispravno — security).

### M5 — Model vlasništva: `user_id` vs `owner_id`

**Problem:** Raniji draft ovog guide-a pretpostavio `watch_progress.owner_id` + `personal_account_id_for()`. Backend stvarno koristi `watch_progress.user_id` (FK profiles). Favorites koriste `owner_id` (FK accounts).

**Fix:** Frontend modeli i repo pozivi (§5) moraju koristiti točne kolone:
- `watch_progress` → `user_id = auth.uid()` (profile-level, privatno)
- `favorites` → `owner_id = personal_account_id` (account-level, dijeljivo)
- `handoff_tokens` → `user_id`
- `onboarding_events` → `user_id`

### M6 — Favorites za anon korisnike

Backend RLS na favorites traži `is_account_member(owner_id)`, što anon nema (anon nema account dok se ne promovira). Frontend već gate-a anon favorites na localStorage — **ispravno**. Nakon promocije (M1+M3), backfill ide kroz migraciju podataka. Nema dodatnog rada osim verifikacije nakon M1/M3.

### Acceptance kriterij Phase 0

- `signInAnonymously()` uspijeva protiv produkcije (M1)
- `curl` s `Accept-Profile: domovina_ai` vraća podatke (M2)
- Anon→Google promocija prebacuje watch_progress (M3)
- Handoff kod s telefona otvara sesiju na TV-u kroz Edge Function (M4)
- Frontend modeli koriste točne FK kolone (M5)

---

## 3. Phase 1 — Backend dovršetak (`domovina-api`)

### 3.1 Migracija: `migrate_anon_data()` RPC

Nova migracija `supabase/migrations/<ts>_anon_data_migration_rpc.sql`. Poštuje backend model (`watch_progress.user_id`).

```sql
-- Plan: docs/auth-and-database-plan-v3.md; rješava M3
-- Anon user_id → permanent user_id transfer za watch_progress + watch_sessions
begin;

create or replace function domovina_ai.migrate_anon_data(p_anon_id uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_moved_progress int := 0;
  v_moved_sessions int := 0;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  -- caller mora biti promovirani (ne anon) user
  if coalesce((select auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'caller_still_anonymous' using errcode = '42501';
  end if;

  -- watch_progress: prebaci anon redove koji NE konfliktiraju s postojećima
  update domovina_ai.watch_progress wp
     set user_id = v_uid
   where wp.user_id = p_anon_id
     and not exists (
       select 1 from domovina_ai.watch_progress wp2
        where wp2.user_id = v_uid and wp2.episode_id = wp.episode_id
     );
  get diagnostics v_moved_progress = row_count;

  -- konflikti: permanent verzija pobjeđuje, briši anon duplikate
  delete from domovina_ai.watch_progress where user_id = p_anon_id;

  -- watch_sessions: append-only, samo re-owner
  update domovina_ai.watch_sessions
     set user_id = v_uid
   where user_id = p_anon_id;
  get diagnostics v_moved_sessions = row_count;

  return jsonb_build_object(
    'moved_watch_progress', v_moved_progress,
    'moved_watch_sessions', v_moved_sessions,
    'new_user_id', v_uid
  );
end;
$$;

grant execute on function domovina_ai.migrate_anon_data(uuid) to authenticated;

commit;
```

Deploy: `./scripts/db-migrate.sh` (backup + transaction apply).

### 3.2 Edge Function: `handoff-consume`

Backend trenutno nema `supabase/functions/`. Kreiraj prvu, slijedeći standardnu Lovable Edge Function strukturu (`_shared/`, `verify_jwt` per function).

```
domovina-api/supabase/functions/
├── _shared/
│   └── cors.ts
└── handoff-consume/
    └── index.ts
```

`handoff-consume/index.ts`:

```typescript
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

const URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  // caller (može biti anon ili authenticated) — samo da znamo tko traži
  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(URL, ANON, { global: { headers: { Authorization: authHeader } } });
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return json({ error: "not_authenticated" }, 401);

  const { code, device } = await req.json().catch(() => ({}));
  if (!/^\d{6}$/.test(code ?? "")) return json({ error: "invalid_code_format" }, 400);

  const admin = createClient(URL, SERVICE, { auth: { persistSession: false } });

  // service_role smije zvati revoked RPC
  const { data, error } = await admin
    .schema("domovina_ai")
    .rpc("consume_handoff_token", { p_code: code, p_device: device ?? null });

  if (error) return json({ error: error.message }, 400);

  const targetUserId = (data as any).user_id as string;

  // session bridge: generiraj magic link za target usera
  const { data: { user: target } } = await admin.auth.admin.getUserById(targetUserId);
  const { data: link } = await admin.auth.admin.generateLink({
    type: "magiclink",
    email: target?.email ?? "",
    options: { redirectTo: "ai.domovina://auth/callback" },
  });

  // audit
  await admin.from("activity_events").insert({
    actor_user_id: user.id,
    event_type: "handoff.consumed",
    payload: { code_user: targetUserId, device },
  });

  return json({ action_link: link?.properties?.action_link, user_id: targetUserId }, 200);

  function json(body: unknown, status: number) {
    return new Response(JSON.stringify(body), {
      status, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
```

`config.toml` dodatak:
```toml
[functions.handoff-consume]
verify_jwt = false   # interno verificiramo authHeader
```

Deploy: `supabase functions deploy handoff-consume --no-verify-jwt` (treba Supabase CLI access na self-hosted; alternativno deploy kroz Coolify ako Edge Runtime container postoji).

> **Provjeri:** ima li Coolify Supabase template `edge-runtime` (functions) container? Ako ne, treba ga dodati u docker-compose ili ostaviti consume kao backend-side proces. Ovo je otvoreno pitanje (§11).

### 3.3 pg_cron: aktiviraj cleanup

Migracija `<ts>_enable_pgcron_cleanup.sql`:

```sql
begin;
create extension if not exists pg_cron;

select cron.schedule(
  'cleanup-handoff-tokens',
  '*/15 * * * *',
  $$ select domovina_ai.cleanup_expired_handoffs() $$
);

-- ako se uključi anon (M1), dodaj i stale-anon cleanup:
-- select cron.schedule('cleanup-stale-anon', '0 3 * * *',
--   $$ ... delete anon users bez aktivnosti > 90 dana ... $$);
commit;
```

> Provjeri je li `pg_cron` dostupan u Coolify Supabase image-u (komentari u postojećoj migraciji sugeriraju da možda nije). Ako nije, cleanup ide kao external cron koji zove RPC preko `db-psql.sh`.

### 3.4 Deep links u redirect URLs

Backend `additional_redirect_urls` nema `ai.domovina://auth/callback`. Mobile/TV OAuth callback neće raditi bez toga.

- Repo: `domovina-api`, `config.toml` + Coolify GoTrue env `GOTRUE_URI_ALLOW_LIST`
- Dodaj: `ai.domovina://auth/callback`

### Acceptance kriterij

- `migrate_anon_data()` u `db-status.sh` kao applied
- `handoff-consume` vraća `action_link` na valjan kod
- `cron.job` tablica ima `cleanup-handoff-tokens`
- Deep link u allow listi

---

## 4. Phase 2 — Frontend repo struktura (`domovina.ai`)

Backend je čist; frontend treba sloj koji centralizira pristup. Trenutno `client.schema('domovina_ai').from(...)` je raspršen po servisima.

### Ciljna struktura

```
lib/
├── data/
│   ├── supabase/
│   │   ├── client.dart        # SupabaseClientProvider (override za testove)
│   │   ├── schemas.dart       # SchemaNames.domovinaAi / .public
│   │   └── tables.dart        # TableNames.* (mora se poklapati s backend migracijama)
│   ├── repositories/
│   │   ├── watch_progress_repo.dart
│   │   ├── favorites_repo.dart
│   │   ├── handoff_repo.dart
│   │   ├── accounts_repo.dart
│   │   └── profiles_repo.dart
│   └── models/                # freezed (§5)
└── services/                  # ChangeNotifier state, deleguje na repos
```

### `lib/data/supabase/tables.dart` — single source of truth za imena

```dart
class SchemaNames {
  static const String public = 'public';
  static const String domovinaAi = 'domovina_ai';
}

class TableNames {
  // public (backend: core_identity migracija)
  static const String profiles = 'profiles';
  static const String accounts = 'accounts';
  static const String accountsMemberships = 'accounts_memberships';
  static const String activityEvents = 'activity_events';
  // domovina_ai
  static const String watchProgress = 'watch_progress';
  static const String watchSessions = 'watch_sessions';
  static const String favorites = 'favorites';
  static const String handoffTokens = 'handoff_tokens';
  static const String onboardingEvents = 'onboarding_events';
  static const String vContinueWatching = 'v_continue_watching';
}
```

### Repository primjer — poštuje M5 (točne FK kolone)

```dart
// lib/data/repositories/watch_progress_repo.dart  — user_id, NE owner_id
class WatchProgressRepo {
  final _c = SupabaseClientProvider.instance;

  Future<List<WatchProgress>> continueWatching({int limit = 20}) async {
    final rows = await _c
        .schema(SchemaNames.domovinaAi)
        .from(TableNames.vContinueWatching)
        .select()
        .limit(limit);
    return rows.map(WatchProgress.fromJson).toList();
  }

  Future<void> upsert(WatchProgress wp) async {
    // backend PK = (user_id, episode_id); user_id se postavlja iz auth.uid() preko RLS
    await _c
        .schema(SchemaNames.domovinaAi)
        .from(TableNames.watchProgress)
        .upsert(wp.toJson(), onConflict: 'user_id,episode_id');
  }
}
```

```dart
// lib/data/repositories/favorites_repo.dart  — owner_id (account), NE user_id
class FavoritesRepo {
  final _c = SupabaseClientProvider.instance;

  Future<void> add(String ownerAccountId, String episodeId) async {
    await _c
        .schema(SchemaNames.domovinaAi)
        .from(TableNames.favorites)
        .upsert({
          'owner_id': ownerAccountId,
          'episode_id': episodeId,
        }, onConflict: 'owner_id,episode_id');
  }
}
```

### Acceptance kriterij

- Nijedan `.schema(...)` string-literal van `lib/data/`
- Servisi (ChangeNotifier) pozivaju repo metode
- `onConflict` se poklapa s backend PK-ovima (`user_id,episode_id` za progress; `owner_id,episode_id` za favorites)

---

## 5. Phase 3 — Type safety kao cross-repo ugovor

### Problem i strategija

Backend schema živi u `domovina-api`, frontend modeli u `domovina.ai`. Kad backend promijeni kolonu, frontend mora znati. Lovable obrazac to rješava jednim repom + `supabase gen types typescript`. U split arhitekturi treba **eksplicitan ugovor**.

**Preporuka:** Backend generira tipove kao artefakt, frontend ih konzumira ručno preslikane u `freezed`.

### Korak 1 (backend, `domovina-api`) — generiraj tipove kao referencu

```bash
# u domovina-api, dodaj script scripts/gen-types.sh
supabase gen types typescript --db-url "$SUPABASE_DB_URL" \
  --schema public,domovina_ai > docs/generated/database.types.ts
git add docs/generated/database.types.ts && git commit -m "chore: regen db types"
```

Ovaj `.ts` fajl je **schema contract** koji frontend dev čita kad piše Dart modele.

### Korak 2 (frontend, `domovina.ai`) — freezed modeli koji prate backend

```yaml
# pubspec.yaml
dependencies:
  freezed_annotation: ^2.4.4
  json_annotation: ^4.9.0
dev_dependencies:
  build_runner: ^2.4.13
  freezed: ^2.5.7
  json_serializable: ^6.8.0
```

```dart
// lib/data/models/watch_progress.dart — preslikava domovina_ai.watch_progress
@freezed
class WatchProgress with _$WatchProgress {
  const factory WatchProgress({
    required String userId,           // PK dio 1 (NE owner_id — vidi M5)
    required String episodeId,        // PK dio 2
    String? channelId,
    required int positionSeconds,
    required int durationSeconds,
    double? percentComplete,          // generated na backendu — read-only
    bool? completed,                  // generated — read-only
    String? episodeTitle,             // denorm cache
    String? episodeThumbnailUrl,
    @Default(1.0) double playbackRate,
    String? lastDevice,
    DateTime? lastWatchedAt,
  }) = _WatchProgress;

  factory WatchProgress.fromJson(Map<String, dynamic> json) =>
      _$WatchProgressFromJson(json);
}
```

> **Generated kolone** (`percent_complete`, `completed`) se NIKAD ne šalju u upsert (backend ih računa). U `toJson()` ih izostavi ili koristi custom serializer.

### Acceptance kriterij

- `docs/generated/database.types.ts` postoji u backend repu i regenerira se nakon svake migracije
- Frontend `freezed` modeli za top tablice (watch_progress, favorites, account, profile)
- `flutter analyze` čist

---

## 6. Phase 4 — Auth hardening (`domovina.ai`)

### 6.1 Paralelni hydration (Lovable pattern)

Lovable best-practice obrazac radi `Promise.all([member, roles])`. Apliciraj na `auth_service.dart` nakon `_setUser()`:

```dart
Future<void> _hydrateUser(User user) async {
  final r = await Future.wait([
    _profilesRepo.fetch(user.id),
    _accountsRepo.fetchPersonal(user.id),
    _accountsRepo.fetchMemberships(user.id),
  ]);
  _profile = r[0] as Profile?;
  _personalAccount = r[1] as Account?;
  _memberships = r[2] as List<Membership>;
  notifyListeners();
}
```

`personalAccount.id` je `owner_id` za favorites (M5).

### 6.2 Lokalizirani error messages

Centraliziraj u `lib/services/auth_error_translator.dart` — mapiraj backend errcode-ove (`not_authenticated`, `invalid_or_expired_code`, `handoff_code_collision`) na hrvatske poruke.

### 6.3 Onboarding telemetrija (F3)

`OnboardingState` trenutno samo localStorage. Dodaj fire-and-forget upis u `domovina_ai.onboarding_events` (RLS: `user_id = auth.uid()`):

```dart
await SupabaseClientProvider.instance
    .schema(SchemaNames.domovinaAi)
    .from(TableNames.onboardingEvents)
    .insert({'event': 'moment_shown', 'moment_id': 'm1', 'provider': null});
```

### Acceptance kriterij

- Hydration je jedan `Future.wait`
- Onboarding momenti se loggaju u backend
- Auth greške lokalizirane

---

## 7. Phase 5 — Realtime sync (`domovina.ai`)

Backend ima Realtime (Supavisor + RealtimeRLS u Coolify). Frontend trenutno radi 5s debounced upsert bez live sync.

```dart
RealtimeChannel? _ch;
void _subscribe(String userId) {
  _ch?.unsubscribe();
  _ch = SupabaseClientProvider.instance
      .channel('wp-$userId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: SchemaNames.domovinaAi,
        table: TableNames.watchProgress,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id', value: userId,   // M5: user_id
        ),
        callback: (_) => refresh(),
      )
      .subscribe();
}
```

> Backend mora imati `alter publication supabase_realtime add table domovina_ai.watch_progress` (standardni Lovable Realtime pattern). Provjeri/dodaj migraciju u `domovina-api` — trenutno nije u 7 migracija.

### Acceptance kriterij

- Backend publication uključuje watch_progress
- Progress na webu → TV osvježi < 1s
- Subscription cleanup na logout

---

## 8. Phase 6 — CI/CD za migracije (`domovina-api`)

Backend deploya migracije ručno (`db-migrate.sh`). Ni standardni Lovable obrazac nema CI za migracije, ali za multi-frontend backend to je vrijedno.

```yaml
# domovina-api/.github/workflows/db.yml
name: DB
on: { push: { branches: [main], paths: ['supabase/migrations/**'] } }
jobs:
  migrate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: supabase/setup-cli@v1
      - run: supabase db push --db-url ${{ secrets.SUPABASE_DB_URL }}
```

Alternativa bez GH Actions: `db-migrate.sh` već radi posao; dodaj `--dry-run` u pre-commit hook za sanity.

> **Migration tests** (nije dio standardnog Lovable obrasca, ali vrijedi): `supabase test db` s pgTAP — testira RLS politike (anon ne vidi tuđe, authenticated vidi svoje). Posebno korisno za multi-frontend gdje regresija pogađa 3 app-a.

---

## 9. Phase 7 — Email infra (odgodi)

Lovable best-practice email infra je queue-based (pgmq + DLQ + `email_send_log` + `suppressed_emails` + React Email templates + `process-email-queue` cron function). Backend `domovina-api` koristi direkt GoTrue→Resend SMTP.

**Kad implementirati:** tek kad šalješ više od auth emaila (welcome, digest, "nova epizoda"). Za sada Resend SMTP je dovoljan.

**Kad počneš (sve u `domovina-api`):**
1. Provjeri `pgmq` dostupnost u Coolify image-u (vjerojatno treba custom image — nije u trenutnom template-u)
2. Postavi `email_infra` migraciju po Lovable obrascu (pgmq + DLQ + `email_send_log` + `suppressed_emails`)
3. Edge Function `process-email-queue` (cron-triggered) + `email_send_log` audit
4. Croatian templates (gender-aware greeting kroz `_shared/hr-gender.ts` helper, po Lovable obrascu)

---

## 10. Phase 8 — Observability

- `activity_events` već postoji na backendu — frontend treba zvati ga za bitne akcije (`episode.played`, `favorite.added`, `handoff.initiated`)
- Slow query log na Postgresu (`log_min_duration_statement=500`)
- Client errors: `sentry_flutter` u `domovina.ai`
- Uptime: backend već ima `docs/setup-guides/uptime-monitoring.md` (Uptime Kuma + Telegram)

---

## 11. Otvorena pitanja (cross-repo)

1. **Edge Runtime na Coolify** — ima li Supabase deployment `edge-runtime` container? Ako ne, `handoff-consume` (M4) ne može kao Deno function bez dodavanja u docker-compose. Alternativa: lagani backend endpoint.
2. **Zašto je `ENABLE_ANONYMOUS_USERS=false`** — namjerno ili propust? Backend dizajn sugerira da je anon planiran. (M1)
3. **`PGRST_DB_SCHEMAS` desync** — `.env.example` ima `public,storage,graphql_public`, memory kaže da treba `public,domovina_ai`. Što je stvarno na Coolify env-u? (M2)
4. **`pg_cron` dostupnost** u Coolify image-u (§3.3)
5. **Realtime publication** — treba migracija da doda `domovina_ai.watch_progress` u `supabase_realtime` (§7)
6. **GDPR delete** — treba RPC `delete_user_data(user_id)` koja cascade-uje kroz oba schema; soft-delete na accounts već postoji
7. **Backup restore test** — backend ima cron pg_dump; je li restore ikad testiran?

---

## 12. Akcijski redoslijed (cross-repo)

### Tjedan 1 — Contract fixes (lomi funkcionalnost)
1. `domovina-api`: `ENABLE_ANONYMOUS_USERS=true` + verify zašto je bio false (M1)
2. `domovina-api`: `PGRST_DB_SCHEMAS` dodaj `domovina_ai`, restart PostgREST (M2)
3. `domovina-api`: deploy `migrate_anon_data()` migraciju (M3, §3.1)
4. `domovina-api`: dodaj `ai.domovina://auth/callback` u redirect allow list (§3.4)
5. `domovina.ai`: ispravi modele na `user_id`/`owner_id` po backendu (M5)

### Tjedan 2 — Edge + backend dovršetak
6. `domovina-api`: Edge Function `handoff-consume` (M4, §3.2) — ovisno o §11.1
7. `domovina-api`: pg_cron cleanup (§3.3) — ovisno o §11.4
8. `domovina-api`: Realtime publication migracija (§7)
9. `domovina-api`: Google OAuth Cloud Console (B9)

### Tjedan 3 — Frontend struktura + types
10. `domovina.ai`: `lib/data/` sloj (§4)
11. `domovina-api`: `gen-types.sh` → `docs/generated/database.types.ts` (§5)
12. `domovina.ai`: freezed modeli (§5)
13. `domovina.ai`: paralelni hydration + onboarding telemetrija (§6)

### Tjedan 4 — Polish
14. `domovina.ai`: realtime watch_progress (§7)
15. `domovina-api`: CI/CD + migration tests (§8)
16. `domovina.ai`: activity_events instrumentacija + Sentry (§10)

---

## 13. Anti-patterns (potvrđeno da ih backend već izbjegava ✅)

| Anti-pattern | Backend status | Napomena |
|--------------|----------------|----------|
| Inline JOIN u RLS | ✅ izbjegnuto | koristi `is_account_member()` helper |
| Goli `auth.uid()` | ✅ izbjegnuto | svuda `(select auth.uid())` |
| Mutable SECURITY DEFINER search_path | ✅ izbjegnuto | `set search_path = ''` + fully-qualified |
| Hard delete | ✅ izbjegnuto | `deleted_at` soft-delete |
| Service role na klijentu | ✅ | frontend nema service key (grep potvrda potrebna) |
| Mutable slug | ✅ izbjegnuto | `guard_slug_immutable` trigger |
| Schema klikan u Studio | ✅ izbjegnuto | migration-first u `domovina-api` |

**Frontend anti-patterns za izbjeći:**

| Anti-pattern | Umjesto |
|--------------|---------|
| `.schema()` string-literal raspršen | centralizirano u `lib/data/supabase/tables.dart` |
| Hand-written modeli bez ugovora | freezed + backend `database.types.ts` referenca |
| Realtime bez filter klauzule | uvijek `filter: user_id=eq.X` |
| Slanje generated kolona u upsert | izostavi `percent_complete`/`completed` |
| Krivi `onConflict` | poklopi s backend PK (`user_id,episode_id` vs `owner_id,episode_id`) |

---

## 14. Repo-to-repo mapa (gdje što živi)

| Odgovornost | Repo | Lokacija |
|-------------|------|----------|
| Schema, RLS, triggers, RPC | `domovina-api` | `supabase/migrations/` |
| Edge Functions | `domovina-api` | `supabase/functions/` (kreiraj) |
| Deploy, backup, secrets | `domovina-api` | `scripts/` |
| Type contract (generated) | `domovina-api` | `docs/generated/database.types.ts` (kreiraj) |
| Infra (Tunnel, Coolify, Access) | `domovina-api` | `cloudflared/`, `docs/` |
| Supabase client init | `domovina.ai` | `lib/main.dart` → `lib/data/supabase/client.dart` |
| Repository sloj | `domovina.ai` | `lib/data/repositories/` (kreiraj) |
| Dart modeli (freezed) | `domovina.ai` | `lib/data/models/` (kreiraj) |
| State (ChangeNotifier) | `domovina.ai` | `lib/services/` |

---

**Final note:** Backend `domovina-api` je iznenađujuće zreo — arhitektura, RLS, migracije i ops su na razini Lovable Supabase best practices ili iznad (offline secrets, transaction-safe migrate, Cloudflare Zero Trust). Glavni rizik nije backend kvaliteta nego **split-repo desync**: frontend pretpostavke (anon, schema exposure, RPC dostupnost, FK kolone) ne poklapaju se s backend stvarnošću. Phase 0 (§2) rješava te mismatch-eve i otključava sve ostalo. Ne gradi backend iznova — sinkroniziraj ugovor.
