# 03 — Triggers & helper functions — v3

> **Cilj:** funkcije + triggeri za bootstrap profila/accounta, slug immutability, RLS helperi, event logging.
>
> **Reference:** `docs/auth-and-database-plan-v3.md` §Architectural principles + §`activity_events`.
>
> **Razlike vs v2:**
> - DROP `has_permission(p_account, p_permission)` — koristi `has_role_on_account(target, min_role)` (3 hardcoded role-a, nema decoupling)
> - DROP `profiles.email`/`is_anonymous` insert iz triggera (PII princip — koristi `auth.email()`)
> - ADD `log_event()` security-definer helper za pisanje u `activity_events`
> - ADD `guard_slug_immutable()` BEFORE UPDATE trigger (princip 2)
> - ADD event emit-ovi iz `handle_user_promoted` i membership change triggera

---

## Prompt za Claude Code

```
Napiši migraciju `sql/migrations/003_triggers_functions.sql`. Sve funkcije
moraju biti `security definer set search_path = ''` i fully-qualified table
references (public.accounts ne accounts).

Idempotentno: `create or replace function`, `drop trigger if exists ... then create`.

1) public.generate_unique_slug(base_text text) returns citext
   - language plpgsql security definer set search_path = ''
   - Lowercase, ukloni @domain dio (split_part na '@'), regex zamijeni
     non-alphanum s '-', trim crtice s krajeva.
   - Ako rezultat < 1 char → 'user'. Ako > 38 char → substring(1,38).
   - Pokušaj base, base-1, base-2, ... dok ne nađe slobodan slug u public.accounts.

2) public.handle_new_user() returns trigger
   - AFTER INSERT na auth.users.
   - UVIJEK insert u public.profiles (id, locale='hr')
     -- NEMA email, NEMA is_anonymous (PII princip; auth.email() ih ima)
   - AKO NEW.is_anonymous IS NOT TRUE:
     - generate_unique_slug iz NEW.email (ili raw_user_meta_data->>'name')
     - INSERT u public.accounts
       (primary_owner_user_id, is_personal_account=true, slug, name)
     - UPDATE public.profiles SET active_account_id = <novi>
     - INSERT u public.activity_events
       (actor_user_id, target_account_id, event_type, payload)
       VALUES (NEW.id, <novi account_id>, 'account.created',
               jsonb_build_object('slug', <slug>, 'is_personal', true))

3) public.handle_user_promoted() returns trigger
   - AFTER UPDATE OF is_anonymous na auth.users.
   - Okida samo kad OLD.is_anonymous = true I NEW.is_anonymous = false.
   - Isto kao handle_new_user (account + activity_event).
   - UPDATE public.profiles SET active_account_id = <novi>
     -- NEMA SET is_anonymous=false ili email=... (oba su iz auth.users)
   - INSERT u public.activity_events s event_type='user.promoted'.

4) Triggere:
   drop trigger if exists on_auth_user_created on auth.users;
   create trigger on_auth_user_created
     after insert on auth.users for each row
     execute function public.handle_new_user();

   drop trigger if exists on_auth_user_promoted on auth.users;
   create trigger on_auth_user_promoted
     after update of is_anonymous on auth.users for each row
     execute function public.handle_user_promoted();

5) public.guard_slug_immutable() returns trigger
   - BEFORE UPDATE na public.accounts.
   - IF OLD.slug IS DISTINCT FROM NEW.slug THEN
       raise exception 'slug is immutable in v1 (changed from % to %)',
         OLD.slug, NEW.slug;

   drop trigger if exists trg_guard_slug_immutable on public.accounts;
   create trigger trg_guard_slug_immutable
     before update on public.accounts
     for each row execute function public.guard_slug_immutable();

6) public.check_membership_is_org() returns trigger
   - BEFORE INSERT OR UPDATE na public.accounts_memberships.
   - SELECT is_personal_account FROM public.accounts WHERE id = NEW.account_id;
   - IF true → raise exception 'cannot add membership to personal account';

   drop trigger if exists trg_check_membership_is_org on public.accounts_memberships;
   create trigger trg_check_membership_is_org
     before insert or update on public.accounts_memberships
     for each row execute function public.check_membership_is_org();

7) RLS helperi — koristit će ih politike u 04:

   public.is_account_member(p_account uuid) returns boolean
     - language sql security definer set search_path = '' stable
     - return exists (
         select 1 from public.accounts a
         where a.id = p_account
           and a.deleted_at is null
           and (
             a.primary_owner_user_id = (select auth.uid())
             or exists (
               select 1 from public.accounts_memberships m
               where m.account_id = p_account
                 and m.user_id = (select auth.uid())
             )
           )
       );

   public.has_role_on_account(
     p_account uuid,
     p_min_role public.member_role default 'member'
   ) returns boolean
     - language sql security definer set search_path = '' stable
     - return exists (
         select 1 from public.accounts a
         where a.id = p_account
           and a.deleted_at is null
           and (
             a.primary_owner_user_id = (select auth.uid())  -- owner uvijek
             or exists (
               select 1 from public.accounts_memberships m
               where m.account_id = p_account
                 and m.user_id = (select auth.uid())
                 and (
                   p_min_role = 'member'
                   or (p_min_role = 'admin' and m.account_role in ('admin','owner'))
                   or (p_min_role = 'owner' and m.account_role = 'owner')
                 )
             )
           )
       );

   Grant execute na authenticated:
     grant execute on function public.is_account_member(uuid) to authenticated;
     grant execute on function public.has_role_on_account(uuid, public.member_role)
       to authenticated;

8) public.log_event(p_event_type text, p_target_account_id uuid,
                    p_payload jsonb default '{}'::jsonb) returns void
   - language sql security definer set search_path = ''
   - insert into public.activity_events
       (actor_user_id, target_account_id, event_type, payload)
     values ((select auth.uid()), p_target_account_id, p_event_type, p_payload);

   grant execute on function public.log_event(text, uuid, jsonb) to authenticated;

9) Membership change auto-logging — pišu eventove od dana 1:

   create or replace function public.log_membership_event() returns trigger
   language plpgsql security definer set search_path = '' as $$
   begin
     if (TG_OP = 'INSERT') then
       insert into public.activity_events
         (actor_user_id, target_account_id, event_type, payload)
       values (
         coalesce(NEW.invited_by, NEW.user_id),
         NEW.account_id,
         'member.joined',
         jsonb_build_object('user_id', NEW.user_id, 'role', NEW.account_role)
       );
     elsif (TG_OP = 'UPDATE' and OLD.account_role is distinct from NEW.account_role) then
       insert into public.activity_events
         (actor_user_id, target_account_id, event_type, payload)
       values (
         (select auth.uid()),
         NEW.account_id,
         'member.role_changed',
         jsonb_build_object(
           'user_id', NEW.user_id,
           'old_role', OLD.account_role,
           'new_role', NEW.account_role
         )
       );
     elsif (TG_OP = 'DELETE') then
       insert into public.activity_events
         (actor_user_id, target_account_id, event_type, payload)
       values (
         (select auth.uid()),
         OLD.account_id,
         'member.removed',
         jsonb_build_object('user_id', OLD.user_id, 'role', OLD.account_role)
       );
     end if;
     return coalesce(NEW, OLD);
   end;
   $$;

   drop trigger if exists trg_log_membership on public.accounts_memberships;
   create trigger trg_log_membership
     after insert or update or delete on public.accounts_memberships
     for each row execute function public.log_membership_event();

10) Episode completion event — okida se kad completed flip-a na true:

   create or replace function domovina_ai.log_completion() returns trigger
   language plpgsql security definer set search_path = '' as $$
   begin
     -- completed je generated stupac; pratimo flip na true.
     if (TG_OP = 'UPDATE' and OLD.completed = false and NEW.completed = true) then
       insert into public.activity_events
         (actor_user_id, target_account_id, event_type, payload)
       select NEW.user_id, a.id, 'episode.completed',
              jsonb_build_object('episode_id', NEW.episode_id,
                                 'duration', NEW.duration_seconds)
       from public.accounts a
       where a.primary_owner_user_id = NEW.user_id
         and a.is_personal_account = true;
     end if;
     return NEW;
   end;
   $$;

   drop trigger if exists trg_log_completion on domovina_ai.watch_progress;
   create trigger trg_log_completion
     after update on domovina_ai.watch_progress
     for each row execute function domovina_ai.log_completion();

11) Output `select 'OK 03' as status;`
```

