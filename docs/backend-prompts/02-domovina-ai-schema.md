# 02 — Domovina.ai schema — v3 hibrid

> **Cilj:** kreirati `domovina_ai` schemu s MVP tablicama za naš onboarding flow:
> `watch_progress` (s denorm cache), `watch_sessions`, `favorites`, `handoff_tokens`, `onboarding_events`.
>
> **Reference:** `docs/auth-and-database-plan-v3.md` §App-specific layer; `docs/schema-v3.dbml` §DOMOVINA.AI.
>
> **Razlike vs v2 promptova:**
> - ADD `watch_progress.episode_title` + `episode_thumbnail_url` (denorm — skida sekundarni CDN fetch)
> - USE `device_type` enum umjesto raw text
> - KEEP `favorites` u MVP-u (v3 ga pomiče u Fazu 10, ali M3 onboarding moment ga zahtjeva sad)
> - KEEP `handoff_tokens` + `onboarding_events` (nije u v3 spec-u, naš add-on za M4 + telemetriju)
> - DROP `bookmarks`, `playlists`, `playlist_items` iz Faze 0 (čekaju Faze 6+ kao u v3)

---

## Prompt za Claude Code

```
Napiši idempotentnu migraciju `sql/migrations/002_domovina_ai.sql`.

Pravila:
- create schema if not exists domovina_ai;
- Sve FK prema public.profiles(id) ili public.accounts(id).
- Episode-i se identificiraju YouTube videoId-em (text).
- Sve PK uuid (gen_random_uuid) osim watch_progress (composite) i
  watch_sessions/onboarding_events (bigserial).
- Sve timestamptz default now().
- Generated columns gdje god ima smisla (percent_complete, completed).

1) Enums u domovina_ai schemi:
   create type domovina_ai.device_type as enum ('web','ios','android','macos');
   create type domovina_ai.playlist_visibility as enum ('private','members','public');
   -- playlist_visibility se NE koristi u ovoj migraciji, ali ga seedamo
   -- jer playlists tablica dolazi u Fazi 6+ i bolje da je enum već tu
   -- (DDL na enum je oslabljen, dodavanje vrijednosti ide bez full lock-a).

2) domovina_ai.watch_progress — Netflix-style "GDJE si stao":
   - user_id uuid not null references public.profiles(id) on delete cascade
   - episode_id text not null  -- YouTube videoId
   - channel_id text not null
   - position_seconds int not null default 0 check (position_seconds >= 0)
   - duration_seconds int not null check (duration_seconds > 0)
   - percent_complete numeric generated always as (
       least(100, (position_seconds::numeric / nullif(duration_seconds,0)) * 100)
     ) stored
   - completed bool generated always as (
       position_seconds::numeric / nullif(duration_seconds,0) >= 0.9
     ) stored
   - episode_title text         -- ★ v3: denorm cache iz CDN
   - episode_thumbnail_url text -- ★ v3: denorm cache iz CDN
   - playback_rate numeric not null default 1.0
   - audio_track text
   - subtitle_track text
   - watch_count int not null default 1
   - last_watched_at timestamptz not null default now()
   - last_device domovina_ai.device_type
   - created_at timestamptz not null default now()
   - PK (user_id, episode_id)

3) domovina_ai.watch_sessions — append-only audit log za analytics:
   - id bigserial PK
   - user_id uuid not null references public.profiles(id) on delete cascade
   - episode_id text not null
   - started_at timestamptz not null default now()
   - ended_at timestamptz
   - start_position_seconds int
   - end_position_seconds int
   - pause_count int not null default 0
   - seek_count int not null default 0
   - completed_normally bool
   - device domovina_ai.device_type
   - user_agent text

4) domovina_ai.favorites — owner-based (user account ILI org account):
   - owner_id uuid not null references public.accounts(id) on delete cascade
   - episode_id text not null
   - created_by uuid not null references public.profiles(id) on delete cascade
   - notes text
   - position int  -- za sortiranje unutar favorita
   - created_at timestamptz not null default now()
   - PK (owner_id, episode_id)

5) domovina_ai.handoff_tokens — M4 cross-device sign-in transfer:
   - code text PK   -- 6-znamenkasti, zero-padded ('000000'..'999999')
   - user_id uuid not null references public.profiles(id) on delete cascade
   - source_device domovina_ai.device_type
   - expires_at timestamptz not null default (now() + interval '5 minutes')
   - consumed_at timestamptz
   - consumed_by_device domovina_ai.device_type
   - created_at timestamptz not null default now()

6) domovina_ai.onboarding_events — telemetry za M1-M4 momente:
   - id bigserial PK
   - user_id uuid not null references public.profiles(id) on delete cascade
   - event text not null
     -- 'moment_shown' | 'moment_dismissed' | 'auth_started' |
     -- 'auth_completed' | 'auth_failed'
   - moment_id text  -- 'm1' | 'm2' | 'm3' | 'm4' | null
   - provider text   -- 'google' | 'apple' | 'email' | 'passkey' | null
   - properties jsonb not null default '{}'::jsonb
   - created_at timestamptz not null default now()

7) Indeksi:
   create index if not exists ix_wp_continue
     on domovina_ai.watch_progress(user_id, last_watched_at desc);
   create index if not exists ix_wp_completed
     on domovina_ai.watch_progress(user_id, completed, last_watched_at desc);

   create index if not exists ix_ws_user
     on domovina_ai.watch_sessions(user_id, started_at desc);
   create index if not exists ix_ws_episode
     on domovina_ai.watch_sessions(episode_id, started_at desc);

   create index if not exists ix_fav_owner
     on domovina_ai.favorites(owner_id, created_at desc);

   create index if not exists ix_ho_user
     on domovina_ai.handoff_tokens(user_id, created_at desc);
   create index if not exists ix_ho_expires
     on domovina_ai.handoff_tokens(expires_at) where consumed_at is null;

   create index if not exists ix_oe_user
     on domovina_ai.onboarding_events(user_id, created_at desc);
   create index if not exists ix_oe_event
     on domovina_ai.onboarding_events(event, created_at desc);

8) View "Continue watching" — frontend pita ovo umjesto raw watch_progress:
   create or replace view domovina_ai.v_continue_watching as
   select user_id, episode_id, channel_id, position_seconds, duration_seconds,
          percent_complete, episode_title, episode_thumbnail_url,
          last_watched_at, last_device
   from domovina_ai.watch_progress
   where not completed
     and position_seconds > 30
   order by last_watched_at desc;

   Views nasljeđuju RLS od underlying tablice u Postgres 15+.

9) Enable RLS na svih 5 tablica (policies dolaze u 04):
   alter table domovina_ai.watch_progress enable row level security;
   alter table domovina_ai.watch_sessions enable row level security;
   alter table domovina_ai.favorites enable row level security;
   alter table domovina_ai.handoff_tokens enable row level security;
   alter table domovina_ai.onboarding_events enable row level security;

10) Output `select 'OK 02' as status;`
```

