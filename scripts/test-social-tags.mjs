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
  const ogImgW     = extractMeta(html, 'property', 'og:image:width');
  const ogImgH     = extractMeta(html, 'property', 'og:image:height');
  const ogImgType  = extractMeta(html, 'property', 'og:image:type');
  const ogImgAlt   = extractMeta(html, 'property', 'og:image:alt');
  const ogUrl      = extractMeta(html, 'property', 'og:url');
  const ogType     = extractMeta(html, 'property', 'og:type');
  const ogSite     = extractMeta(html, 'property', 'og:site_name');
  const ogLocale   = extractMeta(html, 'property', 'og:locale');
  const twCard     = extractMeta(html, 'name', 'twitter:card');
  const twTitle    = extractMeta(html, 'name', 'twitter:title');
  const twImage    = extractMeta(html, 'name', 'twitter:image');
  const twImgAlt   = extractMeta(html, 'name', 'twitter:image:alt');
  const canonical  = extractCanonical(html);

  // Provjeri prisutnost i ispravnost vrijednosti
  check('<title>',           title,    (v) => v.includes('– DOMOVINA.ai') && v !== '– DOMOVINA.ai');
  check('description',       desc,     (v) => v !== 'A new Flutter project.' && v.length > 10);
  check('og:title',          ogTitle,  (v) => v !== 'DOMOVINA.ai' && v.length > 3);
  check('og:description',    ogDesc,   (v) => v.length > 10);
  check('og:image',          ogImage,  (v) => v === expectedThumb);
  check('og:image:width',    ogImgW,   (v) => v === '1280');
  check('og:image:height',   ogImgH,   (v) => v === '720');
  check('og:image:type',     ogImgType,(v) => v === 'image/png');
  check('og:image:alt',      ogImgAlt, (v) => v.length > 3);
  check('og:url',            ogUrl,    (v) => v === expectedCanonical);
  check('og:type',           ogType,   (v) => v === 'video.other');
  check('og:site_name',      ogSite,   (v) => v === 'DOMOVINA.ai');
  check('og:locale',         ogLocale, (v) => v === 'hr_HR');
  check('twitter:card',      twCard,   (v) => v === 'summary_large_image');
  check('twitter:title',     twTitle,  (v) => v !== 'DOMOVINA.ai' && v.length > 3);
  check('twitter:image',     twImage,  (v) => v === expectedThumb);
  check('twitter:image:alt', twImgAlt, (v) => v.length > 3);
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

