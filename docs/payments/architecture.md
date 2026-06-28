# Architecture

How RevenueCat fits the domovina.ai substrate: a single Flutter app, Supabase
auth + Postgres, and a Cloudflare Pages Worker as the only edge compute. No
Firebase, no existing functions directory.

## Substrate (as found in the codebase)

| Concern | Reality | File(s) |
|---|---|---|
| App | Single Flutter app, all platforms | `pubspec.yaml`, `lib/main.dart` |
| App id | `ai.domovina` (iOS + Android, no flavors) | `ios/Runner.xcodeproj/project.pbxproj`, `android/app/build.gradle.kts` |
| Auth | Supabase GoTrue (Google, Apple, email magic-link, passkey, Certilia eID) | `lib/services/auth_service.dart` |
| User id | `auth.users.id` — stable UUID | — |
| DB | Self-hosted Supabase Postgres @ `api.domovina.ai` | `docs/schema.dbml`, `docs/backend-prompts/` |
| Edge compute | One Cloudflare Pages Worker (SPA routing, OG tags, Cal.com proxy) | `web/_worker.js` |
| Config | `--dart-define` at build + `.env` (gitignored) + Cloudflare secrets | `scripts/deploy.sh`, `wrangler.toml` |

## Billing rail per platform

```mermaid
flowchart TD
    subgraph App["Flutter app (one codebase)"]
      iOS["iOS / macOS"]
      Android["Android / Android TV"]
      Web["Web (domovina.ai)"]
    end
    iOS -->|purchases_flutter → StoreKit 2| RC["RevenueCat<br/>(system of record)"]
    Android -->|purchases_flutter → Play Billing| RC
    Web -->|redirect to RC-hosted checkout| WB["RevenueCat Web Billing<br/>(Stripe-backed)"]
    WB --> RC
    RC -->|webhook (entitlement events)| WK["Supabase Edge Function<br/>revenuecat-webhook"]
    WK -->|service-role write| DB[("Supabase Postgres<br/>domovina_ai.subscriptions")]
    App -->|read own row (RLS)| DB
    iOS -.optimistic CustomerInfo.-> App
    Android -.optimistic CustomerInfo.-> App
```

**Key idea:** the Supabase `subscriptions` row, written only by the webhook, is the
**universal entitlement source the app reads on every platform**. Web therefore needs
no payment SDK — it redirects to RevenueCat's hosted checkout and then reads the row.
On mobile the SDK's `CustomerInfo` gives an instant optimistic unlock; the Supabase
row remains authoritative (it survives reinstalls, cross-device, and web purchases).

### Why not Stripe-direct on web (the smpltsk pattern)?

A previous app (smpltsk) used RevenueCat for mobile + Stripe directly for web, with
a Cloud Function reconciling both into the DB. That works, but it means **two billing
systems, two webhooks, two product catalogs to keep in sync**. For a greenfield with
no Stripe yet, **RevenueCat Web Billing** keeps one entitlement model and one webhook,
and the RevenueCat MCP/AI Toolkit can provision most of it. We chose unification.
If a future requirement needs Stripe-native web (e.g. invoicing, the Developer API
tier), add it then — it's the documented fallback, not the default.

## `app_user_id` strategy

RevenueCat must alias its customer to a stable app identity so purchases follow the
user across devices and platforms.

- **Identifier:** Supabase `auth.users.id` (UUID). Immutable, globally unique.
- **On mobile:** call `Purchases.logIn(uid)` immediately after Supabase auth resolves
  — both on fresh sign-in *and* for already-signed-in sessions on launch. Call
  `Purchases.logOut()` on sign-out.
- **Anonymous users:** the app auto-signs-in anonymous Supabase users for casual
  browsing. **Do not** start a purchase for an anonymous user — gate the paywall
  behind "link your account first" so the purchase attaches to a durable identity.
- **Webhook trust:** the webhook receives `app_user_id` from RevenueCat and must
  re-validate it as a UUID before using it as a DB key (see Security invariants).

## Data model (Supabase Postgres)

New table — entitlement mirror, written only by the webhook, read by the app via RLS.

```sql
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

alter table domovina_ai.subscriptions enable row level security;

-- Users may read ONLY their own entitlement; nobody writes via the client.
create policy subscriptions_select_own
  on domovina_ai.subscriptions for select
  using (auth.uid() = user_id);
-- No insert/update/delete policy for authenticated/anon → only the service role
-- (used by the webhook worker) can write, because it bypasses RLS.
```

Notes:
- **One row per user** (primary key on `user_id`) — RevenueCat events are idempotent
  upserts keyed by the validated UUID.
