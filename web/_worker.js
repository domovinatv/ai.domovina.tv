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

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;

    // Statički asseti (JS, CSS, slike, fontovi...) — direktno iz ASSETS
    if (/\.\w{1,8}$/.test(path)) {
      return env.ASSETS.fetch(request);
    }

    // Izvuci YouTube ID iz URL-a:
    //   /v/<ytId>  — permalink format
    //   /?v=<ytId> — query param format
    let ytId = null;
    const vMatch = path.match(/^\/v\/([A-Za-z0-9_-]{6,20})$/);
    if (vMatch) {
      ytId = vMatch[1];
    } else if (path === '/' || path === '') {
      ytId = url.searchParams.get('v');
    }

    // Dohvati index.html iz statičkih asseta (paralelno s metadatom)
    const indexPromise = env.ASSETS.fetch(
      new Request(`${url.origin}/index.html`, { headers: request.headers }),
    );

    if (ytId) {
      // Fetch info + summary + og-share image check paralelno.
      // og-share.jpg je preferirani format za social (WhatsApp limit 600KB);
      // ako pipeline ga generira, koristi ga, inače fallback na originalni
      // thumbnail.png (koji ostaje netaknut za in-app prikaz).
      const [info, summary, hasOgShare] = await Promise.all([
        fetchJson(`${CDN}/data/${ytId}/info.json`),
        fetchJson(`${CDN}/data/${ytId}/summary.json`),
        headOk(`${CDN}/images/${ytId}/og-share.jpg`),
      ]);

      if (info) {
        const indexHtml = await (await indexPromise).text();
        return htmlResponse(injectEpisodeTags(indexHtml, ytId, info, summary, hasOgShare), 'public, max-age=3600, s-maxage=3600');
      }
      // info ne postoji — Flutter će prikazati grešku, servamo plain index
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

function injectEpisodeTags(indexHtml, ytId, info, summary, hasOgShare) {
  const title = info.title || 'DOMOVINA.ai';
  const rawDesc = pickDescription(info, summary);
  const desc = rawDesc.length > 300 ? rawDesc.slice(0, 297) + '…' : rawDesc;
  const thumb = hasOgShare
    ? `${CDN}/images/${ytId}/og-share.jpg`
    : `${CDN}/images/${ytId}/thumbnail.png`;
  const thumbMime = hasOgShare ? 'image/jpeg' : 'image/png';
  // og-share.jpg je 1200×630 (canonical OG spec, 1.91:1)
  // thumbnail.png je 1280×720 (YouTube native, 16:9)
  const thumbW = hasOgShare ? 1200 : 1280;
  const thumbH = hasOgShare ? 630 : 720;
  const canonical = `${SITE}/v/${ytId}`;
  const channel = info.channel || 'DOMOVINA.ai';
  const releaseDate = formatUploadDate(info.upload_date);
  const isoDur = isoDuration(info.duration);
  const videoUrl = `${CDN}/data/${ytId}/video.mp4`;
  const ytUrl = info.webpage_url || `https://www.youtube.com/watch?v=${ytId}`;

  // Tagovi — preferiraj AI-generirane key_topics (hrvatski, relevantni)
  const topicTags = summary?.summary?.key_topics?.length
    ? summary.summary.key_topics.slice(0, 6)
    : (info.tags || []).slice(0, 6);

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
  <meta property="og:url" content="${canonical}">
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
${jsonLdVideoObject({ title, desc, thumb, canonical, releaseDate, isoDur, channel, ytUrl, videoUrl })}
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

function jsonLdVideoObject({ title, desc, thumb, canonical, releaseDate, isoDur, channel, ytUrl, videoUrl }) {
  const obj = {
    '@context': 'https://schema.org',
    '@type': 'VideoObject',
    name: title,
    description: desc,
    thumbnailUrl: thumb,
    contentUrl: videoUrl,
    embedUrl: canonical,
    url: canonical,
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
