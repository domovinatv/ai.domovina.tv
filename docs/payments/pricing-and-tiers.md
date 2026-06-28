# Pricing & tiers

> Numbers below are a **proposal** grounded in the app's actual features. Confirm
> with the owner before provisioning store products — prices are hard to change
> after launch (especially the lifetime tier).

## Positioning

domovina.ai is not a podcast aggregator — it's a **podcast enrichment archive**:
diarized transcripts, AI summaries/articles, Magisterium (Catholic) analysis, and
semantic search over ~1,843 episodes / ~92k chunks. Almost all of that is
**pre-computed and served from CDN** — there is no per-use LLM cost to most
features. The only real-time compute is semantic search.

Two consequences for pricing:

1. **Don't meter what's pre-computed.** Summaries, articles, Magisterium, transcripts
   are the brand promise; gating them hurts the mission and complicates store review.
2. **Sell convenience + identity, not access.** The audience (Croatian diaspora,
   faith communities, researchers) has a strong *support-the-homeland-archive*
   motive — a "Supporter / Founder" framing converts better here than a feature wall.

## Tiers

### Free (today's default — stays generous)

- Unlimited playback (audio + video), all platforms incl. Android TV
- All pre-computed AI assets when they exist: summaries, articles, outlines,
  Magisterium, diarized transcripts
- Semantic search, capped at a **daily query limit** (e.g. 100/day) and default
  result count (12)
- Watch progress + favorites — **local only** (no cross-device sync)
- HR content; EN where a translation already exists
- Pinka donations (unchanged)

### Domovina Plus — the subscription (one entitlement: `domovina_plus`)

Everything in Free, plus convenience + supporter status:

| Benefit | Notes / where it hooks in |
|---|---|
| **Cross-device sync** of favorites + watch history | `favorites_service` / `watch_progress_service` already exist — flip on Supabase sync behind the entitlement |
| **Offline downloads** | media already on CDN; add cache management |
| **Transcript / summary export** (PDF, Markdown, DOCX) | SRT/summary already parsed in memory |
| **Unlimited semantic search** + larger result sets | lift the Free daily cap |
| **EN-first** | EN translations always shown when present (early access before general rollout) |
| **Full Magisterium v2** + prompt visibility | already pre-computed; reveal the detailed view |
| **Supporter badge** + name in a credits/wall | identity reward, ties to mission |

#### Proposed prices (EUR — primary market is HR/EU + diaspora)

| Package | Type | Price | Store product id (suggested) |
|---|---|---|---|
| Monthly | auto-renewable | **€4.99 / mo** | `domovina_plus_monthly` |
| Annual | auto-renewable | **€39.99 / yr** (~33% off) | `domovina_plus_annual` |
| Lifetime "Founder" | non-consumable | **€99.99 once** | `domovina_plus_lifetime` |

RevenueCat offering `default` → packages `$rc_monthly`, `$rc_annual`, `$rc_lifetime`,
all granting the `domovina_plus` entitlement. Optionally a **7-day free trial** on
the monthly/annual subscriptions (introductory offer) — recommended for conversion.

### Out of scope for IAP (document, don't build into RevenueCat)

These are **not** app-store subscriptions and must not be modeled as IAP — Apple/Google
take a cut only on in-app digital goods, and these are neither:

- **Creator tier** — channel ownership claim (YouTube OAuth + Certilia KYC) + Pinka
  payouts. Already partly built. Keep it **free to claim**; monetization is Pinka,
  not RevenueCat. (App Store guideline 3.1.3(b)/3.1.5 — physical/creator payouts are
  outside IAP.)
- **Developer / API tier** — paid access to the public search API (`mcp.domovina.ai`).
  This is consumption **outside** the app → bill with **Stripe metered billing on the
  web**, not IAP. Separate, later track; not part of this integration.

## Entitlement → feature mapping (single source of truth for gating)

```
free            → playback, pre-computed AI assets, search (capped), local-only state
domovina_plus   → + sync, offline, export, unlimited search, EN-first, magisterium v2, badge
```

The app gates a feature by checking the active entitlement (see
[`architecture.md`](./architecture.md) → "Reading entitlement state"). Every gate
reads the same `domovina_plus` boolean — no per-feature product logic in the client.

## Store-review notes (already mostly satisfied)

- **Restore Purchases** button on the paywall — required by Apple. (New.)
- **Manage Subscription** link — deep-link to system manage-subscriptions sheet. (New.)
- **Account deletion** — already implemented (App Store 5.1.1(v)).
- **Free tier remains fully usable** without paying — avoids "app is unusable
  without purchase" rejections.
