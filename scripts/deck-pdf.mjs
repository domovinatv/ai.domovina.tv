#!/usr/bin/env node
/**
 * Izvozi seed deck (`docs/marketing/deck/domovina-seed.html`) u PDF.
 *
 *   node scripts/deck-pdf.mjs                     # build/marketing/domovina-seed.pdf
 *   node scripts/deck-pdf.mjs --out ~/Desktop/deck.pdf
 *   node scripts/deck-pdf.mjs --size 1920x1080    # veća projektorska kutija
 *   node scripts/deck-pdf.mjs --skip-gate         # izvezi i kad prelijeva
 *
 * Izlaz ide u `build/` (nije u gitu) jer je repo JAVAN — deck se dijeli
 * fondovima izravno, ne commitom.
 *
 * Rule (exit kodovi su ugovor, isto kao voting-drift-check):
 *   0 = PDF napisan i prošao vrata
 *   1 = deck pada na vratima (prelijevanje ili krivi broj stranica)
 *   2 = ne mogu provjeriti (nema chromiuma, deck se ne učita, PDF nečitljiv)
 * Ne miješati „ne znam" s „deck je puknuo".
 *
 * Dvoja vrata, jer PDF laže na dva načina koja se ne vide dok ga netko ne
 * otvori pred fondom:
 *   A) PRELIJEVANJE — slajd viši od stranice. Prag je isti kao u orakl
 *      prolazu (`docs/2026-08-26-pitch-deck-orakl.md`):
 *      `getBoundingClientRect().height - visina > 0`, mjereno na 1024x768,
 *      1280x720 i 1920x1080. Ondje je trebao iframe jer Chrome kroz
 *      ekstenziju ne da uži prozor od ~500 px i na HiDPI vraća krivi
 *      `innerWidth`; headless Playwright postavlja viewport točno, pa se
 *      mjeri izravno.
 *   B) BROJ STRANICA — mora biti točno onoliko koliko ima `.slide` sekcija.
 *      Jedan piksel viška po slajdu daje 32 stranice, svaka druga prazna, i
 *      to je tiho: PDF se uredno otvori.
 *
 * Print stilovi žive u samom decku, u `@media print` bloku na dnu `<style>`.
 */
import { createServer } from 'node:http';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DECK_DIR = path.join(REPO, 'docs/marketing/deck');
const DECK_FILE = 'domovina-seed.html';

const GREEN = '\x1b[32m', RED = '\x1b[31m', YELLOW = '\x1b[33m';
const DIM = '\x1b[2m', BOLD = '\x1b[1m', RESET = '\x1b[0m';
const ok = (s) => `${GREEN}✓${RESET} ${s}`;
const bad = (s) => `${RED}✗${RESET} ${s}`;
const warn = (s) => `${YELLOW}!${RESET} ${s}`;

// ------------------------------------------------------------- argumenti ---

const args = process.argv.slice(2);
const flag = (name, dflt) => {
  const i = args.indexOf(name);
  return i >= 0 && args[i + 1] ? args[i + 1] : dflt;
};

const outPath = path.resolve(
  REPO,
  flag('--out', 'build/marketing/domovina-seed.pdf').replace(/^~/, process.env.HOME),
);
const skipGate = args.includes('--skip-gate');

const sizeArg = flag('--size', '1280x720');
const sizeMatch = /^(\d+)x(\d+)$/.exec(sizeArg);
if (!sizeMatch) {
  console.error(bad(`--size mora biti ŠIRINAxVISINA (dobiveno "${sizeArg}")`));
  process.exit(2);
}
const PAGE = { width: Number(sizeMatch[1]), height: Number(sizeMatch[2]) };

// Rezolucije na kojima se mjeri prelijevanje. Ciljna veličina stranice je
// uvijek među njima — deck ne smije prelijevati baš u kutiji u koju ga
// izvozimo, čak i ako je netko zada kroz `--size`.
const PROBES = [...new Set([
  `${PAGE.width}x${PAGE.height}`, '1024x768', '1280x720', '1920x1080',
])].map((s) => {
  const [w, h] = s.split('x').map(Number);
  return { w, h, label: s };
});

// ------------------------------------------------------------ posluživanje ---

// `file://` otpada: ekstenzijski Chrome ga ne otvara, a i font fetch se pod
// njim ponaša drukčije nego na objavljenom Artifactu. Poslužujemo isti
// direktorij na efemernoj petlji.
const MIME = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript',
  '.json': 'application/json', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
  '.png': 'image/png', '.svg': 'image/svg+xml', '.webp': 'image/webp',
};

