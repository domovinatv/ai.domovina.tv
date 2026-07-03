/**
 * Cloudflare Pages Advanced Mode Worker — domovina.ai
 *
 * Odgovornosti:
 *  1. SPA routing — sve HTML rute vraćaju index.html (Flutter preuzima routing)
 *  2. Statički asseti — proslijeđuju se direktno iz Pages ASSETS bindinga
 *  3. OG/social tagovi — za /v/<ytId> i /?v=<ytId> fetchamo info.json + summary.json
 *     s CDN-a i injectamo bogate meta tagove PRIJE nego crawler dobije odgovor
 *  4. JSON-LD VideoObject — za Google rich-result kartice
 *  5. COEP/COOP headeri — potrebni za Flutter Skwasm (WebAssembly renderer)
 *
 * NAPOMENA: web/_redirects nije prisutan — worker je jedini izvor SPA routinga.
 * Ako se vrati _redirects sa SPA fallbackom, ASSETS.fetch() će za bilo koji
 * nepostojeći .html vratiti index.html sa 200 OK, što ruši detekciju pretty
 * URL-ova (social-test.html, /v/<id>.html, ...) — worker bi krivo vratio
 * index.html bez OG injection.
 */

const CDN = 'https://cdn.domovina.ai';
const SITE = 'https://domovina.ai';
// Person-hub agregat (domovina-rag) — isti no-auth/CORS JSON wrapper kao /api/search.
// GET .../api/person/<slug> → { name, slug, avatar_url, channel_count, episode_count, ... }.
// Vidi lib/services/person_service.dart + lib/models/person_hub.dart.
const PERSON_API = 'https://mcp.domovina.ai/api/person';

// --- Cal.com booking ("15 min DOMOVINA.ai", stepanic/15min) ---------------
// eventTypeId je stabilan (dohvaćen iz /v2/event-types). Ključ dolazi SAMO iz
// env.CAL_API_KEY (Pages secret) — nikad hardkodiran jer je _worker.js u gitu.
const CAL_API = 'https://api.cal.com/v2';
const CAL_EVENT_TYPE_ID = 1787504;
const CAL_TIMEZONE = 'Europe/Zagreb';
// Permisivni CORS — native app + lokalni web dev (localhost) zovu cross-origin.
// U produkciji je web same-origin pa CORS ne smeta.
const CAL_CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Access-Control-Max-Age': '86400',
};

