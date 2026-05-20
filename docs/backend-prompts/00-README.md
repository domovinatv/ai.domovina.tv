# Backend prompts — Supabase (self-hosted na Coolify)

Ovi promptovi prate **v3 hibrid**: source-of-truth je `docs/auth-and-database-plan-v3.md` (principi + reducirani MVP scope), plus produžetak za našu stvarnu MVP-feature listu koja v3 ne pokriva (M3 favorites, M4 cross-device handoff, onboarding telemetry).

## Tri arhitekturalna principa (iz v3)

1. **PII isključivo u `auth.users`.** Naše tablice drže FK i non-PII data. Queries koriste `auth.email()` / `(auth.jwt() ->> 'is_anonymous')` umjesto mirror stupaca. GDPR delete = `DELETE FROM auth.users` → `ON DELETE CASCADE`.
2. **Slug je immutable u v1.** Trigger `BEFORE UPDATE` na `accounts` odbija promjenu `slug`. Nema redirect logike. Slug history se može dodati u v2 ako se značajan use case pojavi.
3. **Soft-delete samo na `accounts`.** Sve drugo hard-delete preko `ON DELETE CASCADE`. RLS policies na svim queries za accounts uključuju `AND deleted_at IS NULL`. Cleanup cron periodični hard-delete > 30 dana.

## Što se mijenja v2 → v3 i kako se reflektira u promptovima

| Promjena | Razlog | Gdje |
|---|---|---|
| Drop `apps` + `app_installations` | Schema = app boundary | 01 |
| Drop `role_permissions` + `app_permissions` enum | 3 hardcoded roles ne traže decoupling | 01, 03, 04 |
| Drop `profiles.email`, `profiles.is_anonymous` mirror | Princip 1 (PII) | 01, 03 |
| Add `accounts.search_text` GENERATED + GIN trgm | Sub-ms typeahead | 01 |
| Add `activity_events` tablica + `log_event()` helper | Event sourcing seam (notifications/audit/feed) | 01, 03, 04 |
| Add `accounts.deleted_at` + slug immutable trigger | Principi 2 i 3 | 01, 03 |
| Add `watch_progress.episode_title`, `episode_thumbnail_url` | Denorm cache za "Continue watching" | 02 |
| Use `device_type` + `playlist_visibility` enume | Type safety | 02 |

## Naš MVP scope odstupa od v3 MVP-a

v3 spec definira MVP kao 6 tablica (resume-only). **Naš stvarni MVP** uključuje M3 favorites + M4 handoff + onboarding telemetry, što v3 pomiče u Faze 9-10. Zato Fazu 0 proširujemo s 3 dodatne `domovina_ai` tablice:

**MVP scope (Faza 0):**
```
public.profiles              ← bez email/is_anonymous (v3)
public.accounts              ← + search_text GENERATED + GIN trgm + deleted_at (v3)
public.accounts_memberships
public.activity_events       ← novo (v3)

domovina_ai.watch_progress   ← + episode_title + episode_thumbnail_url (v3)
domovina_ai.watch_sessions
domovina_ai.favorites        ← VRATI iz Faze 10 (M3 onboarding moment)
domovina_ai.handoff_tokens   ← NOVO (M4 cross-device, nije u v3)
domovina_ai.onboarding_events ← NOVO (M1-M4 telemetrija)
```

**Faze 6+** dodaju: `invitations`, `bookmarks`, `playlists`, `playlist_items` — kad UI feature treba tablicu.

## Endpoint (Coolify već postavljen)

| Service | URL |
|---------|-----|
| GoTrue (Auth) | `https://api.domovina.ai/auth/v1/*` |
| PostgREST | `https://api.domovina.ai/rest/v1/*` |
| Realtime | `wss://api.domovina.ai/realtime/v1/*` |
| Storage | `https://api.domovina.ai/storage/v1/*` |
| Studio | interni / IP-restricted |

## Env koje Flutter strana očekuje

```
SUPABASE_URL=https://api.domovina.ai
SUPABASE_ANON_KEY=<JWT iz Coolify Supabase config-a>
```

Ne stavljaj u repo — Cloudflare Pages env varijable na build time, lokalno `.env`.

## PostgREST schema exposure

Kritično — bez ovog Flutter klijent neće vidjeti `domovina_ai.*`:

```bash
# Coolify Supabase service env:
PGRST_DB_SCHEMAS=public,domovina_ai
# Restart PostgREST container.
```

Flutter pristupa preko `supabase.schema('domovina_ai').from('watch_progress')`.

## Redoslijed izvršavanja

```
01-core-identity.md          → public.profiles, accounts, accounts_memberships, activity_events
                               + extensions (citext, pg_trgm), enum (member_role, visibility_level)
                               + slug immutable trigger
02-domovina-ai-schema.md     → domovina_ai.watch_progress (+ denorm), watch_sessions,
                               favorites (MVP), handoff_tokens, onboarding_events
                               + enums (device_type, playlist_visibility)
03-triggers-functions.md     → handle_new_user, handle_user_promoted, generate_unique_slug,
                               has_role_on_account, is_account_member, log_event,
                               guard_slug_immutable
04-rls-policies.md           → sve RLS politike (s deleted_at filterima, has_role_on_account)
05-auth-providers.md         → Google + Apple + Email magic + Passkey (WebAuthn) GoTrue config
06-handoff-rpc.md            → create/consume_handoff_token RPC + pg_cron cleanup
07-flutter-swap-mocks.md     → swap mock servisa za prave Supabase pozive
```

## Sanity check između koraka

```sql
-- Nakon 01
select table_schema, table_name from information_schema.tables
where table_schema = 'public'
  and table_name in ('profiles','accounts','accounts_memberships','activity_events');
-- Treba 4 reda.

-- Nakon 02
select table_schema, table_name from information_schema.tables
where table_schema = 'domovina_ai';
-- Treba: watch_progress, watch_sessions, favorites, handoff_tokens, onboarding_events.

-- Nakon 04 — RLS na svemu
select schemaname, tablename, rowsecurity from pg_tables
where schemaname in ('public','domovina_ai')
  and tablename not like 'pg_%';
-- Sve treba imati rowsecurity = t.

-- Provjeri pg_trgm + GIN index na search_text
select indexname, indexdef from pg_indexes
where tablename = 'accounts' and indexname = 'ix_accounts_search';
```

## Backup prije svakog prompta

```bash
pg_dump --schema=public --schema=domovina_ai postgres > backup-$(date +%Y%m%d-%H%M).sql
```

## Status tracking

Markiraj korake kako ih radiš — dodaj `✅ DONE 2026-MM-DD` na kraj headera unutar svakog fajla.

## Reference

- [`docs/auth-and-database-plan-v3.md`](../auth-and-database-plan-v3.md) — principi + argumentacija
- [`docs/auth-and-database-plan.md`](../auth-and-database-plan.md) — v2 historical reference (sequence diagrami, Coolify deploy detalji, RLS pattern explainer)
- [`docs/schema-v3.dbml`](../schema-v3.dbml) — formalna schema s TableGroup-ovima
- [`docs/schema-v3-local.svg`](../schema-v3-local.svg) — auto-generirani ERD