function serve(dir) {
  const server = createServer(async (req, res) => {
    const rel = decodeURIComponent(new URL(req.url, 'http://x').pathname).replace(/^\/+/, '');
    const file = path.join(dir, rel || DECK_FILE);
    if (!file.startsWith(dir)) { res.writeHead(403).end(); return; }
    try {
      const body = await readFile(file);
      res.writeHead(200, { 'content-type': MIME[path.extname(file)] ?? 'application/octet-stream' });
      res.end(body);
    } catch {
      res.writeHead(404).end();
    }
  });
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => resolve({ server, port: server.address().port }));
  });
}

// ------------------------------------------------------------------- PDF ---

/**
 * Broj stranica iz samog PDF-a, bez ovisnosti.
 * Prvo `/Count` u stablu stranica (mjerodavan), pa brojanje `/Type /Page`
 * objekata kao ispad. `null` znači „ne znam" → izlaz 2, ne 1.
 */
function pdfPageCount(buf) {
  const s = buf.toString('latin1');
  const counts = [...s.matchAll(/\/Type\s*\/Pages\b[^>]*?\/Count\s+(\d+)/g)].map((m) => Number(m[1]));
  if (counts.length) return Math.max(...counts);
  const pages = s.match(/\/Type\s*\/Page(?![s\w])/g);
  return pages ? pages.length : null;
}

/**
 * Veličine stranica iz MediaBoxa, u točkama (72/in). PDF ne zna za CSS px:
 * 1280x720 px na 96 dpi je 960x540 pt.
 *
 * Zašto zasebna vrata: broj stranica prođe i kad je kutija kriva. Ako
 * `preferCSSPageSize` ne uhvati `@page` (tipfeler u pravilu, Chrome koji ne
 * uzme px), deck se prelomi u A4 portret — 16 stranica, uredan PDF, potpuno
 * neupotrebljiv na projektoru.
 */
