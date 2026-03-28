/**
 * Testira server-side OG/social tagove za sve poznate epizode.
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

// OG tagovi koje svaka epizoda mora imati
const REQUIRED_TAGS = [
  { type: 'tag', name: 'title',                     desc: '<title>' },
  { type: 'meta', attr: 'name',     val: 'description',           desc: 'meta[name=description]' },
  { type: 'meta', attr: 'property', val: 'og:title',              desc: 'og:title' },
  { type: 'meta', attr: 'property', val: 'og:description',        desc: 'og:description' },
  { type: 'meta', attr: 'property', val: 'og:image',              desc: 'og:image' },
  { type: 'meta', attr: 'property', val: 'og:url',                desc: 'og:url' },
  { type: 'meta', attr: 'property', val: 'og:type',               desc: 'og:type' },
  { type: 'meta', attr: 'property', val: 'og:site_name',          desc: 'og:site_name' },
  { type: 'meta', attr: 'name',     val: 'twitter:card',          desc: 'twitter:card' },
  { type: 'meta', attr: 'name',     val: 'twitter:title',         desc: 'twitter:title' },
  { type: 'meta', attr: 'name',     val: 'twitter:image',         desc: 'twitter:image' },
  { type: 'link', attr: 'rel',      val: 'canonical',             desc: 'canonical link' },
];

const GREEN  = '\x1b[32m';
const RED    = '\x1b[31m';
const YELLOW = '\x1b[33m';
const BOLD   = '\x1b[1m';
const RESET  = '\x1b[0m';

function ok(s)   { return `${GREEN}✓${RESET} ${s}`; }
function fail(s) { return `${RED}✗${RESET} ${s}`; }
function warn(s) { return `${YELLOW}!${RESET} ${s}`; }

function extractMeta(html, attr, val) {
  // Matches <meta property="og:title" content="..."> or reversed attr order
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

async function testVideo(ytId) {
  const url = `${BASE}/v/${ytId}`;
  console.log(`\n${BOLD}── ${ytId}${RESET}  ${url}`);

  let html;
  try {
    const res = await fetch(url, {
      headers: { 'Accept': 'text/html', 'User-Agent': 'DominovinaBot/1.0 (social-tag-tester)' },
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

  for (const tag of REQUIRED_TAGS) {
    let value = null;
    if (tag.type === 'tag')  value = extractTitle(html);
    if (tag.type === 'link') value = extractCanonical(html);
    if (tag.type === 'meta') value = extractMeta(html, tag.attr, tag.val);

    if (value !== null && value.trim() !== '') {
      const preview = value.length > 80 ? value.slice(0, 77) + '…' : value;
      console.log(`  ${ok(tag.desc.padEnd(25))} "${preview}"`);
      passed++;
    } else {
      console.log(`  ${fail(tag.desc.padEnd(25))} NEDOSTAJE`);
      failed++;
    }
  }

  // Provjeri da OG image pokazuje na CDN thumbnail
  const ogImage = extractMeta(html, 'property', 'og:image');
  if (ogImage) {
    const expectedThumb = `https://cdn.domovina.ai/images/${ytId}/thumbnail.png`;
    if (ogImage === expectedThumb) {
      console.log(`  ${ok('og:image URL')}              točan CDN path`);
    } else {
      console.log(`  ${warn('og:image URL')}              očekivano: ${expectedThumb}`);
      console.log(`                              dobiveno:  ${ogImage}`);
    }
  }

  // Provjeri canonical URL format
  const canonical = extractCanonical(html);
  const expectedCanonical = `https://domovina.ai/v/${ytId}`;
  if (canonical === expectedCanonical) {
    console.log(`  ${ok('canonical URL')}             točan`);
  } else if (canonical) {
    console.log(`  ${warn('canonical URL')}             dobiveno: ${canonical}`);
  }

  return { ytId, passed, failed };
}

async function main() {
  console.log(`${BOLD}Domovina.ai — Social Tag Tester${RESET}`);
  console.log(`Target: ${BOLD}${BASE}${RESET}`);
  console.log(`Testira se: ${VIDEO_IDS.length} epizoda, ${REQUIRED_TAGS.length} tagova po epizodi\n`);

  const results = [];
  for (const id of VIDEO_IDS) {
    results.push(await testVideo(id));
  }

  // Summary
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
    console.log(`${RED}${totalFailed} tagova nedostaje — provjeri _worker.js deployment${RESET}`);
    process.exit(1);
  } else {
    console.log(`${GREEN}${BOLD}Sve OK!${RESET}`);
  }
}

main().catch(e => { console.error(e); process.exit(1); });
