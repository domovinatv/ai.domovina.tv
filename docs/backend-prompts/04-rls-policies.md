# 04 — RLS policies — v3

> **Cilj:** RLS politike za sve MVP tablice. Koristi `(select auth.uid())` (InitPlan optimizacija), `to authenticated`, deleted_at filtere gdje je relevantno.
>
> **Reference:** `docs/auth-and-database-plan-v3.md` §Architectural principles.
>
> **Razlike vs v2 promptova:**
> - DROP svi `has_permission(...)` pozivi — koristi `has_role_on_account(target, 'admin')` ili `('owner')`
> - ADD policies za `activity_events`
> - ADD `accounts.deleted_at IS NULL` u svim accounts SELECT-ovima
> - DROP policies za `apps`, `app_installations`, `role_permissions`, `invitations` (nije u MVP-u)
> - ADD policies za `favorites`, `handoff_tokens`, `onboarding_events` (naš MVP-add)

---

## Prompt za Claude Code

```
Napiši migraciju `sql/migrations/004_rls_policies.sql`. Sve politike koriste
`(select auth.uid())` wrap pattern (Supabase RLS optimization — InitPlan,
ne PerRow).

Idempotentno: drop policy if exists ... on ...; create policy ...;

Princip:
- to authenticated (Supabase auth.uid() je non-null i za anonymous users)
- Owner-based pristup koristi:
    public.is_account_member(account_id)
    public.has_role_on_account(account_id, 'admin')
    public.has_role_on_account(account_id, 'owner')
  (definirani u 03 — sve security definer, koriste auth.uid() interno)

=== public.profiles ===

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (id = (select auth.uid()));

drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert on public.profiles
  for insert to authenticated
  with check (id = (select auth.uid()));
-- Note: handle_new_user trigger je security definer pa zaobilazi RLS svakako.

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

=== public.accounts ===

drop policy if exists accounts_select on public.accounts;
create policy accounts_select on public.accounts
  for select to authenticated
  using (
    deleted_at is null
    and (
      primary_owner_user_id = (select auth.uid())
      or public.is_account_member(id)
      or visibility = 'public'
    )
  );

drop policy if exists accounts_insert on public.accounts;
create policy accounts_insert on public.accounts
  for insert to authenticated
  with check (primary_owner_user_id = (select auth.uid()));

drop policy if exists accounts_update on public.accounts;
create policy accounts_update on public.accounts
  for update to authenticated
  using (
    deleted_at is null
    and (
      primary_owner_user_id = (select auth.uid())
      or public.has_role_on_account(id, 'admin')
    )
  )
  with check (
    primary_owner_user_id = (select auth.uid())
    or public.has_role_on_account(id, 'admin')
  );

drop policy if exists accounts_delete on public.accounts;
create policy accounts_delete on public.accounts
  for delete to authenticated
  using (primary_owner_user_id = (select auth.uid()));
-- Soft-delete (UPDATE deleted_at) prolazi accounts_update policy.
-- Hard-delete je rezerviran za owner ili cleanup cron (service_role).

=== public.accounts_memberships ===

drop policy if exists memberships_select on public.accounts_memberships;
create policy memberships_select on public.accounts_memberships
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or public.is_account_member(account_id)
  );

drop policy if exists memberships_write on public.accounts_memberships;
create policy memberships_write on public.accounts_memberships
  for all to authenticated
  using (public.has_role_on_account(account_id, 'admin'))
  with check (public.has_role_on_account(account_id, 'admin'));

=== public.activity_events ===

drop policy if exists activity_select on public.activity_events;
create policy activity_select on public.activity_events
  for select to authenticated
  using (
    actor_user_id = (select auth.uid())
    or public.is_account_member(target_account_id)
  );
-- INSERT samo preko log_event() security definer; NEMA insert policy.
-- Append-only — NEMA update/delete policy.

=== domovina_ai.watch_progress ===

drop policy if exists wp_select on domovina_ai.watch_progress;
create policy wp_select on domovina_ai.watch_progress
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists wp_write on domovina_ai.watch_progress;
create policy wp_write on domovina_ai.watch_progress
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

=== domovina_ai.watch_sessions ===

drop policy if exists ws_select on domovina_ai.watch_sessions;
create policy ws_select on domovina_ai.watch_sessions
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists ws_insert on domovina_ai.watch_sessions;
create policy ws_insert on domovina_ai.watch_sessions
  for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists ws_update on domovina_ai.watch_sessions;
create policy ws_update on domovina_ai.watch_sessions
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
-- Session ended_at i end_position_seconds se update-aju na kraju sesije.

=== domovina_ai.favorites — owner-based (user account ili org) ===

drop policy if exists fav_select on domovina_ai.favorites;
create policy fav_select on domovina_ai.favorites
  for select to authenticated
  using (public.is_account_member(owner_id));

drop policy if exists fav_insert on domovina_ai.favorites;
create policy fav_insert on domovina_ai.favorites
  for insert to authenticated
  with check (
    public.is_account_member(owner_id)
    and created_by = (select auth.uid())
  );

drop policy if exists fav_delete on domovina_ai.favorites;
create policy fav_delete on domovina_ai.favorites
  for delete to authenticated
  using (
    created_by = (select auth.uid())
    or public.has_role_on_account(owner_id, 'admin')
  );

drop policy if exists fav_update on domovina_ai.favorites;
create policy fav_update on domovina_ai.favorites
  for update to authenticated
  using (
    created_by = (select auth.uid())
    or public.has_role_on_account(owner_id, 'admin')
  )
  with check (
    created_by = (select auth.uid())
    or public.has_role_on_account(owner_id, 'admin')
  );

=== domovina_ai.handoff_tokens ===

drop policy if exists ho_select on domovina_ai.handoff_tokens;
create policy ho_select on domovina_ai.handoff_tokens
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists ho_insert on domovina_ai.handoff_tokens;
create policy ho_insert on domovina_ai.handoff_tokens
  for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists ho_delete on domovina_ai.handoff_tokens;
create policy ho_delete on domovina_ai.handoff_tokens
  for delete to authenticated
  using (user_id = (select auth.uid()));

-- consume_handoff_token RPC (06) je security definer i zaobilazi RLS
-- — može pristupiti tudjem kodu da ga konzumira (po definiciji feature-a).

=== domovina_ai.onboarding_events ===

drop policy if exists oe_select on domovina_ai.onboarding_events;
create policy oe_select on domovina_ai.onboarding_events
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists oe_insert on domovina_ai.onboarding_events;
create policy oe_insert on domovina_ai.onboarding_events
  for insert to authenticated
  with check (user_id = (select auth.uid()));
-- Append-only; NEMA update/delete policy.

Output `select 'OK 04' as status;`
```