async function handleCalProxy(request, env, path) {
  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CAL_CORS });
  }
  const key = env.CAL_API_KEY;
  const jsonHeaders = {
    'Content-Type': 'application/json',
    'Cache-Control': 'no-store',
    ...CAL_CORS,
  };
  const err = (message, status) =>
    new Response(JSON.stringify({ status: 'error', message }), { status, headers: jsonHeaders });

  try {
    if (path === '/api/cal/slots' && request.method === 'GET') {
      const u = new URL(request.url);
      const start = u.searchParams.get('start');
      const end = u.searchParams.get('end');
      const tz = u.searchParams.get('timeZone') || CAL_TIMEZONE;
      if (!start || !end) return err('start i end su obavezni', 400);
      const api = `${CAL_API}/slots?eventTypeId=${CAL_EVENT_TYPE_ID}`
        + `&start=${encodeURIComponent(start)}&end=${encodeURIComponent(end)}`
        + `&timeZone=${encodeURIComponent(tz)}`;
      const headers = { 'cal-api-version': '2024-09-04' };
      if (key) headers['Authorization'] = `Bearer ${key}`;
      const res = await fetch(api, { headers });
      return new Response(await res.text(), { status: res.status, headers: jsonHeaders });
    }

    if (path === '/api/cal/book' && request.method === 'POST') {
      if (!key) return err('CAL_API_KEY nije konfiguriran na serveru', 500);
      const input = await request.json();
      if (!input.start || !input.name || !input.email) {
        return err('start, name i email su obavezni', 400);
      }
      const payload = {
        start: input.start,
        eventTypeId: CAL_EVENT_TYPE_ID,
        attendee: {
          name: input.name,
          email: input.email,
          timeZone: input.timeZone || CAL_TIMEZONE,
          language: input.language || 'hr',
        },
      };
      if (input.notes) payload.bookingFieldsResponses = { notes: input.notes };
      const res = await fetch(`${CAL_API}/bookings`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${key}`,
          'cal-api-version': '2024-08-13',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(payload),
      });
      return new Response(await res.text(), { status: res.status, headers: jsonHeaders });
    }

    return err('nepoznata Cal.com ruta', 404);
  } catch (e) {
    return err(String(e), 500);
  }
}

// .well-known — serviramo iz workera (NE iz ASSETS) jer:
//   1. apple-app-site-association nema ekstenziju → fall-through na SPA fallback
//   2. flutter build web zna preskočiti `.`-prefiksirane direktorije (web/.well-known/
//      ne dospije pouzdano u build/web)
// Oba služe i App Links verifikaciji (Android autoVerify, iOS applinks) i
// passkey/WebAuthn (Android Credential Manager preko assetlinks; iOS webcredentials).
//
// POPUNITI prije deploya:
//   __ANDROID_SHA256_FINGERPRINT__ — SHA-256 signing cert fingerprint(i), velika
//      slova, ":"-odvojeni (npr. AB:CD:...). Dodaj debug I release ako trebaju oba.
//      (Google Play signing definira se naknadno.)
// Apple Team ID (6SCK58757K) je već upisan.
const ASSETLINKS_JSON = JSON.stringify([
  {
    relation: [
      'delegate_permission/common.handle_all_urls',
      'delegate_permission/common.get_login_creds',
    ],
    target: {
      namespace: 'android_app',
      package_name: 'ai.domovina',
      sha256_cert_fingerprints: ['__ANDROID_SHA256_FINGERPRINT__'],
    },
  },
], null, 2);

const AASA_JSON = JSON.stringify({
  applinks: {
    apps: [],
    details: [
      { appID: '6SCK58757K.ai.domovina', paths: ['*'] },
    ],
  },
  webcredentials: {
    apps: ['6SCK58757K.ai.domovina'],
  },
}, null, 2);

// WebAuthn Related Origin Requests (WebAuthn L3). Lets passkeys created under
// RP ID `domovina.ai` be used natively from OTHER registrable domains in the
// ecosystem (pinka.finance, domovina.energy, …) — not just *.domovina.ai
// subdomains. Each listed origin may request assertions with RP ID domovina.ai.
// Served at https://domovina.ai/.well-known/webauthn.
// See pay.domovina.ai/docs/plans/cross-domain-wallet-passkey.md (Phase D).
const WEBAUTHN_JSON = JSON.stringify({
  origins: [
    'https://domovina.ai',
    'https://www.domovina.ai',
    'https://wallet.domovina.ai',
    'https://pay.domovina.ai',
    'https://mpt.domovina.ai',
    'https://pinka.finance',
    'https://www.pinka.finance',
    'https://app.pinka.finance',
    'https://pinka-app.pages.dev',
    'https://pinka.io',
    'https://www.pinka.io',
    'https://domovina.energy',
    'https://www.domovina.energy',
    'https://domovina.tv',
    'https://www.domovina.tv',
  ],
}, null, 2);

function wellKnownResponse(body) {
  return new Response(body, {
    status: 200,
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'public, max-age=3600',
    },
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;

    // .well-known (App Links + passkey/WebAuthn) — prije svega ostalog.
    if (path === '/.well-known/assetlinks.json') return wellKnownResponse(ASSETLINKS_JSON);
    if (path === '/.well-known/apple-app-site-association') return wellKnownResponse(AASA_JSON);
    if (path === '/.well-known/webauthn') return wellKnownResponse(WEBAUTHN_JSON);

    // Cal.com booking proxy — drži CAL_API_KEY server-side (env secret), NIKAD
    // u web bundleu. Slotovi su javni (reflektiraju Google Calendar kolizije),
    // booking POST traži ključ. Flutter app zove same-origin /api/cal/*.
    if (path === '/api/cal/slots' || path === '/api/cal/book') {
      return handleCalProxy(request, env, path);
    }

    // Statički asseti (JS, CSS, slike, fontovi...) — direktno iz ASSETS.
    // KRITIČNO: env.ASSETS.fetch ne aplicira web/_headers automatski kad
    // worker rukuje requestom (CF Pages Advanced Mode contract). Bootstrap
    // fajlovi (main.dart.js, flutter*.js, manifest.json) bi inače dobili
    // default Cache-Control od ~14400s pa bi iOS Safari servirao stari
    // main.dart.js (~3.3MB) tjednima nakon deploya. Patchamo ih ovdje na
    // no-cache + must-revalidate (ETag negotiation = 304 na unchanged).
    // Hashed bundle assets (canvaskit, assets/*) ostaju s default
    // CF cachiranjem koje je sigurno jer im se URL mijenja na rebuild.
    if (/\.\w{1,8}$/.test(path)) {
      const res = await env.ASSETS.fetch(request);
      // Bootstrap entry-pointi koji se mijenjaju na svaki rebuild ali zadržavaju
      // isti URL — moraju revalidate-ati. Skwasm build dodaje main.dart.wasm i
      // *.mjs runtime loadere uz dart2js fallback.
      if (/^\/(main\.dart\.(?:js|wasm|mjs)|flutter\.js|flutter_bootstrap\.js|skwasm(?:_heavy)?\.(?:js|wasm|worker\.js)|manifest\.json|favicon\.png)$/.test(path)) {
        const headers = new Headers(res.headers);
        headers.set('Cache-Control', 'public, max-age=0, must-revalidate');
        // CDN edge sloj: i CF mora poštovati no-store da ne servira iz vlastitog cache-a
        headers.set('CDN-Cache-Control', 'no-store');
        return new Response(res.body, { status: res.status, statusText: res.statusText, headers });
      }
      return res;
    }

    // Trailing-slash kanonikalizacija — 301 na verziju bez "/".
    // Bez ovoga route matcheri ispod (/v/<id>, /v/<id>/t/<n>, /m/<id>) i
    // pretty-URL .html lookup propuste request s "/" sufiksom pa fall-through
    // na SPA fallback servira generic OG tagove. New URL preservira search +
    // hash, pa query params (?utm_source=..., ?ref=..., interni app params)
    // ostaju netaknuti kroz redirect.
    if (path !== '/' && path.endsWith('/')) {
      const canonicalUrl = new URL(request.url);
      canonicalUrl.pathname = path.replace(/\/+$/, '');
      return Response.redirect(canonicalUrl.toString(), 301);
    }

    // Izvuci YouTube ID iz URL-a:
    //   /v/<ytId>            — permalink format (detailed view)
    //   /v/<ytId>/t/<sec>    — timestamp clip share (path-based za pouzdan crawler cache)
    //   /m/<ytId>            — mobile simplified view (isti OG, canonical → /v/<id>)
    //   /?v=<ytId>           — query param format
    let ytId = null;
    let tSec = null;
    let viewMode = 'v'; // 'v' = detailed, 'm' = simple
    const tMatch = path.match(/^\/v\/([A-Za-z0-9_-]{6,20})\/t\/(\d+)$/);
    const vMatch = !tMatch && path.match(/^\/v\/([A-Za-z0-9_-]{6,20})$/);
    const mMatch = !tMatch && !vMatch && path.match(/^\/m\/([A-Za-z0-9_-]{6,20})$/);
    if (tMatch) {
      ytId = tMatch[1];
      tSec = parseInt(tMatch[2], 10);
    } else if (vMatch) {
      ytId = vMatch[1];
    } else if (mMatch) {
      ytId = mMatch[1];
      viewMode = 'm';
    } else if (path === '/' || path === '') {
      ytId = url.searchParams.get('v');
    }

    // Dohvati index.html iz statičkih asseta (paralelno s metadatom)
    const indexPromise = env.ASSETS.fetch(
      new Request(`${url.origin}/index.html`, { headers: request.headers }),
    );

    if (ytId) {
      // Fetch info + summary + article + og-sections manifest + og-share check
      // paralelno. article.json i og-sections.json su opcionalni (stariji videi
      // ih možda nemaju) — fetchJson vraća null na 404 pa fallback radi sam.
      // og-sections.json je Tier B manifest: { sections: { "<sec>": "og-t-<sec>.jpg" } }
      // — file po section-u, 1200×630 JPEG ~100KB (WhatsApp-safe < 600KB).
      const [info, summary, article, ogSections, hasOgShare] = await Promise.all([
        fetchJson(`${CDN}/data/${ytId}/info.json`),
        fetchJson(`${CDN}/data/${ytId}/summary.json`),
        // article + og-sections fetchamo SAMO za timestamp shareove — base
        // /v/<id> koristi episode-level og-share.jpg.
        (typeof tSec === 'number') ? fetchJson(`${CDN}/data/${ytId}/article.json`) : Promise.resolve(null),
        (typeof tSec === 'number') ? fetchJson(`${CDN}/images/${ytId}/og-sections.json`) : Promise.resolve(null),
        headOk(`${CDN}/images/${ytId}/og-share.jpg`),
      ]);

      // Section-specific og:image override. Manifest mapa: { "<startSec>": "og-t-<sec>.jpg" }.
      // findArticleSection vraća section s _start poljem koji odgovara ključu u manifestu.
      // Ako manifest postoji i sadrži file za taj section start → koristi ga.
      let sectionImageUrl = null;
      if (info && article && ogSections && typeof tSec === 'number') {
        const sec = findArticleSection(article, tSec, info.duration);
        if (sec && typeof sec._start === 'number') {
          const filename = ogSections.sections?.[String(sec._start)];
          if (filename) {
            sectionImageUrl = `${CDN}/images/${ytId}/${filename}`;
          }
        }
      }

      if (info) {
        const indexHtml = await (await indexPromise).text();
        return htmlResponse(injectEpisodeTags(indexHtml, ytId, info, summary, article, hasOgShare, tSec, viewMode, sectionImageUrl), 'public, max-age=3600, s-maxage=3600');
      }
      // info ne postoji — Flutter će prikazati grešku, servamo plain index
      return htmlResponse(await (await indexPromise).text(), 'no-store');
    }

    // Person-hub profil — /p/<slug>. Slug se koristi DOSLOVNO (bez `-`↔`_`
    // transformacije koju rade kanali) jer je primarni ključ u bazi. Fetchamo
    // agregat s domovina-rag i injectamo osobno-specifične OG tagove PRIJE nego
    // crawler (WhatsApp/Facebook/…) dobije odgovor — inače dijeli generički
    // domovina.ai preview.
    const pMatch = path.match(/^\/p\/([a-z0-9-]{2,80})$/);
    if (pMatch) {
      const slug = pMatch[1];
      const person = await fetchJson(`${PERSON_API}/${encodeURIComponent(slug)}`);
      if (person && person.name) {
        const indexHtml = await (await indexPromise).text();
        return htmlResponse(injectPersonTags(indexHtml, slug, person), 'public, max-age=3600, s-maxage=3600');
      }
      // Slug ne postoji (404) ili API nedostupan — Flutter pokaže prazno stanje.
      return htmlResponse(await (await indexPromise).text(), 'no-store');
    }

    // Cloudflare Pages "pretty URLs" — provjeri postoji li <path>.html.
    // Bez _redirects ovaj lookup je pouzdan (404 ako fajl ne postoji).
    if (path !== '/' && !path.endsWith('/')) {
      const htmlReq = new Request(`${url.origin}${path}.html`, { headers: request.headers });
      const htmlRes = await env.ASSETS.fetch(htmlReq);
      if (htmlRes.ok) return htmlRes;
    }

    // Bez video ID-a i bez .html match-a — SPA fallback (Flutter router)
    return htmlResponse(await (await indexPromise).text(), 'no-store');
  },
};

async function fetchJson(url) {
  try {
    const res = await fetch(url, { cf: { cacheTtl: 300, cacheEverything: true } });
    if (res.ok) return await res.json();
  } catch (_) {}
  return null;
}

async function headOk(url) {
  try {
    const res = await fetch(url, { method: 'HEAD', cf: { cacheTtl: 3600, cacheEverything: true } });
    return res.ok;
  } catch (_) {
    return false;
  }
}

/**
 * Generira bogati description s fallback hijerarhijom:
 *   1. summary.summary.abstract_hr  (AI sažetak na hrvatskom — najbolja kvaliteta)
 *   2. info.description             (sirov YouTube opis — često sadrži linkove/hashtagove)
 */
function pickDescription(info, summary) {
  const abstract = summary?.summary?.abstract_hr;
  if (abstract && abstract.trim().length > 50) return abstract.trim();
  return (info.description || '').replace(/\s+/g, ' ').trim();
}

/** "20260319" → "2026-03-19" */
function formatUploadDate(yyyymmdd) {
  if (!yyyymmdd || !/^\d{8}$/.test(yyyymmdd)) return null;
  return `${yyyymmdd.slice(0, 4)}-${yyyymmdd.slice(4, 6)}-${yyyymmdd.slice(6, 8)}`;
}

/** Sekunde → "H:MM:SS" ili "M:SS" za prikaz u OG title/description */
function formatClock(seconds) {
  const s = Math.max(0, Math.floor(seconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  const pad = (n) => n.toString().padStart(2, '0');
  return h > 0 ? `${h}:${pad(m)}:${pad(sec)}` : `${m}:${pad(sec)}`;
}

/** Pronađi chapter koji obuhvaća timestamp; vrati null ako nema chaptera ili tSec izvan range. */
function findChapter(chapters, tSec) {
  if (!Array.isArray(chapters) || chapters.length === 0 || tSec == null) return null;
  return chapters.find((c) =>
    typeof c.start_time === 'number' &&
    typeof c.end_time === 'number' &&
    tSec >= c.start_time &&
    tSec < c.end_time,
  ) || null;
}

/** "HH:MM:SS" → sekunde */
function clockToSec(clock) {
  if (!clock || typeof clock !== 'string') return null;
  const parts = clock.split(':').map((n) => parseInt(n, 10));
  if (parts.some((n) => Number.isNaN(n))) return null;
  if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
  if (parts.length === 2) return parts[0] * 60 + parts[1];
  return null;
}

/**
 * Pronađi article section koji obuhvaća tSec.
 * Article sections imaju AI-generirane subtitle/description/keywords/entities —
 * znatno bogatije od info.chapters (samo title).
 *
 * Algoritam: poravnaj sve sections po timestampu, pa zadnji čiji secStart <= tSec
 * (do sljedećeg sectiona ili kraja videa) je match.
 */
function findArticleSection(article, tSec, videoDuration) {
  if (!article || !Array.isArray(article.iterations) || tSec == null) return null;
  const flat = [];
  for (const it of article.iterations) {
    if (!Array.isArray(it.sections)) continue;
    for (const s of it.sections) {
      const start = clockToSec(s.screenshot_timestamp);
      if (start != null) flat.push({ start, section: s });
    }
  }
  if (flat.length === 0) return null;
  flat.sort((a, b) => a.start - b.start);
  // Pronađi zadnji section s start <= tSec
  let match = null;
  for (let i = 0; i < flat.length; i++) {
    const next = flat[i + 1];
    const end = next ? next.start : (typeof videoDuration === 'number' ? videoDuration : Infinity);
    if (tSec >= flat[i].start && tSec < end) {
      match = { ...flat[i].section, _start: flat[i].start, _end: end };
      break;
    }
  }
  return match;
}

/** Sekunde → ISO-8601 duration npr. 2661 → "PT44M21S" */
function isoDuration(seconds) {
  if (!seconds || seconds <= 0) return null;
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  let out = 'PT';
  if (h > 0) out += `${h}H`;
  if (m > 0) out += `${m}M`;
  if (s > 0 || (h === 0 && m === 0)) out += `${s}S`;
  return out;
}

function injectEpisodeTags(indexHtml, ytId, info, summary, article, hasOgShare, tSec, viewMode, sectionImageUrl) {
  const baseTitle = info.title || 'DOMOVINA.ai';
  const rawDesc = pickDescription(info, summary);
  const baseDesc = rawDesc.length > 300 ? rawDesc.slice(0, 297) + '…' : rawDesc;

  // Match prioritet za timestamp share:
  //   1. Article section — najbogatiji (AI subtitle + screenshot_description + keywords)
  //   2. info.chapters    — basic (samo title + range)
  //   3. Plain timestamp  — samo ⏱ marker
  const section = (typeof tSec === 'number')
    ? findArticleSection(article, tSec, info.duration)
    : null;
  const chapter = (typeof tSec === 'number' && !section)
    ? findChapter(info.chapters, tSec)
    : null;
  const clock = (typeof tSec === 'number') ? formatClock(tSec) : null;
  let title = baseTitle;
  let desc = baseDesc;
  // Specifični tagovi za section/chapter — fallback su summary.key_topics u glavnom blocku ispod.
  let overrideTopicTags = null;

  if (section) {
    // Section subtitle je već specifičan ("Uvod i predstavljanje X"), ne treba mu cijeli baseTitle.
    // Skratimo subtitle ako je predug, da stane u 95 chara s clock+epname.
    const sub = (section.subtitle || '').replace(/\s+/g, ' ').trim();
    const subShort = sub.length > 80 ? sub.slice(0, 77) + '…' : sub;
    title = `⏱ ${clock} · ${subShort}`;
    const range = `${formatClock(section._start)}–${formatClock(section._end)}`;
    const sectionDesc = (section.screenshot_description || section.content || '').replace(/\s+/g, ' ').trim();
    desc = `${sectionDesc} — iz "${baseTitle}" (${range})`;
    if (desc.length > 300) desc = desc.slice(0, 297) + '…';
    // Bogatiji article:tag-ovi za ovaj specifični trenutak.
    const tags = [];
    if (Array.isArray(section.keywords)) tags.push(...section.keywords);
    if (Array.isArray(section.entities)) tags.push(...section.entities);
    if (tags.length > 0) overrideTopicTags = tags.slice(0, 8);
  } else if (chapter) {
    title = `⏱ ${clock} · ${chapter.title} — ${baseTitle}`;
    const range = `${formatClock(chapter.start_time)}–${formatClock(chapter.end_time)}`;
    desc = `Dio "${chapter.title}" (${range}) iz: ${baseTitle}. ${baseDesc}`;
    if (desc.length > 300) desc = desc.slice(0, 297) + '…';
  } else if (typeof tSec === 'number') {
    title = `⏱ ${clock} — ${baseTitle}`;
    desc = `Trenutak na ${clock} iz: ${baseTitle}. ${baseDesc}`;
    if (desc.length > 300) desc = desc.slice(0, 297) + '…';
  }

  // og:image prioritet:
  //   1. og-t-<sec>.jpg (1200×630 JPEG ~100KB, WhatsApp-safe < 600KB) —
  //      Tier B pipeline output, section-specific frame s brand overlayem.
  //      Aktivira se kad og-sections.json manifest listira fajl za taj section.
  //   2. og-share.jpg (1200×630 JPEG ~100KB) — episode-level brand image.
  //   3. thumbnail.png (1280×720 PNG) — YouTube native, krajnji fallback.
  let thumb, thumbMime, thumbW, thumbH;
  if (sectionImageUrl) {
    thumb = sectionImageUrl;
    thumbMime = 'image/jpeg';
    thumbW = 1200;
    thumbH = 630;
  } else if (hasOgShare) {
    thumb = `${CDN}/images/${ytId}/og-share.jpg`;
    thumbMime = 'image/jpeg';
    thumbW = 1200;
    thumbH = 630;
  } else {
    thumb = `${CDN}/images/${ytId}/thumbnail.png`;
    thumbMime = 'image/png';
    thumbW = 1280;
    thumbH = 720;
  }
  // KRITIČNO: canonical mora biti pun path s /t/<sec> da svaki clip ima vlastiti
  // crawler cache entry (Facebook/LinkedIn/WhatsApp). Bez ovoga svi timestampovi
  // dijele isti preview.
  // Canonical uvijek pokazuje na /v/ (ne /m/) — SEO konsolidacija: /m/ je samo
  // alternativni view, ne distinct content. og:url, pak, prati share URL da
  // crawleri ne dignu canonical preko og:url-a i poremete cache.
  const canonical = (typeof tSec === 'number')
    ? `${SITE}/v/${ytId}/t/${tSec}`
    : `${SITE}/v/${ytId}`;
  const ogUrl = (viewMode === 'm')
    ? `${SITE}/m/${ytId}`
    : canonical;
  const channel = info.channel || 'DOMOVINA.ai';
  const releaseDate = formatUploadDate(info.upload_date);
  const isoDur = isoDuration(info.duration);
  const videoUrl = `${CDN}/data/${ytId}/video.mp4`;
  const ytUrl = info.webpage_url || `https://www.youtube.com/watch?v=${ytId}`;

  // Tagovi — section override (section-specifični keywords+entities) > summary.key_topics > info.tags.
  const topicTags = overrideTopicTags
    || (summary?.summary?.key_topics?.length
      ? summary.summary.key_topics.slice(0, 6)
      : (info.tags || []).slice(0, 6));

  const articleTags = topicTags.map((t) => `  <meta property="article:tag" content="${x(t)}">`).join('\n');

  const tags = `
  <title>${x(title)} – DOMOVINA.ai</title>
  <meta name="description" content="${x(desc)}">
  <link rel="canonical" href="${canonical}">

  <meta property="og:type" content="video.other">
  <meta property="og:locale" content="hr_HR">
  <meta property="og:site_name" content="DOMOVINA.ai">
  <meta property="og:logo" content="${SITE}/og-image-square.png">
  <meta property="og:title" content="${x(title)}">
  <meta property="og:description" content="${x(desc)}">
  <meta property="og:url" content="${ogUrl}">
  <meta property="og:image" content="${thumb}">
  <meta property="og:image:type" content="${thumbMime}">
  <meta property="og:image:width" content="${thumbW}">
  <meta property="og:image:height" content="${thumbH}">
  <meta property="og:image:alt" content="${x(title)}">
  <meta property="og:video" content="${videoUrl}">
  <meta property="og:video:secure_url" content="${videoUrl}">
  <meta property="og:video:type" content="video/mp4">${
    info.duration ? `\n  <meta property="og:video:duration" content="${info.duration}">` : ''
  }${
    releaseDate ? `\n  <meta property="og:video:release_date" content="${releaseDate}">` : ''
  }${
    typeof tSec === 'number' ? `\n  <meta property="og:video:start_time" content="${tSec}">` : ''
  }
  <meta property="article:author" content="${x(channel)}">${
    releaseDate ? `\n  <meta property="article:published_time" content="${releaseDate}">` : ''
  }
${articleTags}

  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${x(title)}">
  <meta name="twitter:description" content="${x(desc)}">
  <meta name="twitter:image" content="${thumb}">
  <meta name="twitter:image:alt" content="${x(title)}">
  <meta name="twitter:label1" content="Kanal">
  <meta name="twitter:data1" content="${x(channel)}">${
    info.duration_string ? `\n  <meta name="twitter:label2" content="Trajanje">\n  <meta name="twitter:data2" content="${x(info.duration_string)}">` : ''
  }

  <script type="application/ld+json">
${jsonLdVideoObject({ title, desc, thumb, canonical, releaseDate, isoDur, channel, ytUrl, videoUrl, tSec, chapter, section, baseTitle, ytId })}
  </script>`;

  // Ukloni default tagove + bilo koji prethodni JSON-LD; pa injectaj video-specifične.
  // Crawler uvijek čita PRVI match — mora biti naš, ne default.
  let html = indexHtml;
  html = html
    .replace(/<title>[^<]*<\/title>/gi, '')
    .replace(/<meta\s[^>]*(?:property|name)=["'](?:og:|twitter:|article:|description)[^"']*["'][^>]*>/gi, '')
    .replace(/<link\s[^>]*rel=["']canonical["'][^>]*>/gi, '')
    .replace(/<script\s+type=["']application\/ld\+json["'][^>]*>[\s\S]*?<\/script>/gi, '');
  return html.replace('</head>', `${tags}\n</head>`);
}

/**
 * Hrvatski broj + imenica po slavenskom plural pravilu:
 *   1  → one   (1 epizoda, 21 epizoda)
 *   2–4 → few  (2 epizode, 23 epizode)
 *   else → many (5 epizoda, 11 epizoda)
 * Iznimke: 11–14 uvijek "many".
 */
function croPlural(n, one, few, many) {
  const mod10 = n % 10;
  const mod100 = n % 100;
  if (mod10 === 1 && mod100 !== 11) return one;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
  return many;
}

/**
 * Injektira OG/JSON-LD tagove za person-hub profil (/p/<slug>).
 * Cilj: kad se link dijeli na WhatsApp/Facebook, preview pokaže IME osobe i
 * broj epizoda/kanala — ne generički domovina.ai opis.
 */
function injectPersonTags(indexHtml, slug, person) {
  const name = (person.name || '').trim() || 'Govornik';
  const epCount = Number(person.episode_count) || (Array.isArray(person.episodes) ? person.episodes.length : 0);
  const chCount = Number(person.channel_count) || (Array.isArray(person.channels) ? person.channels.length : 0);

  const epWord = croPlural(epCount, 'epizodi', 'epizode', 'epizoda'); // "u N epizodi/epizode/epizoda"
  const chWord = croPlural(chCount, 'kanalu', 'kanala', 'kanala');   // "na N kanalu/kanala"

  const title = `${name} — podcast profil`;
  // Gramatika: "gost u 1 epizodi", "gost u 2 epizode", "gost u 6 epizoda";
  //            "na 1 kanalu", "na 6 kanala".
  const desc = `Sve epizode u kojima ${name} govori — gost u ${epCount} ${epWord} `
    + `na ${chCount} ${chWord}. AI sažetci, transkripti i analiza podcasta na DOMOVINA.ai.`;

  const canonical = `${SITE}/p/${slug}`;

  // og:image — avatar osobe ako postoji (kvadratni headshot), inače brend slika.
  // WhatsApp voli 1200×630; za kvadratni avatar padamo na summary karticu.
  const hasAvatar = typeof person.avatar_url === 'string' && person.avatar_url.startsWith('http');
  const image = hasAvatar ? person.avatar_url : `${SITE}/og-image.png`;
  const twitterCard = hasAvatar ? 'summary' : 'summary_large_image';

  // Split imena za og profile:first_name/last_name (best-effort).
  const parts = name.split(/\s+/);
  const firstName = parts[0] || name;
  const lastName = parts.length > 1 ? parts.slice(1).join(' ') : '';

  const jsonLd = JSON.stringify({
    '@context': 'https://schema.org',
    '@type': 'ProfilePage',
    mainEntity: {
      '@type': 'Person',
      name,
      url: canonical,
      ...(hasAvatar ? { image: person.avatar_url } : {}),
      subjectOf: {
        '@type': 'ItemList',
        numberOfItems: epCount,
        name: `Epizode u kojima govori ${name}`,
      },
    },
    publisher: {
      '@type': 'Organization',
      name: 'DOMOVINA.ai',
      logo: { '@type': 'ImageObject', url: `${SITE}/icons/Icon-512.png` },
    },
  }, null, 2);

  const tags = `
  <title>${x(title)} – DOMOVINA.ai</title>
  <meta name="description" content="${x(desc)}">
  <link rel="canonical" href="${canonical}">

  <meta property="og:type" content="profile">
  <meta property="og:locale" content="hr_HR">
  <meta property="og:site_name" content="DOMOVINA.ai">
  <meta property="og:logo" content="${SITE}/og-image-square.png">
  <meta property="og:title" content="${x(name)}">
  <meta property="og:description" content="${x(desc)}">
  <meta property="og:url" content="${canonical}">
  <meta property="og:image" content="${x(image)}">
  <meta property="og:image:alt" content="${x(name)} — DOMOVINA.ai">
  <meta property="profile:first_name" content="${x(firstName)}">${
    lastName ? `\n  <meta property="profile:last_name" content="${x(lastName)}">` : ''
  }
  <meta property="profile:username" content="${x(slug)}">

  <meta name="twitter:card" content="${twitterCard}">
  <meta name="twitter:title" content="${x(name)}">
  <meta name="twitter:description" content="${x(desc)}">
  <meta name="twitter:image" content="${x(image)}">
  <meta name="twitter:image:alt" content="${x(name)} — DOMOVINA.ai">
  <meta name="twitter:label1" content="Epizode">
  <meta name="twitter:data1" content="${epCount}">
  <meta name="twitter:label2" content="Kanali">
  <meta name="twitter:data2" content="${chCount}">

  <script type="application/ld+json">
${jsonLd}
  </script>`;

  // Ukloni default tagove + prethodni JSON-LD; injectaj person-specifične.
  let html = indexHtml;
  html = html
    .replace(/<title>[^<]*<\/title>/gi, '')
    .replace(/<meta\s[^>]*(?:property|name)=["'](?:og:|twitter:|article:|profile:|description)[^"']*["'][^>]*>/gi, '')
    .replace(/<link\s[^>]*rel=["']canonical["'][^>]*>/gi, '')
    .replace(/<script\s+type=["']application\/ld\+json["'][^>]*>[\s\S]*?<\/script>/gi, '');
  return html.replace('</head>', `${tags}\n</head>`);
}

function jsonLdVideoObject({ title, desc, thumb, canonical, releaseDate, isoDur, channel, ytUrl, videoUrl, tSec, chapter, section, baseTitle, ytId }) {
  const obj = {
    '@context': 'https://schema.org',
    '@type': 'VideoObject',
    name: typeof tSec === 'number' ? (baseTitle || title) : title,
    description: desc,
    thumbnailUrl: thumb,
    contentUrl: videoUrl,
    embedUrl: typeof tSec === 'number' ? `${SITE}/v/${ytId}` : canonical,
    url: typeof tSec === 'number' ? `${SITE}/v/${ytId}` : canonical,
    sameAs: ytUrl,
    inLanguage: 'hr',
    publisher: {
      '@type': 'Organization',
      name: 'DOMOVINA.ai',
      logo: {
        '@type': 'ImageObject',
        url: `${SITE}/icons/Icon-512.png`,
      },
    },
    author: { '@type': 'Person', name: channel },
  };
  if (releaseDate) obj.uploadDate = releaseDate;
  if (isoDur) obj.duration = isoDur;

  // Schema.org Clip — signaliziraj Googleu da je ovo specifični trenutak.
  // Vidi: https://developers.google.com/search/docs/appearance/structured-data/video#clip
  // Prioritet imena: section.subtitle > chapter.title > generički "Trenutak na X".
  if (typeof tSec === 'number') {
    let clipName;
    let clipEnd;
    if (section) {
      clipName = (section.subtitle || '').replace(/\s+/g, ' ').trim() || `Trenutak na ${formatClock(tSec)}`;
      if (typeof section._end === 'number' && Number.isFinite(section._end)) {
        clipEnd = Math.floor(section._end);
      }
    } else if (chapter) {
      clipName = chapter.title;
      if (typeof chapter.end_time === 'number') clipEnd = Math.floor(chapter.end_time);
    } else {
      clipName = `Trenutak na ${formatClock(tSec)}`;
    }
    const clip = {
      '@type': 'Clip',
      name: clipName,
      url: canonical,
      startOffset: tSec,
    };
    if (typeof clipEnd === 'number') clip.endOffset = clipEnd;
    obj.hasPart = clip;
  }

  return JSON.stringify(obj, null, 2);
}

function htmlResponse(html, cacheControl) {
  return new Response(html, {
    status: 200,
    headers: {
      'Content-Type': 'text/html;charset=UTF-8',
      'Cache-Control': cacheControl,
      // Skwasm (Flutter WebAssembly renderer) zahtijeva ove headere
      // za SharedArrayBuffer koji koristi za multi-threading.
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'credentialless',
    },
  });
}

/** HTML escape za umetanje u atribute */
function x(s) {
  return (s || '')
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}
