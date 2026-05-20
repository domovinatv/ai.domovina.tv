# 01 — Core identity (public.*) — v3

> **Cilj:** kreirati `public.profiles`, `public.accounts`, `public.accounts_memberships`, `public.activity_events`.
>
> **Reference:** `docs/auth-and-database-plan-v3.md` §Core identity; `docs/schema-v3.dbml` §IDENTITY + ACCOUNTS & ORGS + ACTIVITY EVENTS.
>
> **Razlike vs v2:**
> - DROP `apps`, `app_installations`, `role_permissions`, `app_permissions` enum
> - DROP `profiles.email`, `profiles.is_anonymous` (PII princip — koristi `auth.email()`)
> - ADD `accounts.search_text` GENERATED + GIN trgm
> - ADD `accounts.deleted_at` (soft-delete princip — samo ovdje)
> - ADD `activity_events` tablica
> - Slug immutable se enforce-a triggerom u 03

---

## Prompt za Claude Code

```
Ti si Postgres + Supabase ekspert. Napiši idempotentnu migraciju
sql/migrations/001_core_identity.sql prema specifikaciji niže.

Pravila:
- Idempotentno: `create if not exists`, `drop trigger if exists` pa create.
- Sve PK uuid s gen_random_uuid() (osim activity_events koja je bigserial).
- Sve timestamptz default now().
- Komentiraj svaki nontrivial CHECK / INDEX kratko (jedan red).
- Ne dodaj RLS politike ovdje — RLS dolazi u 04. Samo
  `alter table ... enable row level security;` na kraju svake tablice.
- Nema `apps`, `app_installations`, `role_permissions` tablica
  (v3 ih je drop-ao).
- Nema `email` ili `is_anonymous` u profiles (PII princip — koristi auth.email()).

1) Extensions:
   create extension if not exists citext;
   create extension if not exists pg_trgm;

2) Enums u public schemi:
   create type public.member_role as enum ('owner','admin','member');
   create type public.visibility_level as enum ('private','public');

3) public.profiles — minimal, bez PII mirror:
   - id uuid PK references auth.users(id) on delete cascade
   - locale text not null default 'hr'
   - timezone text not null default 'Europe/Zagreb'
   - active_account_id uuid -- FK postavi NAKON što kreiraš accounts
   - notification_prefs jsonb not null default '{}'::jsonb
   - onboarding_completed_at timestamptz
   - last_seen_at timestamptz
   - deleted_at timestamptz  -- opcionalno (GDPR), v3 dopušta
   - created_at, updated_at timestamptz not null default now()

4) public.accounts — unified user+org, soft-delete only here:
   - id uuid PK default gen_random_uuid()
   - primary_owner_user_id uuid not null references auth.users(id) on delete cascade
   - is_personal_account bool not null default false
   - slug citext not null unique
   - name text not null
   - avatar_url text
   - bio text
   - website_url text
   - search_text text GENERATED ALWAYS AS (
       lower(name || ' ' || slug::text || ' ' || coalesce(bio, ''))
     ) STORED
   - visibility public.visibility_level not null default 'private'
   - metadata jsonb not null default '{}'::jsonb
   - deleted_at timestamptz  -- ★ soft-delete (princip 3 — sole table)
   - created_at, updated_at timestamptz not null default now()

   CONSTRAINT slug_format CHECK (
     slug ~ '^[a-z0-9][a-z0-9-]{0,38}[a-z0-9]$' OR length(slug) = 1
   )

   Partial unique index — jedan personal account po user-u:
   create unique index if not exists ix_one_personal_per_user
     on public.accounts(primary_owner_user_id)
     where is_personal_account = true;

5) Sad postavi profiles.active_account_id FK:
   alter table public.profiles
     add constraint fk_active_account
     foreign key (active_account_id)
     references public.accounts(id) on delete set null;

6) public.accounts_memberships — N:M user × org × role:
   - account_id uuid not null references public.accounts(id) on delete cascade
   - user_id uuid not null references public.profiles(id) on delete cascade
   - account_role public.member_role not null default 'member'
   - display_name_override text
   - invited_by uuid references public.profiles(id) on delete set null
   - joined_at timestamptz not null default now()
   - last_active_at timestamptz
   - PK (account_id, user_id)

   Cross-table CHECK da account_id nije personal NE radi pouzdano u CHECK —
   enforce trigger-om (u 03: check_membership_is_org).

7) public.activity_events — append-only event stream (novo u v3):
   - id bigserial PK
   - actor_user_id uuid references auth.users(id) on delete set null
   - target_account_id uuid references public.accounts(id) on delete cascade
   - event_type text not null
   - payload jsonb not null default '{}'::jsonb
   - created_at timestamptz not null default now()

8) Indeksi (kritični za RLS performance i feed queries):
   create index if not exists ix_accounts_primary_owner
     on public.accounts(primary_owner_user_id);
   create index if not exists ix_accounts_slug on public.accounts(slug);

   -- ★ GIN trigram za sub-ms fuzzy search po name/slug/bio
   create index if not exists ix_accounts_search
     on public.accounts using gin (search_text gin_trgm_ops);

   -- Aktivni accounts (deleted_at NULL) — ako neke RLS politike imaju
   -- AND deleted_at IS NULL, ovaj partial može pomoći.
   create index if not exists ix_accounts_alive
     on public.accounts(id) where deleted_at is null;

   create index if not exists ix_memberships_user
     on public.accounts_memberships(user_id);
   create index if not exists ix_memberships_account
     on public.accounts_memberships(account_id);

   create index if not exists ix_activity_account_recent
     on public.activity_events(target_account_id, created_at desc);
   create index if not exists ix_activity_actor
     on public.activity_events(actor_user_id, created_at desc);
   create index if not exists ix_activity_type
     on public.activity_events(event_type, created_at desc);

9) Updated_at autotouch trigger:
   create or replace function public.touch_updated_at() returns trigger
   language plpgsql security definer set search_path = '' as $$
   begin
     new.updated_at = now();
     return new;
   end;
   $$;

   drop trigger if exists trg_profiles_updated on public.profiles;
   create trigger trg_profiles_updated
     before update on public.profiles
     for each row execute function public.touch_updated_at();

   drop trigger if exists trg_accounts_updated on public.accounts;
   create trigger trg_accounts_updated
     before update on public.accounts
     for each row execute function public.touch_updated_at();

10) Enable RLS na svih 4 tablice (policies dolaze u 04):
    alter table public.profiles enable row level security;
    alter table public.accounts enable row level security;
    alter table public.accounts_memberships enable row level security;
    alter table public.activity_events enable row level security;

11) Output `select 'OK 01' as status;`

NAPOMENA — slug immutable trigger (guard_slug_immutable) NIJE u ovom fajlu;
on dolazi u 03 jer zahtjeva funkciju koju ćemo definirati zajedno s ostalim.
```