---

## RLS smoke test

```sql
-- Setup: 2 test usera (kao service_role)
insert into auth.users (id, email, is_anonymous) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.com', false),
  ('22222222-2222-2222-2222-222222222222', 'b@test.com', false);
-- Triggeri kreiraju profiles + accounts.

-- Simuliraj request kao user A:
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111"}';

-- Smije samo svoj profile
select count(*) from public.profiles;            -- 1
-- Smije svoje accounte
select count(*) from public.accounts;            -- 1
-- Ne smije B-ov watch_progress (nema ga još, ali pravilo važi)
select count(*) from domovina_ai.watch_progress; -- 0

-- Pokušaj insertirati B-ov fav → fail
insert into domovina_ai.favorites (owner_id, episode_id, created_by)
values (
  (select id from public.accounts
   where primary_owner_user_id='22222222-2222-2222-2222-222222222222'),
  'xyz', '11111111-1111-1111-1111-111111111111'
);
-- ERROR: new row violates row-level security policy

-- Smije svoj insert
insert into domovina_ai.favorites (owner_id, episode_id, created_by)
values (
  (select id from public.accounts
   where primary_owner_user_id='11111111-1111-1111-1111-111111111111'),
  'abc', '11111111-1111-1111-1111-111111111111'
);
-- OK

reset role;

-- Cleanup
delete from auth.users where id in
  ('11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222');
```

## Što ide u sljedeći korak

- `05-auth-providers.md` — Google + Apple + Email magic + Passkey config u GoTrue-u (nepromijenjen vs v2 verzija).