function pdfPageSizes(buf) {
  const boxes = [...buf.toString('latin1').matchAll(
    /\/MediaBox\s*\[\s*([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)\s*\]/g,
  )].map((m) => ({ w: Math.round(m[3] - m[1]), h: Math.round(m[4] - m[2]) }));
  return [...new Set(boxes.map((b) => `${b.w}x${b.h}`))];
}

const PX_TO_PT = 72 / 96;

// ------------------------------------------------------------------ glavno ---

let chromium;
try {
  ({ chromium } = await import('playwright'));
} catch {
  console.error(bad('playwright nije instaliran — `npm install` u korijenu repoa'));
  process.exit(2);
}

if (!existsSync(path.join(DECK_DIR, DECK_FILE))) {
  console.error(bad(`nema ${path.relative(REPO, path.join(DECK_DIR, DECK_FILE))}`));
  process.exit(2);
}

const { server, port } = await serve(DECK_DIR);
const url = `http://127.0.0.1:${port}/${DECK_FILE}`;

// Tri pokušaja, jer Playwrightov vlastiti chromium na ovom stroju pada iz dva
// nezavisna razloga (oba izmjerena 22.9.2026.):
//   1. `headless: true` od 1.49 diže `chrome-headless-shell`, zaseban download
//      od punog chromiuma — tko je instalirao drugu verziju playwrighta ima u
//      cacheu shell krive revizije i `launch()` padne;
//   2. `chromium-1208` je bio raspakiran bez svog frameworka, pa se proces
//      digne i odmah ugasi uz „Target page, context or browser has been
//      closed" — poruka koja ne kaže ništa o uzroku.
// Sistemski Chrome renderira isti PDF i tu je, pa je zadnji ispad on.
// NAPOMENA: uz taj ispad render ovisi o lokalno instaliranom Chromeu, ne o
// verziji prikovanoj u `package.json`.
const LAUNCHERS = [
  { opts: {}, note: null },
  { opts: { channel: 'chromium' }, note: 'headless shell nedostaje — dižem puni chromium' },
  { opts: { channel: 'chrome' }, note: 'Playwrightov chromium ne radi — dižem sistemski Chrome' },
];

let browser;
for (const [i, { opts, note }] of LAUNCHERS.entries()) {
  try {
    browser = await chromium.launch(opts);
    if (note) console.log(`${warn(note)}\n`);
    break;
  } catch (e) {
    if (i === LAUNCHERS.length - 1) {
      server.close();
      console.error(bad(`nijedan chromium se ne diže: ${e.message.split('\n')[0]}`));
      console.error(`  ${DIM}npx playwright install chromium${RESET}`);
      process.exit(2);
    }
  }
}

const page = await browser.newPage({ viewport: { width: PAGE.width, height: PAGE.height } });
let exitCode = 0;

try {
  await page.goto(url, { waitUntil: 'networkidle', timeout: 60_000 });
  // Fraunces i Inter dolaze s Google Fontsa. Bez ovog čekanja prvi izvoz
  // padne na Georgiju/Helveticu i to se vidi tek u gotovom PDF-u.
  await page.evaluate(() => document.fonts.ready);

  const slideCount = await page.locator('.slide').count();
  if (slideCount === 0) {
    console.error(bad('deck se učitao, ali nema nijedne .slide sekcije'));
    process.exit(2);
  }
  console.log(`${BOLD}Deck${RESET}  ${slideCount} slajdova  ${DIM}${path.relative(REPO, path.join(DECK_DIR, DECK_FILE))}${RESET}\n`);

  // --- vrata A: prelijevanje -------------------------------------------
  let overflowFails = 0;
  for (const probe of PROBES) {
    await page.setViewportSize({ width: probe.w, height: probe.h });
    await page.evaluate(() => document.fonts.ready);
    const spills = await page.evaluate((h) =>
      Array.from(document.querySelectorAll('.slide'))
        .map((el, i) => ({ n: i + 1, over: Math.round(el.getBoundingClientRect().height - h) }))
        .filter((s) => s.over > 0), probe.h);

    if (spills.length === 0) {
      console.log(ok(`${probe.label} — nijedan slajd ne prelijeva`));
    } else {
      overflowFails += spills.length;
      const worst = spills.reduce((a, b) => (b.over > a.over ? b : a));
      console.log(bad(
        `${probe.label} — prelijeva ${spills.length}/${slideCount}, ` +
        `najgori slajd ${worst.n} za ${worst.over} px`,
      ));
      console.log(`  ${DIM}${spills.map((s) => `${s.n}:+${s.over}px`).join('  ')}${RESET}`);
    }
  }

  // --- render ------------------------------------------------------------
  await page.setViewportSize(PAGE);
  await page.evaluate(() => document.fonts.ready);
  // Deck ima `@page{size:1280px 720px}` tvrdo upisan, a `preferCSSPageSize`
  // daje CSS-u zadnju riječ — bez ovog pravila `--size` tiho ne radi ništa
  // (izmjereno: `--size 1920x1080` je davao 960x540 pt stranicu).
  await page.addStyleTag({ content: `@media print{@page{size:${PAGE.width}px ${PAGE.height}px}}` });
  // `emulateMedia` nije potreban — page.pdf() ionako renderira pod print
  // medijem, što je točno ono što `@media print` blok u decku čeka.
  const pdf = await page.pdf({
    width: `${PAGE.width}px`,
    height: `${PAGE.height}px`,
    printBackground: true,
    preferCSSPageSize: true,
    margin: { top: '0', right: '0', bottom: '0', left: '0' },
  });

  // --- vrata B: broj stranica -------------------------------------------
  const pages = pdfPageCount(pdf);
  if (pages === null) {
    console.log(`\n${warn('ne mogu pročitati broj stranica iz PDF-a — provjeri ručno')}`);
    exitCode = 2;
  } else if (pages !== slideCount) {
    console.log(`\n${bad(`PDF ima ${pages} stranica, a deck ${slideCount} slajdova`)}`);
    console.log(`  ${DIM}višak stranica = slajd se prelio preko svoje kutije; manjak = slajdovi su se spojili${RESET}`);
    exitCode = 1;
  } else {
    console.log(`\n${ok(`PDF ima točno ${pages} stranica`)}`);
  }

  // --- vrata C: veličina stranice ---------------------------------------
  const want = `${Math.round(PAGE.width * PX_TO_PT)}x${Math.round(PAGE.height * PX_TO_PT)}`;
  const sizes = pdfPageSizes(pdf);
  if (sizes.length === 0) {
    console.log(warn('ne mogu pročitati MediaBox — provjeri veličinu stranice ručno'));
    if (exitCode === 0) exitCode = 2;
  } else if (sizes.length > 1 || sizes[0] !== want) {
    console.log(bad(`stranica je ${sizes.join(', ')} pt, očekivano ${want} pt (${PAGE.width}×${PAGE.height} px)`));
    console.log(`  ${DIM}@page pravilo u decku nije primijenjeno — provjeri @media print blok${RESET}`);
    exitCode = 1;
  } else {
    console.log(ok(`stranica je ${want} pt = ${PAGE.width}×${PAGE.height} px, landscape 16:9`));
  }

  if (overflowFails > 0) exitCode = skipGate ? exitCode : 1;

  if (exitCode === 1 && !skipGate) {
    console.log(`\n${RED}Deck pada na vratima — PDF NIJE napisan.${RESET}`);
    console.log(`${DIM}Izvoz unatoč tome: --skip-gate${RESET}`);
  } else {
    await mkdir(path.dirname(outPath), { recursive: true });
    await writeFile(outPath, pdf);
    const kb = (pdf.length / 1024 / 1024).toFixed(1);
    console.log(`\n${BOLD}→ ${path.relative(process.cwd(), outPath)}${RESET}  ${DIM}${kb} MB${RESET}`);
  }
} catch (e) {
  console.error(bad(`izvoz pao: ${e.message}`));
  exitCode = 2;
} finally {
  await browser.close();
  server.close();
}

process.exit(exitCode);