---

## PostgREST exposure — kritično

Bez ovog Flutter klijent ne vidi nove tablice:

```bash
# Coolify Supabase service env:
PGRST_DB_SCHEMAS=public,domovina_ai
# Restart PostgREST container.
```

Provjera:
```bash
curl https://api.domovina.ai/rest/v1/?apikey=$ANON_KEY | jq '.definitions | keys'
# Treba sadržavati "domovina_ai.watch_progress" itd.
```

Flutter koristi `supabase.schema('domovina_ai').from('watch_progress')`.

## Sanity check

```sql
\dt domovina_ai.*
-- 5 tablica.

-- Provjeri generated stupce na watch_progress:
\d domovina_ai.watch_progress
-- percent_complete i completed treba imati GENERATED.

-- View:
select * from domovina_ai.v_continue_watching limit 1;
-- 0 redova ali bez error-a.
```

## Smoke test

```sql
-- (kao service_role)
insert into auth.users (id, email, is_anonymous) values
  (gen_random_uuid(), 'test@example.com', false) returning id \gset
insert into public.profiles (id) values (:'id');

insert into domovina_ai.watch_progress
  (user_id, episode_id, channel_id, position_seconds, duration_seconds,
   episode_title, episode_thumbnail_url, last_device)
values
  (:'id', 'H-p2Hl6x7I0', 'kontra_kanal', 600, 3600,
   'Testna epizoda', 'https://cdn.domovina.ai/.../thumb.jpg', 'web');

select percent_complete, completed from domovina_ai.watch_progress
where user_id = :'id';
-- 16.67, false

-- Continue watching view:
select episode_id, episode_title, position_seconds
from domovina_ai.v_continue_watching where user_id = :'id';
-- 1 red.

delete from auth.users where email='test@example.com';
```

## Što ide u sljedeći korak

- `03-triggers-functions.md` — `handle_new_user`, `handle_user_promoted`, `generate_unique_slug`, `has_role_on_account`, `is_account_member`, `log_event`, `guard_slug_immutable`.
