# Implementation plan (AI-executable)

Phased plan an autonomous Claude Code session runs **in this repo**. Each phase lists
files to touch and acceptance criteria. Work on a branch (`feature/revenuecat-billing`),
keep commits scoped per phase, open a PR at the end. Run `flutter analyze` after each
code phase. **Do not commit secrets.** Read `architecture.md` + `pricing-and-tiers.md`
+ `provisioning.md` first.

Provisioning (RevenueCat dashboard + stores, partly human) is **Phase 0** and may run
in parallel via the RevenueCat MCP — but code phases 1–6 can be built and unit-tested
against RevenueCat **TestStore** before live store products exist.

---

## Phase 0 — Provisioning (human + MCP) · prerequisite

Follow `provisioning.md`. Minimum to unblock code: RevenueCat project + 3 apps +
`domovina_plus` entitlement + 3 products + `default` offering + **TestStore** enabled,
and the webhook registered. Live store products can land later.

**Acceptance:** MCP `get-offerings` returns the `default` offering with 3 packages,
each referencing a product attached to `domovina_plus`.

---

## Phase 1 — Supabase data model

- Add migration creating `domovina_ai.subscriptions` + RLS exactly as in
  `architecture.md` (select-own policy; no client write policy).
- Place it alongside existing schema docs/migrations (`docs/backend-prompts/` style or
  the repo's migration mechanism).

**Acceptance:** table exists; an authenticated user can `select` only their own row;
client `insert/update` is denied; service role can upsert.

---

## Phase 2 — Flutter SDK + RevenueCatService

- Add `purchases_flutter` (latest 10.x) to `pubspec.yaml`. **Guard web/TV**: do not
  initialize the SDK where it's unsupported (web). Detect platform like the existing
  TV detection in `main.dart`.
- New `lib/services/revenue_cat_service.dart`:
  - `configure()` with the platform publishable key from `--dart-define`
    (`RC_PUBLIC_SDK_KEY_IOS` / `RC_PUBLIC_SDK_KEY_ANDROID`); no-op on web.
  - `logIn(uid)` / `logOut()` wired to Supabase auth state in `auth_service.dart` —
    call `logIn` after auth resolves **including already-signed-in launch sessions**.
  - `getOfferings()`, `purchasePackage()`, `restorePurchases()`.
  - expose a `CustomerInfo` stream for optimistic unlock (mobile only).

**Acceptance:** on a mobile debug build with TestStore keys, `getOfferings()` returns 3
packages; signing in calls `Purchases.logIn(<supabase uuid>)`; web build compiles and
runs with the SDK fully bypassed.

---

## Phase 3 — Entitlement state (all platforms)

- New `lib/services/entitlement_service.dart` exposing `ValueNotifier<bool> isPlus`:
  - subscribe to the user's `domovina_ai.subscriptions` row via the Supabase client
    (authoritative, every platform);
  - on mobile, also fold in optimistic `CustomerInfo.entitlements.active['domovina_plus']`.
- Gate strictly on the **entitlement**, never a product id.

**Acceptance:** flipping the Supabase row to `status='active', entitlement='domovina_plus'`
flips `isPlus` to true on web and mobile; a mobile sandbox purchase unlocks optimistically
before the row updates.

---

## Phase 4 — Paywall + purchase flow

- New paywall screen + an `UpgradeTrigger` enum for the gated entry points (offline,
  export, sync toggle, search-cap hit). Render the 3 packages from the `default` offering.
- **Mobile:** `purchasePackage()` via the SDK; show **Restore Purchases** + a
  **Manage Subscription** deep link (store requirement).
- **Web:** no SDK — redirect to the **RevenueCat Web Billing hosted checkout**, passing
  the Supabase UUID as the customer id; on return, the webhook→Supabase row drives unlock.
- Add a route (e.g. `/subscribe`) in `lib/router/app_router.dart`.
- Gate the paywall behind a real (non-anonymous) account; prompt link-account first.

**Acceptance:** mobile sandbox purchase completes and unlocks; web redirect reaches the
hosted checkout with the correct customer id; restore works; anonymous users are prompted
to link before purchase.

---

## Phase 5 — Webhook (Cloudflare Worker → Supabase)

- Add `POST /api/revenuecat/webhook` to `web/_worker.js` (or a standalone Worker).
- Implement exactly per `architecture.md` → "Webhook handler" + "Security invariants":
  bearer-auth against `REVENUECAT_WEBHOOK_AUTH`; **UUID-validate** `app_user_id`;
  SANDBOX/PRODUCTION gate; event→status map; product allowlist; service-role upsert into
  `domovina_ai.subscriptions`; fast `200`.
- Secrets via `wrangler secret put` (`REVENUECAT_WEBHOOK_AUTH`, `SUPABASE_SERVICE_ROLE_KEY`).

**Acceptance:** a RevenueCat **test webhook** with a valid UUID upserts the row; a crafted
non-UUID `app_user_id` is rejected without any DB write; a non-allowlisted `product_id`
is ignored; replaying RENEWAL is idempotent.

---

## Phase 6 — Feature gating

Wire each Plus benefit to `isPlus` (see `pricing-and-tiers.md` matrix):
- favorites + watch-history **cross-device sync** (flip on the existing services behind `isPlus`);
- **offline download**, **transcript/summary export**, **EN-first**, **Magisterium v2**
  detail, **unlimited search** (lift the Free daily cap), **Supporter badge**.
- Free tier must stay fully usable; gates show the paywall, never a dead end.

**Acceptance:** with `isPlus=false` each gated feature shows the paywall; with `isPlus=true`
each unlocks; Free playback + pre-computed AI assets remain unaffected either way.

---

## Phase 7 — Testing & store-readiness

- RevenueCat **TestStore** for deterministic CI; **App Store sandbox** + **Play internal
  testing** for real-receipt runs.
- Integration test for the paywall (renders packages; restore; degrades gracefully when
  the SDK/keys are absent — important since web has no SDK).
- Confirm store-review items: Restore Purchases, Manage Subscription, account deletion
  (already present), free tier usable without paying.

**Acceptance:** integration tests green; a sandbox purchase on each mobile store unlocks
via the webhook; web hosted-checkout purchase unlocks via the webhook.

---

## Phase 8 — Production flip (human-gated)

Swap TestStore/sandbox keys → live; flip the webhook env gate to require `PRODUCTION`;
ensure live store products are "Ready"/"Active" (MCP `get-product-store-state`); ship
builds. Update `README.md` status checkboxes.

---

## Definition of done

- One entitlement (`domovina_plus`), one webhook, one Supabase mirror row read on all platforms.
- No secrets in the repo; service-role key only in the Worker.
- Free tier unchanged and fully usable; Plus features gated solely on the entitlement.
- Sandbox E2E verified on iOS, Android, and web before the production flip.