---

## Smoke test (nakon 03)

```sql
-- 1. Signup test — anonymous user
-- Preko GoTrue REST: POST /auth/v1/signup s '{}'.
-- Pretpostavi vraćeni id = ':uid'.

-- Provjeri da je profile auto-kreiran BEZ email/is_anonymous mirrora:
select id, locale, active_account_id from public.profiles where id = ':uid';
-- Treba: 1 red, locale='hr', active_account_id=NULL (anonymous nema account).

-- Provjeri da NEMA accounta za anonymous:
select count(*) from public.accounts where primary_owner_user_id = ':uid';
-- 0

-- 2. Promotion test
update auth.users set is_anonymous=false, email='matija@example.com'
where id = ':uid';

-- Trigger okida → personal account:
select slug, name from public.accounts where primary_owner_user_id = ':uid';
-- Treba: 1 red, slug iz emaila.

-- Profile updatean:
select active_account_id from public.profiles where id = ':uid';
-- NIJE null.

-- Activity event:
select event_type, payload from public.activity_events
where actor_user_id = ':uid' order by created_at;
-- 'account.created' + 'user.promoted'.

-- 3. Slug immutable
update public.accounts set slug='novi-slug' where primary_owner_user_id=':uid';
-- ERROR: slug is immutable in v1

-- 4. has_role_on_account
select public.has_role_on_account(
  (select id from public.accounts where primary_owner_user_id=':uid'),
  'owner'
);
-- t (sam si owner svog personal accounta)

-- 5. Cleanup
delete from auth.users where id = ':uid';
-- Cascade očisti profile, account, memberships, events.
```

## Što ide u sljedeći korak

- `04-rls-policies.md` — sve RLS politike, koriste `has_role_on_account` i `is_account_member` iz ovog file-a.
