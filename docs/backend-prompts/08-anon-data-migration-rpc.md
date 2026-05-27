# 08 — RPC za migraciju anon → permanent user data — v1

> **Cilj:** RPC `domovina_ai.migrate_anon_data(p_anon_id uuid)` koji prenese sve per-user redove iz anon UUID-a u current `auth.uid()` (permanent user) nakon što se anon user prijavio s Google/Apple/email-om.
>
> **Razlog:** Frontend strategija se mijenja — umjesto `linkIdentity` (koji ne radi za "returning user with new browser" scenarij jer `identity_already_exists`), uvijek pozivamo `signInWithOAuth`. Time GoTrue kreira **novi** `auth.users` red (ili sign-in postojeći), a anon UUID ostaje s podacima. Trebamo server-side merge.
>
> **Reference:**
> - `docs/auth-and-database-plan-v3.md` §Anon→permanent
> - `lib/services/auth_service.dart` (frontend strana — refactor u istom PR-u)
> - 03-triggers-functions.md (`handle_user_promoted` neće više fire-ati jer ne updateamo isti row)

---

## Što treba migrirati

Sve tablice u `domovina_ai.*` koje imaju `user_id uuid` FK na `public.profiles(id)`:

| Tablica | Kolona | PK | Handling |
|---|---|---|---|
| `watch_progress` | `user_id` | `(user_id, episode_id)` | UPSERT — ako target već ima red za isti episode, zadrži MAX(position_seconds) |
| `watch_sessions` | `user_id` | `id` (UUID PK) | UPDATE bez konflikta |
| `handoff_tokens` | `user_id` | `id` (UUID PK) | UPDATE bez konflikta |
| `onboarding_events` | `user_id` | `id` (UUID PK) | UPDATE bez konflikta |

**`favorites` se NE migrira** — anon nema personal account → ne može imati favorite (RLS `is_account_member(owner_id)` blokira INSERT za anone). Provjereno u kodu (`frontend_mock_strategy.md` memorija + RLS policies).

**`profiles`** anon reda se briše — nakon migracije `auth.users` anon reda obrišemo, `ON DELETE CASCADE` će propasti dolje na `profiles`.

---

## Signature

```sql
domovina_ai.migrate_anon_data(p_anon_id uuid)
returns table (
  watch_progress_moved int,
  watch_progress_merged int,   -- broj redova gdje smo zadržali target umjesto anon
  watch_sessions_moved int,
  handoff_tokens_moved int,
  onboarding_events_moved int,
  anon_user_deleted boolean
)
language plpgsql
security definer
set search_path = ''
```

---

## Behavior

```
1. v_target_id := (select auth.uid())
   if v_target_id is null → raise exception 'not authenticated'
   if v_target_id = p_anon_id → return all zeros (no-op, isti user)

2. Validacija anon usera:
   select is_anonymous, email
   from auth.users
   where id = p_anon_id
   into v_anon_is_anonymous, v_anon_email

   if not found → raise exception 'anon user not found'
   if v_anon_is_anonymous != true → raise exception 'source user is not anonymous'
   if v_anon_email is not null and v_anon_email != '' → raise exception 'source user has email — not anonymous'

3. Validacija target usera:
   select is_anonymous
   from auth.users
   where id = v_target_id
   into v_target_is_anonymous

   if v_target_is_anonymous = true → raise exception 'target user is anonymous — cannot migrate into anon'

4. Migracija watch_progress (UPSERT logika):
   - INSERT INTO domovina_ai.watch_progress (user_id, episode_id, ...) — sve iz anon-a s SET user_id = v_target_id
   - ON CONFLICT (user_id, episode_id) DO UPDATE SET position_seconds = GREATEST(EXCLUDED.position_seconds, watch_progress.position_seconds),
       watch_count = watch_count + EXCLUDED.watch_count,
       last_watched_at = GREATEST(EXCLUDED.last_watched_at, watch_progress.last_watched_at)
   - GET DIAGNOSTICS watch_progress_moved = ROW_COUNT
   - Posebno izračunaj watch_progress_merged: count anon redova gdje je već postojao target red.
   - DELETE FROM domovina_ai.watch_progress WHERE user_id = p_anon_id (cleanup nakon migracije)

5. Migracija watch_sessions:
   UPDATE domovina_ai.watch_sessions SET user_id = v_target_id WHERE user_id = p_anon_id

6. Migracija handoff_tokens i onboarding_events — isto, UPDATE user_id.

7. Cascade cleanup:
   DELETE FROM auth.users WHERE id = p_anon_id
   -- CASCADE briše domovina_ai.* redove koji ostanu + public.profiles red

8. Log u activity_events:
   INSERT INTO public.activity_events (actor_user_id, event_type, payload)
   VALUES (v_target_id, 'user.anon_data_migrated',
           jsonb_build_object('anon_id', p_anon_id,
                              'watch_progress', watch_progress_moved,
                              'merged', watch_progress_merged, ...))

9. return next row.
```

---

## Security model za MVP

**Trenutni stav:** RPC trustuje da `p_anon_id` koji client pošalje stvarno pripada njemu. Napadač koji zna tuđi anon UUID može trigerirati migraciju u svoj account — efektivno krasti tuđu watch history.

**Mitigacije u MVP-u:**
- Anon UUIDs nikad ne idu u URL-ove, logove, share linkove. Pohranjeni samo u user-ovom localStorage. Praktični risk je nizak.
- Validacija u koraku 2 (anon mora biti `is_anonymous = true` AND email empty) — ako attacker zna UUID nekog već promovirannog usera, RPC će puknuti.
- Step 7 brisanje anon usera znači da je svaki UUID upotrebljiv **samo jednom** — drugi pokušaj migracije istog UUID-a će puknuti.

**Hardening za fazu 2 (preporuka — ne za MVP):**
- Client šalje i anon JWT kao argument (`p_anon_jwt text`).
- Server verifies JWT s istim secret-om (`current_setting('app.settings.jwt_secret')`).
- Extract `sub` i provjeri da je jednak `p_anon_id`.
- Ovo zahtijeva pgjwt extension ili custom PL/pgSQL HMAC SHA256 verifier.

---

## Grants

```sql
REVOKE ALL ON FUNCTION domovina_ai.migrate_anon_data(uuid) FROM public;
GRANT EXECUTE ON FUNCTION domovina_ai.migrate_anon_data(uuid) TO authenticated;
```

(Anon role NE smije zvati ovu RPC — only authenticated.)

---

## Test scenariji

| # | Stanje prije | RPC poziv | Očekivano |
|---|---|---|---|
| 1 | Anon ima 3 watch_progress reda, target ima 0 | success | 3 moved, 0 merged, anon deleted |
| 2 | Anon ima isti episode kao target s većim position | success | UPSERT zadrži anon position, 1 merged |
| 3 | Anon ne postoji | exception | "anon user not found" |
| 4 | Anon ima email | exception | "source user is not anonymous" |
| 5 | Target je anonymous | exception | "target user is anonymous" |
| 6 | p_anon_id = auth.uid() | no-op | sve nule, exit |
| 7 | Pozovan kao anon role | exception | RLS / grant blokira |

---

## Migracija file

`sql/migrations/008_anon_data_migration_rpc.sql` — idempotent (`create or replace function`).

Nakon deploya, frontend strana mijenja `auth_service.dart` da poziva RPC nakon signedIn evenata (vidi task #3 u sesiji 2026-05-26).
