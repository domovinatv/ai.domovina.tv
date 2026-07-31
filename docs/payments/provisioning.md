# Provisioning

What must exist in RevenueCat and in each store before code can transact. Split into
**what the RevenueCat MCP / AI Toolkit can automate** and the **manual gaps no API covers**.

> **Ovo je plan.** Stvarno stanje — konkretni ID-evi, kredencijali, što je
> verificirano i kojeg datuma, plus zamke otkrivene pri izvedbi — živi u
> [`provisioning-state.md`](provisioning-state.md). Prije bilo kakvog rada na
> naplati pročitaj taj dokument.

> Install once (already done globally on the dev machine): the RevenueCat AI Toolkit
> (`claude plugin marketplace add RevenueCat/ai-toolkit` → install `RevenueCat`) which
> bundles the hosted MCP at `https://mcp.revenuecat.ai/mcp`. Authenticate it via `/mcp`
> (OAuth) before provisioning. The MCP exposes `create-app`, `create-product`,
> `create-entitlement`, `create-offering`, `get-product-store-state`, etc.

## 1. RevenueCat side — mostly MCP-automatable

Order matters (RevenueCat enforces dependencies):

1. **Project** — reuse an existing RevenueCat project or create "DOMOVINA".
2. **Apps** (3):
   - iOS app → App Store, bundle `ai.domovina`
   - Android app → Play Store, package `ai.domovina`
   - **Web Billing app** (RC Billing) → connect the Stripe account RevenueCat manages
3. **Entitlement** — `domovina_plus` (single entitlement for the whole subscription).
4. **Products** (3) — referencing the store product ids:
   - `domovina_plus_monthly` (auto-renewable)
   - `domovina_plus_annual` (auto-renewable)
   - `domovina_plus_lifetime` (non-consumable)
   - each attached to the `domovina_plus` entitlement
5. **Offering** `default` → packages `$rc_monthly`, `$rc_annual`, `$rc_lifetime`.
6. **Webhook** — point at `https://domovina.ai/api/revenuecat/webhook`, set the
   Authorization header to `REVENUECAT_WEBHOOK_AUTH` (same value as the Worker secret).
7. **Store credentials into RevenueCat**: upload the Apple In-App-Purchase Key (`.p8`,
   Key ID + Issuer ID) and the Google Play service-account JSON so RC can validate
   receipts. These go in the **dashboard**, never in the repo.

Verify with the MCP `get-product-store-state` tool — products must read "Ready to
Submit" (Apple) / "Active" (Play) or the SDK won't return them, even in sandbox.

## 2. App Store Connect (iOS / macOS) — partly API, partly manual

- App id `6781716801`, bundle `ai.domovina`.
- Create a **subscription group** (e.g. "Domovina Plus") and two **auto-renewable**
  subscriptions (`domovina_plus_monthly`, `domovina_plus_annual`) + one
  **non-consumable** (`domovina_plus_lifetime`). Set EUR pricing per
  `pricing-and-tiers.md`. Optionally add a 7-day introductory free trial.
- Generate an **In-App Purchase Key** (Users & Access → Integrations) → give to RevenueCat.

**Manual gaps (no API):**
- **Paid Applications agreement** must be signed (Agreements/Tax/Banking) — dashboard only.
- The **first IAP must be submitted attached to an app binary** via App Store Connect;
  only subsequent IAPs can go API-only.
- Each IAP needs a **review screenshot**; uploading it is awkward/manual.

## 3. Google Play Console (Android / Android TV) — partly API, partly manual

- Package `ai.domovina` (already live).
- **Subscriptions:** create `domovina_plus` subscription with **base plans**
  `monthly` (P1M) and `annual` (P1Y) via Monetization → Subscriptions. New base plans
  start in **draft** until activated.
- **Lifetime (one-time product):** create via Monetization → one-time products.
  ⚠️ **Known blocker (carried from prior projects):** one-time / managed products can
  require a **Google Play Billing Library v8** build uploaded first, and the service
  account may need the right billing permission, before the product can be created or
  surfaced. If lifetime creation fails with a permission error, ship a PBL-8 build to a
  track first, then create the product. (Deadline pressure: new apps must ship PBL v8+
  by Aug 31 2026.)
- Create a **service account** (Google Cloud) with Play access → JSON → give to RevenueCat.
- Set up **Real-time Developer Notifications** (Pub/Sub topic) in Play → Monetization
  setup, so RevenueCat gets server-side renewal events.

**Manual gaps:** activating products to "Active"; the BG-region / EUR migration quirks
seen historically; first release/track requirements.

## 4. RevenueCat Web Billing (web) — RC + Stripe dashboard

- In RevenueCat, configure the **Web Billing** app: connect/authorize the Stripe account,
  create the matching products/prices (monthly/annual/lifetime in EUR), and enable the
  **hosted checkout / paywall link**. The Flutter web app will redirect users to that
  hosted checkout (Flutter web can't run `purchases_flutter`).
- Confirm Web Billing purchases emit the **same webhook events** to the same endpoint,
  carrying the same `app_user_id` (the Supabase UUID you pass into the checkout link).

## 5. Secrets to set (no values in repo)

| Secret | Set where |
|---|---|
| `RC_PUBLIC_SDK_KEY_IOS`, `RC_PUBLIC_SDK_KEY_ANDROID` | `.env` (local) + `scripts/build-mobile-release.sh` `--dart-define` + CI |
| `REVENUECAT_WEBHOOK_AUTH` | `wrangler secret put` (Worker) **and** RevenueCat webhook header |
| `SUPABASE_SERVICE_ROLE_KEY` | `wrangler secret put` (Worker) |
| Apple `.p8` (+ Key ID/Issuer ID), Play service-account JSON | RevenueCat dashboard |

## 6. Environment flip (do last)

The webhook accepts `SANDBOX` during development. Before launch, flip it to require
`PRODUCTION`, and swap the SDK keys / store products to live. Keep a sandbox path for
ongoing QA via RevenueCat **TestStore** (synthetic store, no real store round-trip).

## Provisioning order checklist

1. RevenueCat project + 3 apps + entitlement + products + offering + webhook (MCP)
2. App Store Connect products + IAP key + Paid Apps agreement
3. Play Console products + service account + RTDN (+ PBL-8 build if lifetime blocked)
4. Web Billing (Stripe) connected in RevenueCat
5. Store credentials uploaded into RevenueCat
6. Secrets set (Worker + build + RC)
7. Verify product store-state via MCP → all "Ready"/"Active"
8. Then run the code implementation (`implementation-plan.md`)
