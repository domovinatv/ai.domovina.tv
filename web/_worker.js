/**
 * Cloudflare Pages Advanced Mode Worker — domovina.ai
 *
 * Odgovornosti:
 *  1. SPA routing — sve HTML rute vraćaju index.html (Flutter preuzima routing)
 *  2. Statički asseti — proslijeđuju se direktno iz Pages ASSETS bindinga
 *  3. OG/social tagovi — za /v/<ytId> i /?v=<ytId> fetchamo info.json s CDN-a
 *     i injektamo meta tagove u HTML PRIJE nego crawler dobije odgovor
 *  4. COEP/COOP headeri — potrebni za Flutter Skwasm (WebAssembly renderer)
 *     COOP: same-origin        — izolira browsing context za SharedArrayBuffer
 *     COEP: credentialless     — cross-origin resursi (CDN video/slike) se loadaju
 *                                bez credentials — javni CDN pa nema problema
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

    // Cloudflare Pages "pretty URLs" strippa .html ekstenziju (social-test.html → /social-test).
    // Provjeri postoji li .html fajl za ovaj path prije nego padnemo na SPA routing.
    if (path !== '/' && !path.endsWith('/')) {
      const htmlReq = new Request(`${url.origin}${path}.html`, { headers: request.headers });
      const htmlRes = await env.ASSETS.fetch(htmlReq);
      if (htmlRes.ok) return htmlRes;
    }

    // Dohvati index.html iz statičkih asseta
    const indexRequest = new Request(`${url.origin}/index.html`, {
      headers: request.headers,
    });
    const indexResponse = await env.ASSETS.fetch(indexRequest);

    // Izvuci YouTube ID iz URL-a:
    //   /v/<ytId>  — permalink format
    //   /?v=<ytId> — query param format
    let ytId = null;
    const vMatch = path.match(/^\/v\/([A-Za-z0-9_-]+)$/);
    if (vMatch) {
      ytId = vMatch[1];
    } else {
      ytId = url.searchParams.get('v');
    }

    // Nema video ID — vrati index.html bez izmjena (home page)
    if (!ytId) {
      return htmlResponse(await indexResponse.text(), 'no-store');
    }

    // Fetchaj metadata epizode s CDN-a
    let info = null;
    try {
      const res = await fetch(`${CDN}/data/${ytId}/info.json`);
      if (res.ok) info = await res.json();
    } catch (_) {}

    // Video nije pronađen — Flutter će prikazati grešku, ali servamo index.html
    if (!info) {
      return htmlResponse(await indexResponse.text(), 'no-store');
    }

    // Generiraj OG/social meta tagove
    const title = info.title || 'DOMOVINA.ai';
    const rawDesc = (info.description || '').replace(/\s+/g, ' ').trim();
    const desc = rawDesc.length > 300 ? rawDesc.slice(0, 297) + '…' : rawDesc;
    const thumb = `${CDN}/images/${ytId}/thumbnail.png`;
    const canonical = `${SITE}/v/${ytId}`;
    const channel = info.channel || 'DOMOVINA.ai';

    const tags = `
  <title>${x(title)} – DOMOVINA.ai</title>
  <meta name="description" content="${x(desc)}">
  <link rel="canonical" href="${canonical}">

  <meta property="og:type" content="video.other">
  <meta property="og:locale" content="hr_HR">
  <meta property="og:site_name" content="DOMOVINA.ai">
  <meta property="og:title" content="${x(title)}">
  <meta property="og:description" content="${x(desc)}">
  <meta property="og:url" content="${canonical}">
  <meta property="og:image" content="${thumb}">
  <meta property="og:image:type" content="image/png">
  <meta property="og:image:width" content="1280">
  <meta property="og:image:height" content="720">
  <meta property="og:image:alt" content="${x(title)}">
  <meta property="og:video" content="${CDN}/data/${ytId}/video.mp4">
  <meta property="og:video:type" content="video/mp4">
  <meta property="article:author" content="${x(channel)}">

  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${x(title)}">
  <meta name="twitter:description" content="${x(desc)}">
  <meta name="twitter:image" content="${thumb}">
  <meta name="twitter:image:alt" content="${x(title)}">`;

    // Ukloni default tagove iz index.html koji će biti zamijenjeni,
    // pa injektaj video-specifične tagove ispred </head>.
    // Crawler uvijek čita PRVI match — mora biti naš, ne default.
    let html = await indexResponse.text();
    html = html
      .replace(/<title>[^<]*<\/title>/gi, '')
      .replace(/<meta\s[^>]*(?:property|name)=["'](?:og:|twitter:|article:|description)[^"']*["'][^>]*>/gi, '')
      .replace(/<link\s[^>]*rel=["']canonical["'][^>]*>/gi, '');
    html = html.replace('</head>', `${tags}\n</head>`);

    return htmlResponse(html, 'public, max-age=3600, s-maxage=3600');
  },
};

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
