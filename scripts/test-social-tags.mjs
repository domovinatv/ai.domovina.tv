/**
 * Testira server-side OG/social tagove za sve poznate epizode.
 * Verificira i PRISUTNOST i ISPRAVNOST vrijednosti.
 *
 * Korištenje:
 *   node scripts/test-social-tags.mjs                        # produkcija
 *   node scripts/test-social-tags.mjs http://localhost:8080  # lokalni dev
 */

const VIDEO_IDS = [
  'H-p2Hl6x7I0',
  'AoXN-3Mkmew',
  'b-nls1ck8EE',
  'oxq1U0xypu8',
  'MGLq9v3AtvE',
  'KvIhy5SESYs',
];

const BASE = (process.argv[2] || 'https://domovina.ai').replace(/\/$/, '');

const GREEN  = '\x1b[32m';
const RED    = '\x1b[31m';
const YELLOW = '\x1b[33m';
const BOLD   = '\x1b[1m';
const RESET  = '\x1b[0m';

const ok   = (s) => `${GREEN}✓${RESET} ${s}`;
const fail = (s) => `${RED}✗${RESET} ${s}`;
const warn = (s) => `${YELLOW}!${RESET} ${s}`;

function extractMeta(html, attr, val) {
  const re = new RegExp(
    `<meta[^>]+${attr}=["']${val}["'][^>]+content=["']([^"']*)["']` +
    `|<meta[^>]+content=["']([^"']*)["'][^>]+${attr}=["']${val}["']`,
    'i'
  );
  const m = html.match(re);
  return m ? (m[1] ?? m[2]) : null;
}

function extractTitle(html) {
  const m = html.match(/<title>([^<]*)<\/title>/i);
  return m ? m[1] : null;
}

function extractCanonical(html) {
  const m = html.match(/<link[^>]+rel=["']canonical["'][^>]+href=["']([^"']*)["']/i);
  return m ? m[1] : null;
}

function countMeta(html, attr, val) {
  const re = new RegExp(`<meta[^>]+${attr}=["']${val}["']`, 'gi');
  return (html.match(re) || []).length;
}

async function testVideo(ytId) {
  const url = `${BASE}/v/${ytId}`;
  console.log(`\n${BOLD}── ${ytId}${RESET}  ${url}`);

  let html;
  try {
    const res = await fetch(url, {
      headers: { Accept: 'text/html', 'User-Agent': 'DominovinaBot/1.0 (social-tag-tester)' },
      redirect: 'follow',
    });
    if (!res.ok) {
      console.log(`  ${fail(`HTTP ${res.status}`)}`);
      return { ytId, passed: 0, failed: 1 };
    }
    html = await res.text();
  } catch (e) {
    console.log(`  ${fail(`Network error: ${e.message}`)}`);
    return { ytId, passed: 0, failed: 1 };
  }

  let passed = 0;
  let failed = 0;

  const check = (label, value, expected) => {
    const label20 = label.padEnd(26);
    if (value === null || value.trim() === '') {
      console.log(`  ${fail(label20)} NEDOSTAJE`);
      failed++;
      return;
    }
    if (expected !== undefined && !expected(value)) {
      const preview = value.length > 70 ? value.slice(0, 67) + '…' : value;
      console.log(`  ${fail(label20)} "${preview}"`);
      failed++;
      return;
    }
    const preview = value.length > 70 ? value.slice(0, 67) + '…' : value;
    console.log(`  ${ok(label20)} "${preview}"`);
    passed++;
  };

  const expectedCanonical = `https://domovina.ai/v/${ytId}`;
  const expectedThumb = `https://cdn.domovina.ai/images/${ytId}/thumbnail.png`;

  const title      = extractTitle(html);
  const desc       = extractMeta(html, 'name', 'description');
  const ogTitle    = extractMeta(html, 'property', 'og:title');
  const ogDesc     = extractMeta(html, 'property', 'og:description');
  const ogImage    = extractMeta(html, 'property', 'og:image');
  const ogUrl      = extractMeta(html, 'property', 'og:url');
  const ogType     = extractMeta(html, 'property', 'og:type');
  const ogSite     = extractMeta(html, 'property', 'og:site_name');
  const twCard     = extractMeta(html, 'name', 'twitter:card');
  const twTitle    = extractMeta(html, 'name', 'twitter:title');
  const twImage    = extractMeta(html, 'name', 'twitter:image');
  const canonical  = extractCanonical(html);

  // Provjeri prisutnost i ispravnost vrijednosti
  check('<title>',           title,    (v) => v.includes('– Domovina.ai') && v !== '– Domovina.ai');
  check('description',       desc,     (v) => v !== 'A new Flutter project.' && v.length > 10);
  check('og:title',          ogTitle,  (v) => v !== 'Domovina.ai' && v.length > 3);
  check('og:description',    ogDesc,   (v) => v.length > 10);
  check('og:image',          ogImage,  (v) => v === expectedThumb);
  check('og:url',            ogUrl,    (v) => v === expectedCanonical);
  check('og:type',           ogType,   (v) => v === 'video.other');
  check('og:site_name',      ogSite,   (v) => v === 'Domovina.ai');
  check('twitter:card',      twCard,   (v) => v === 'summary_large_image');
  check('twitter:title',     twTitle,  (v) => v !== 'Domovina.ai' && v.length > 3);
  check('twitter:image',     twImage,  (v) => v === expectedThumb);
  check('canonical',         canonical,(v) => v === expectedCanonical);

  // Upozori ako postoji više istih tagova (duplicati)
  const dupChecks = [
    ['property', 'og:title'], ['property', 'og:type'],
    ['name', 'twitter:card'], ['name', 'twitter:title'],
  ];
  for (const [attr, val] of dupChecks) {
    const n = countMeta(html, attr, val);
    if (n > 1) {
      console.log(`  ${warn(`${val} (duplicat!)`)}       pronađeno ${n}x — provjeri Worker stripanje`);
    }
  }

  return { ytId, passed, failed };
}

async function main() {
  console.log(`${BOLD}Domovina.ai — Social Tag Tester${RESET}`);
  console.log(`Target: ${BOLD}${BASE}${RESET}`);
  console.log(`Testira: ${VIDEO_IDS.length} epizoda × 12 tagova (prisutnost + ispravne vrijednosti)\n`);

  const results = [];
  for (const id of VIDEO_IDS) {
    results.push(await testVideo(id));
  }

  const totalPassed = results.reduce((s, r) => s + r.passed, 0);
  const totalFailed = results.reduce((s, r) => s + r.failed, 0);
  const total = totalPassed + totalFailed;

  console.log(`\n${BOLD}━━━ Rezultati ━━━${RESET}`);
  for (const r of results) {
    const bar = r.failed === 0
      ? `${GREEN}${r.passed}/${r.passed + r.failed} OK${RESET}`
      : `${RED}${r.failed} FAIL${RESET} / ${r.passed} OK`;
    console.log(`  ${r.ytId.padEnd(14)} ${bar}`);
  }

  console.log(`\nUkupno: ${totalPassed}/${total} prošlo`);
  if (totalFailed > 0) {
    console.log(`${RED}${totalFailed} tagova nije ispravno — provjeri _worker.js deployment${RESET}`);
    process.exit(1);
  } else {
    console.log(`${GREEN}${BOLD}Sve OK!${RESET}`);
  }
}

main().catch(e => { console.error(e); process.exit(1); });