- The webhook **deep-merges only the columns above** and never touches any app-owned
  data. If you later add an admin/comp override (e.g. a manually granted Plus), put it
  in a *separate* column/table the webhook does not write, mirroring the perfect_training
  pattern (server-owned vs admin-owned fields).

## Reading entitlement state (client)

A single repository exposes one boolean the whole app gates on:

- **All platforms:** subscribe to the user's `domovina_ai.subscriptions` row via the
  Supabase client; `isPlus = (status == 'active' && entitlement == 'domovina_plus')`.
- **Mobile only, optimistic:** also listen to `Purchases.addCustomerInfoUpdateListener`;
  if `customerInfo.entitlements.active` contains `domovina_plus`, unlock immediately
  while the webhook→Supabase round-trip catches up.
- Expose as e.g. `EntitlementService` / a `ValueNotifier<bool> isPlus` consumed by
  feature gates. Never gate on a specific product id — always on the entitlement.

## Webhook handler (Supabase Edge Function)

The webhook **writes** entitlement state to our Postgres for a logged-in user, so
per the backend-placement rule (`domovina-api/docs/backend-architecture.md`) it is
a **Supabase Edge Function** (`domovina-api/supabase/functions/revenuecat-webhook/`),
not a Cloudflare Pages worker route. This keeps the service-role key on Coolify
(auto-injected into the edge runtime) instead of duplicating it into Cloudflare,
and keeps the Cloudflare worker for frontend/OG/third-party-SaaS proxy duties only
(e.g. Cal.com). `verify_jwt = false` (server-to-server; we check the shared secret
ourselves). Decision logic is pure + unit-tested in `logic.ts` / `logic_test.ts`.

**Endpoint:** `POST https://api.domovina.ai/functions/v1/revenuecat-webhook`

**Flow:**
1. **Auth:** compare `Authorization` header against `REVENUECAT_WEBHOOK_AUTH`
   (a shared secret you set in RevenueCat's webhook config). Reject on mismatch (401).
2. Parse the event; read `event.app_user_id`, `event.type`, `event.environment`,
   `event.product_id`, `event.entitlement_ids`, `event.expiration_at_ms`, `event.store`.
3. **Validate `app_user_id` is a UUID** (strict regex) *before* using it as a key —
   blocks a malicious client from smuggling a crafted id to write another user's row.
4. **Environment gate:** while testing, accept `SANDBOX`; before launch, require
   `PRODUCTION` (store the env on the row for audit).
5. **Map event → status:**
   | event.type | status | entitlement |
   |---|---|---|
   | INITIAL_PURCHASE, RENEWAL, UNCANCELLATION, NON_RENEWING_PURCHASE, PRODUCT_CHANGE | `active` | `domovina_plus` |
   | CANCELLATION | (keep `active` until expiry) | `domovina_plus` |
   | EXPIRATION, BILLING_ISSUE (after grace) | `expired` | `null` |
6. **Allowlist** `product_id` against the three known products; ignore unknown ids.
7. **Write** with the service-role supabase-js client
   (`.schema('domovina_ai').from('subscriptions').upsert(row, { onConflict: 'user_id' })`).
   Service role bypasses RLS; upsert keyed on `user_id` is idempotent.
8. Return `200` quickly; RevenueCat retries non-2xx.

### Security invariants (do not regress)

- `app_user_id` MUST match `^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`
  before any DB access.
- The **service-role key lives only in the Supabase edge runtime env (Coolify)** —
  auto-injected, never shipped to the client, never in `--dart-define`, never in
  Cloudflare, never logged.
- The webhook writes **only** the entitlement columns; everything else is untouched.
- Reject events whose `product_id` isn't in the allowlist (defense against typos /
  cross-project leakage).

## Secrets & config

| Secret | Where | Public? |
|---|---|---|
| `RC_PUBLIC_SDK_KEY_IOS` (`appl_…`) | `--dart-define` at iOS/macOS build (`scripts/build-mobile-release.sh`) | Public by design |
| `RC_PUBLIC_SDK_KEY_ANDROID` (`goog_…`) | `--dart-define` at Android build | Public by design |
| `REVENUECAT_WEBHOOK_AUTH` | Supabase edge runtime env (Coolify) + RevenueCat webhook config | **Secret** |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase edge runtime env (Coolify) — auto-injected | **Secret** |
| `SUPABASE_URL` | Supabase edge runtime env — auto-injected | Safe |
| App Store In-App-Purchase Key (`.p8`), Play service-account JSON | uploaded **into RevenueCat dashboard**, not the repo | Secret |

Web Billing publishable config (Stripe) is managed inside RevenueCat — the Flutter web
build only needs the RC-hosted checkout URL/SDK key, no Stripe secret on the client.
