-- 001_subscriptions.sql — RevenueCat entitlement mirror
--
-- One row per user, written ONLY by the Cloudflare Worker webhook
-- (POST /api/revenuecat/webhook) via the Supabase service role. The Flutter app
-- reads its own row on every platform (web/iOS/Android/macOS/TV) and gates the
-- `domovina_plus` entitlement on it. See docs/payments/architecture.md.
--
-- Idempotent: safe to re-run. Apply against the shared self-hosted Supabase
-- backend (api.domovina.ai) — schema work is owned by the domovina-api repo, so
-- land this through that repo's migration mechanism. domovina_ai is already
-- exposed via PGRST_DB_SCHEMAS=public,domovina_ai.

create schema if not exists domovina_ai;

create table if not exists domovina_ai.subscriptions (
  user_id              uuid primary key references auth.users(id) on delete cascade,
  rc_app_user_id       text not null,
  status               text not null default 'free',   -- 'active' | 'expired' | 'free'
  entitlement          text,                            -- 'domovina_plus' when active, else null
  product_id           text,                            -- e.g. 'domovina_plus_annual'
  store                text,                            -- 'app_store' | 'play_store' | 'rc_billing'
  period_type          text,                            -- 'normal' | 'trial' | 'intro'
  current_period_end   timestamptz,                     -- null for lifetime
  rc_event_type        text,                            -- last event applied (audit)
  environment          text,                            -- 'SANDBOX' | 'PRODUCTION'
  updated_at           timestamptz not null default now()
);

-- The app only ever reads its own row; a lookup by user_id is the PK so no extra
-- index is needed. Keep an index on status for any future "active subscribers"
-- admin queries (cheap, harmless).
create index if not exists ix_subscriptions_status
  on domovina_ai.subscriptions(status);

alter table domovina_ai.subscriptions enable row level security;

-- Users may read ONLY their own entitlement row.
drop policy if exists subscriptions_select_own on domovina_ai.subscriptions;
create policy subscriptions_select_own
  on domovina_ai.subscriptions for select
  using (auth.uid() = user_id);

-- No insert/update/delete policy for authenticated/anon → the client can never
-- write entitlement state. Only the service role (used by the webhook worker)
-- can write, because it bypasses RLS.

-- PostgREST grants: SELECT for end users (RLS still filters to own row); the
-- service role already has full access and bypasses RLS.
grant usage on schema domovina_ai to anon, authenticated;
grant select on domovina_ai.subscriptions to anon, authenticated;

select 'OK 001_subscriptions' as status;