---

## Sanity check (Studio SQL editor)

```sql
\dt public.*

-- 4 tablice + 2 enum-a:
select typname from pg_type where typname in ('member_role','visibility_level');

-- search_text generated stupac:
select column_name, generation_expression
from information_schema.columns
where table_schema='public' and table_name='accounts'
  and column_name='search_text';

-- GIN trgm index:
select indexname, indexdef from pg_indexes
where tablename='accounts' and indexname='ix_accounts_search';

-- pg_trgm extension:
select extname from pg_extension where extname='pg_trgm';
```

## Smoke test

```sql
-- Manual insert (service_role context):
insert into auth.users (id, email, is_anonymous) values
  (gen_random_uuid(), 'matija@example.com', false)
returning id \gset

insert into public.profiles (id) values (:'id');  -- NO email, NO is_anonymous

insert into public.accounts (primary_owner_user_id, is_personal_account, slug, name)
values (:'id', true, 'matija', 'Matija Stepanić')
returning id, search_text;
-- search_text = 'matija stepanić matija ' (lower(name)+slug+coalesce(bio,''))

-- Fuzzy search:
select slug, name, similarity(search_text, 'matijaa') as sim
from public.accounts
where search_text % 'matijaa'   -- pg_trgm operator
order by sim desc limit 5;

-- Cleanup:
delete from auth.users where email='matija@example.com';
-- Trebao cascade i kroz profiles i kroz accounts.
```

## Što ide u sljedeći korak

- `02-domovina-ai-schema.md` — `domovina_ai.*` tablice s denorm watch_progress, favorites, handoff_tokens, onboarding_events.