async function testHomepage() {
  const url = BASE;
  console.log(`\n${BOLD}── HOMEPAGE${RESET}  ${url}`);

  let html;
  try {
    const res = await fetch(url, {
      headers: { Accept: 'text/html', 'User-Agent': 'DominovinaBot/1.0 (social-tag-tester)' },
      redirect: 'follow',
    });
    if (!res.ok) {
      console.log(`  ${fail(`HTTP ${res.status}`)}`);
      return { ytId: 'HOMEPAGE', passed: 0, failed: 1 };
    }
    html = await res.text();
  } catch (e) {
    console.log(`  ${fail(`Network error: ${e.message}`)}`);
    return { ytId: 'HOMEPAGE', passed: 0, failed: 1 };
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

  const title      = extractTitle(html);
  const desc       = extractMeta(html, 'name', 'description');
  const ogTitle    = extractMeta(html, 'property', 'og:title');
  const ogDesc     = extractMeta(html, 'property', 'og:description');
  const ogImage    = extractMeta(html, 'property', 'og:image');
  const ogImgW     = extractMeta(html, 'property', 'og:image:width');
  const ogImgH     = extractMeta(html, 'property', 'og:image:height');
  const ogImgType  = extractMeta(html, 'property', 'og:image:type');
  const ogImgAlt   = extractMeta(html, 'property', 'og:image:alt');
  const ogUrl      = extractMeta(html, 'property', 'og:url');
  const ogType     = extractMeta(html, 'property', 'og:type');
  const ogSite     = extractMeta(html, 'property', 'og:site_name');
  const ogLocale   = extractMeta(html, 'property', 'og:locale');
  const twCard     = extractMeta(html, 'name', 'twitter:card');
  const twTitle    = extractMeta(html, 'name', 'twitter:title');
  const twImage    = extractMeta(html, 'name', 'twitter:image');
  const twImgAlt   = extractMeta(html, 'name', 'twitter:image:alt');
  const canonical  = extractCanonical(html);

  check('<title>',           title,    (v) => v.includes('DOMOVINA.ai'));
  check('description',       desc,     (v) => v.length > 20);
  check('og:type',           ogType,   (v) => v === 'website');
  check('og:locale',         ogLocale, (v) => v === 'hr_HR');
  check('og:site_name',      ogSite,   (v) => v === 'DOMOVINA.ai');
  check('og:title',          ogTitle,  (v) => v.includes('DOMOVINA.ai'));
  check('og:description',    ogDesc,   (v) => v.length > 20);
  check('og:url',            ogUrl,    (v) => v === 'https://domovina.ai');
  check('og:image',          ogImage,  (v) => v === 'https://domovina.ai/og-image.png');
  check('og:image:width',    ogImgW,   (v) => v === '1200');
  check('og:image:height',   ogImgH,   (v) => v === '630');
  check('og:image:type',     ogImgType,(v) => v === 'image/png');
  check('og:image:alt',      ogImgAlt, (v) => v.length > 3);
  check('twitter:card',      twCard,   (v) => v === 'summary_large_image');
  check('twitter:title',     twTitle,  (v) => v.includes('DOMOVINA.ai'));
  check('twitter:image',     twImage,  (v) => v === 'https://domovina.ai/og-image.png');
  check('twitter:image:alt', twImgAlt, (v) => v.length > 3);
  check('canonical',         canonical,(v) => v === 'https://domovina.ai');

  return { ytId: 'HOMEPAGE', passed, failed };
}

/**
 * Testira timestamp share URL `/v/<id>/t/<sec>` — chapter-aware OG tagovi.
 * Verificira da je canonical/og:url path-based (nije normaliziran na base URL)
 * i da title/description signaliziraju da je clip, ne cijela epizoda.
 */
async function testTimestamp(ytId, tSec) {
  const url = `${BASE}/v/${ytId}/t/${tSec}`;
  console.log(`\n${BOLD}── ${ytId} @ ${tSec}s${RESET}  ${url}`);

  let html;
  try {
    const res = await fetch(url, {
      headers: { Accept: 'text/html', 'User-Agent': 'DominovinaBot/1.0 (social-tag-tester)' },
      redirect: 'follow',
    });
    if (!res.ok) {
      console.log(`  ${fail(`HTTP ${res.status}`)}`);
      return { ytId: `${ytId}@${tSec}`, passed: 0, failed: 1 };
    }
    html = await res.text();
  } catch (e) {
    console.log(`  ${fail(`Network error: ${e.message}`)}`);
    return { ytId: `${ytId}@${tSec}`, passed: 0, failed: 1 };
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

  const expectedCanonical = `https://domovina.ai/v/${ytId}/t/${tSec}`;

  const title       = extractTitle(html);
  const ogTitle     = extractMeta(html, 'property', 'og:title');
  const ogDesc      = extractMeta(html, 'property', 'og:description');
  const ogUrl       = extractMeta(html, 'property', 'og:url');
  const ogStart     = extractMeta(html, 'property', 'og:video:start_time');
  const canonical   = extractCanonical(html);

  // Kritično: og:url i canonical MORAJU sadržavati /t/<sec> — bez toga
  // crawleri sve clipove istog videa tretiraju kao isti URL.
  check('og:url path-based',  ogUrl,     (v) => v === expectedCanonical);
  check('canonical path-based', canonical, (v) => v === expectedCanonical);
  check('og:video:start_time', ogStart,  (v) => v === String(tSec));
  // Title/desc moraju biti chapter-aware (sadrže ⏱ marker ili timestamp).
  check('og:title (clip marker)', ogTitle, (v) => v.includes('⏱') || v.includes(':'));
  check('og:description (clip)', ogDesc, (v) => v.length > 30);
  check('<title> (clip)',       title,    (v) => v.includes('⏱') || v.includes('DOMOVINA.ai'));

  return { ytId: `${ytId}@${tSec}`, passed, failed };
}

/**
 * Testira simple-view share URL `/m/<id>` — isti OG kao /v/, ali:
 *  - canonical → /v/<id> (SEO konsolidacija, /m/ je samo alternativni view)
 *  - og:url → /m/<id> (prati shared URL da crawler ima distinct cache)
 */
async function testSimpleView(ytId) {
  const url = `${BASE}/m/${ytId}`;
  console.log(`\n${BOLD}── ${ytId} (simple view)${RESET}  ${url}`);

  let html;
  try {
    const res = await fetch(url, {
      headers: { Accept: 'text/html', 'User-Agent': 'DominovinaBot/1.0 (social-tag-tester)' },
      redirect: 'follow',
    });
    if (!res.ok) { console.log(`  ${fail(`HTTP ${res.status}`)}`); return { ytId: `${ytId}/m`, passed: 0, failed: 1 }; }
    html = await res.text();
  } catch (e) { console.log(`  ${fail(`Network: ${e.message}`)}`); return { ytId: `${ytId}/m`, passed: 0, failed: 1 }; }

  let passed = 0, failed = 0;
  const check = (label, value, expected) => {
    const lab = label.padEnd(26);
    if (value === null || value.trim() === '') { console.log(`  ${fail(lab)} NEDOSTAJE`); failed++; return; }
    if (expected !== undefined && !expected(value)) { const p = value.length > 70 ? value.slice(0,67)+'…' : value; console.log(`  ${fail(lab)} "${p}"`); failed++; return; }
    const p = value.length > 70 ? value.slice(0,67)+'…' : value; console.log(`  ${ok(lab)} "${p}"`); passed++;
  };

  const ogTitle = extractMeta(html, 'property', 'og:title');
  const ogUrl   = extractMeta(html, 'property', 'og:url');
  const canon   = extractCanonical(html);
  const title   = extractTitle(html);

  check('og:title (not default)',  ogTitle, (v) => v !== 'DOMOVINA.ai' && v.length > 5);
  check('og:url is /m/',           ogUrl,   (v) => v === `https://domovina.ai/m/${ytId}`);
  check('canonical is /v/',        canon,   (v) => v === `https://domovina.ai/v/${ytId}`);
  check('<title> (not default)',   title,   (v) => v.includes('DOMOVINA.ai') && v !== '– DOMOVINA.ai');

  return { ytId: `${ytId}/m`, passed, failed };
}

async function main() {
  console.log(`${BOLD}DOMOVINA.ai — Social Tag Tester${RESET}`);
  console.log(`Target: ${BOLD}${BASE}${RESET}`);
  console.log(`Testira: homepage + ${VIDEO_IDS.length} epizoda + timestamp shareovi\n`);

  const results = [];
  results.push(await testHomepage());
  for (const id of VIDEO_IDS) {
    results.push(await testVideo(id));
  }
  // Timestamp share testovi — uzmi prvi video, testiraj 2 različita momenta.
  // 600s = ~10min (vjerojatno unutar chaptera), 60s = rano (early chapter).
  results.push(await testTimestamp(VIDEO_IDS[0], 600));
  results.push(await testTimestamp(VIDEO_IDS[0], 60));
  // Simple view share (/m/<id>) — isti OG, canonical → /v/, og:url → /m/.
  results.push(await testSimpleView(VIDEO_IDS[0]));

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
