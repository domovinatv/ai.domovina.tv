#!/usr/bin/env node
// Unit test for the RevenueCat webhook handler in web/_worker.js.
//
// Loads the REAL worker source into a vm sandbox (no edits, no duplication),
// stubs global fetch to capture the Supabase upsert, and asserts the security
// invariants from docs/payments/architecture.md. Run: node scripts/test-revenuecat-webhook.mjs
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const src = readFileSync(new URL('../web/_worker.js', import.meta.url), 'utf8')
  // The only ESM export; rebind so the file runs as a plain script in vm.
  .replace('export default {', 'globalThis.__worker = {');

let calls = [];
const mockFetch = async (url, opts) => {
  calls.push({ url: String(url), opts });
  return new Response(null, { status: 204 });
};

const ctx = vm.createContext({
  Response, Request, Headers, URL, console, Date, fetch: mockFetch,
});
vm.runInContext(src, ctx);
const handle = ctx.handleRevenueCatWebhook;
if (typeof handle !== 'function') {
  console.error('FAIL: handleRevenueCatWebhook not found in worker');
  process.exit(1);
}

const SECRET = 'test-secret-123';
const ENV = {
  REVENUECAT_WEBHOOK_AUTH: SECRET,
  SUPABASE_SERVICE_ROLE_KEY: 'srk_test',
  SUPABASE_URL: 'https://api.domovina.ai',
};
const UUID = '11111111-1111-1111-1111-111111111111';

function req(body, { auth = SECRET } = {}) {
  return new Request('https://domovina.ai/api/revenuecat/webhook', {
    method: 'POST',
    headers: { Authorization: auth, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}
function event(over = {}) {
  return {
    event: {
      type: 'INITIAL_PURCHASE',
      app_user_id: UUID,
      environment: 'SANDBOX',
      product_id: 'domovina_plus_annual',
      entitlement_ids: ['domovina_plus'],
      period_type: 'NORMAL',
      expiration_at_ms: 1893456000000,
      store: 'APP_STORE',
      ...over,
    },
  };
}

let passed = 0, failed = 0;
function ok(cond, msg) {
  if (cond) { passed++; console.log(`  ok  ${msg}`); }
  else { failed++; console.error(`FAIL  ${msg}`); }
}
const upserts = () => calls.filter((c) => c.url.includes('/rest/v1/subscriptions'));

async function run() {
  // 1. Auth mismatch → 401, no DB.
  calls = [];
  let r = await handle(req(event(), { auth: 'wrong' }), ENV);
  ok(r.status === 401, 'wrong Authorization → 401');
  ok(upserts().length === 0, '  …no DB write on auth failure');

  // 2. Valid UUID INITIAL_PURCHASE → 200 + active upsert.
  calls = [];
  r = await handle(req(event()), ENV);
  ok(r.status === 200, 'valid INITIAL_PURCHASE → 200');
  const u = upserts();
  ok(u.length === 1, '  …one upsert');
  const row = u.length ? JSON.parse(u[0].opts.body)[0] : {};
  ok(row.user_id === UUID, '  …row keyed by validated UUID');
  ok(row.status === 'active' && row.entitlement === 'domovina_plus',
    '  …status active + domovina_plus');
  ok(u[0].opts.headers['Content-Profile'] === 'domovina_ai',
    '  …writes into domovina_ai schema');
  ok(u[0].url.includes('on_conflict=user_id'), '  …upsert keyed on user_id');

  // 3. Non-UUID app_user_id → 400, no DB (security invariant).
  calls = [];
  r = await handle(req(event({ app_user_id: '$RCAnonymousID:abc123' })), ENV);
  ok(r.status === 400, 'non-UUID app_user_id → 400');
  ok(upserts().length === 0, '  …no DB write for crafted/anonymous id');

  // 4. Non-allowlisted product → 200 ignored, no DB.
  calls = [];
  r = await handle(req(event({ product_id: 'evil_product' })), ENV);
  ok(r.status === 200, 'non-allowlisted product → 200 (ignored)');
  ok(upserts().length === 0, '  …no DB write for unknown product');

  // 5. Other-entitlement event → 200 ignored.
  calls = [];
  r = await handle(req(event({ entitlement_ids: ['some_other'] })), ENV);
  ok(r.status === 200, 'other entitlement → 200 (ignored)');
  ok(upserts().length === 0, '  …no DB write for other entitlement');

  // 6. EXPIRATION → expired + null entitlement.
  calls = [];
  r = await handle(req(event({ type: 'EXPIRATION' })), ENV);
  const er = JSON.parse(upserts()[0].opts.body)[0];
  ok(r.status === 200 && er.status === 'expired' && er.entitlement === null,
    'EXPIRATION → expired + entitlement null');

  // 7. CANCELLATION keeps access until expiry.
  calls = [];
  r = await handle(req(event({ type: 'CANCELLATION' })), ENV);
  const cr = JSON.parse(upserts()[0].opts.body)[0];
  ok(cr.status === 'active' && cr.entitlement === 'domovina_plus',
    'CANCELLATION → stays active until expiry');

  // 8. RENEWAL replay is idempotent (both 200, both upsert merge-duplicates).
  calls = [];
  const r1 = await handle(req(event({ type: 'RENEWAL' })), ENV);
  const r2 = await handle(req(event({ type: 'RENEWAL' })), ENV);
  ok(r1.status === 200 && r2.status === 200, 'RENEWAL replay → both 200');
  ok(upserts().every((c) =>
    c.opts.headers['Prefer'].includes('merge-duplicates')),
    '  …idempotent upsert (merge-duplicates)');

  // 9. Production gate: SANDBOX rejected when REQUIRE_PRODUCTION=true.
  calls = [];
  r = await handle(req(event()), { ...ENV, REVENUECAT_REQUIRE_PRODUCTION: 'true' });
  ok(r.status === 200 && upserts().length === 0,
    'REQUIRE_PRODUCTION=true → SANDBOX ignored, no write');

  // 10. TestStore product id is accepted (sandbox E2E).
  calls = [];
  r = await handle(req(event({ product_id: 'yearly', entitlement_ids: ['domovina_plus'] })), ENV);
  ok(r.status === 200 && upserts().length === 1,
    'TestStore product (yearly) → accepted');

  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

run();
