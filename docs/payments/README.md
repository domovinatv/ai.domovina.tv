# Payments — RevenueCat + Web Billing integration

Permanent design + implementation docs for adding subscriptions to **domovina.ai**.
The app is a single Flutter codebase (iOS / Android / Android TV / macOS / Web),
live on the [App Store](https://apps.apple.com/us/app/domovina-ai/id6781716801)
(`ai.domovina`, id `6781716801`) and [Google Play](https://play.google.com/store/apps/details?id=ai.domovina)
(`ai.domovina`), with the web build in production at https://domovina.ai/.

As of writing there is **no billing of any kind** (no RevenueCat, no Stripe, no
App Store / Play products). Pinka (EURe/SEPA creator donations) exists but is a
separate concern — it is *not* a user subscription and is out of scope here.

## The core decision

**One billing system of record: RevenueCat, across every platform.**

| Platform | Purchase rail | Why |
|---|---|---|
| iOS / macOS | RevenueCat SDK → StoreKit 2 | Apple requires IAP for in-app digital goods |
| Android / Android TV | RevenueCat SDK → Google Play Billing | Play requires IAP |
| Web (domovina.ai) | **RevenueCat Web Billing** (Stripe-backed, RC-managed) | `purchases_flutter` has no web support; redirect to RC-hosted checkout |

Everything funnels into **one entitlement** (`domovina_plus`) and **one webhook**
that writes entitlement state into **Supabase Postgres**. The Flutter app reads
that Supabase row on *all* platforms — so there is a single, consistent source of
truth, and the web build needs no payment SDK at all. On mobile the RevenueCat
SDK additionally gives an optimistic instant unlock; Supabase stays authoritative.

This minimizes moving parts (one webhook, one entitlement model) and lets the
[RevenueCat AI Toolkit + MCP](https://github.com/RevenueCat/ai-toolkit) drive most
of the RevenueCat-side provisioning. See [`architecture.md`](./architecture.md) for
the alternative (RevenueCat mobile + Stripe-direct web) and why we did not pick it.

## Documents

| File | What it covers |
|---|---|
| [`pricing-and-tiers.md`](./pricing-and-tiers.md) | Proposed Free vs **Domovina Plus** model, tier→entitlement→feature matrix, what is IAP vs not (Creator/API stay off-IAP) |
| [`architecture.md`](./architecture.md) | Platforms→rail, entitlement model, `app_user_id` strategy, webhook→Supabase, data model (SQL + RLS), secrets, sequence diagram |
| [`provisioning.md`](./provisioning.md) | Step-by-step: RevenueCat project/apps/products/entitlements/offerings, App Store Connect, Play Console, Web Billing, secrets, webhook registration — incl. the **manual gaps** no API covers |
| [`implementation-plan.md`](./implementation-plan.md) | Phased, AI-executable task plan with files-to-touch + acceptance criteria — this is what an autonomous Claude Code session runs |

## Status

Code (branch `feature/revenuecat-billing`) is complete; remaining boxes are
owner/store actions with no API. See the PR for the full human-step list.

- [ ] Pricing confirmed by owner (numbers in `pricing-and-tiers.md` are proposals)
- [x] RevenueCat project + entitlement (`domovina_plus`) + 3 products + `default` offering + webhook provisioned (TestStore app; iOS/Android/Web-Billing apps are human steps)
- [ ] App Store Connect products created (+ Paid Apps agreement, first-IAP submission) — **human**
- [ ] Play Console products created (mind the one-time/lifetime Billing-Library caveat) — **human**
- [ ] RevenueCat Web Billing connected to Stripe — **human**
- [x] Supabase `subscriptions` table + RLS migration written in **domovina-api** (`supabase/migrations/20260628120000_revenuecat_subscriptions.sql`, PR #1) — apply with `scripts/db-migrate.sh`
- [x] Flutter SDK + RevenueCatService + entitlement state wired (web/TV bypass the SDK)
- [x] Paywall UI + feature gates (additive; cross-device-sync gating left as an owner decision)
- [x] Cloudflare Worker webhook → Supabase implemented + unit-tested (`scripts/test-revenuecat-webhook.mjs`); **set secrets + deploy** = human
- [x] TestStore webhook E2E unit-tested; **live sandbox purchase E2E** = human (needs store products + secrets)
- [ ] PRODUCTION env flip (`REVENUECAT_REQUIRE_PRODUCTION=true` + live keys) — **human, do last**

## Guardrails (apply to every change here)

- **`app_user_id` = Supabase `auth.users.id` (UUID).** Call `Purchases.logIn(uid)`
  right after Supabase auth resolves, including already-signed-in sessions.
- **No secrets in the repo.** Publishable SDK keys (`appl_…`/`goog_…`) are public
  by design and travel via `--dart-define`; the webhook shared secret and Supabase
  **service-role** key live only as Cloudflare Worker secrets.
- **Webhook is the only writer of entitlement state.** It validates the incoming
  `app_user_id` as a real UUID before touching any row, deep-merges only
  server-owned fields, and gates SANDBOX vs PRODUCTION.
- **Don't paywall core content.** Playback + pre-computed AI assets stay free
  (brand promise + simpler store review). Plus sells convenience, not access.
