# CDN & R2 cache optimizacija — analiza i plan

**Datum analize:** 2026-05-28
**Status:** problem identificiran, fix nije još implementiran
**Skopirano iz:** Claude konverzacije, perzistirano kao referenca za buduće odluke

---

## 1. TL;DR

`cdn.domovina.ai` (Cloudflare R2 bucket via custom domain) **trenutno NE
cachira ni jedan request na Cloudflare edge-u**. Svaki request svakog
klijenta ide direktno na R2 = 1 Class B operacija. Free tier je 10M Class
B/mjesec — to znači breakeven na ~4.5k DAU.

Uz Cache Rules + Smart Tiered Cache + ispravne `Cache-Control` headere s
backend uploadera, edge HIT ratio može preko 95% → breakeven se pomiče
na ~30k DAU bez troška, ~1M DAU za ~$100/mjesec.

## 2. Mjerenje (2026-05-28)

Sve provjere na živom CDN-u vraćaju `cf-cache-status: DYNAMIC` i čak na
drugi hit istog URL-a:

| Endpoint | Origin Cache-Control | cf-cache-status (1.) | (2.) |
|---|---|---|---|
| `/channels/data/index.json` | `public, max-age=60, must-revalidate` | `DYNAMIC` | `DYNAMIC` |
| `/data/<id>/info.json` | (isto) | `DYNAMIC` | `DYNAMIC` |
| `/images/<id>/thumbnail.png` | (isto) | `DYNAMIC` | `DYNAMIC` |
| `/data/<id>/video.mp4` (HEAD + Range) | (isto) | `DYNAMIC` | `DYNAMIC` |

`DYNAMIC` = Cloudflare smatra odgovor ne-cacheabilnim, prosljeđuje
origin-u (R2) → 1 Class B po requestu.

### Zašto je sve `DYNAMIC`

1. **`max-age=60` + `must-revalidate`** — preniska vrijednost da CF
   default heuristika cachira agresivno; uz `must-revalidate` edge mora
   konzultirati origin za svaki request stariji od 60s.
2. **JSON se po defaultu ne cachira** na CF edge-u (samo "static"
   ekstenzije: png, jpg, mp4, css, js, woff…). Bez explicit Cache Rule-a
   za JSON, sav metadata uvijek pogađa R2.
3. **Memory napomena** kaže "uploader stavlja `immutable` na sve fajlove",
   ali response pokazuje `must-revalidate`. Treba potvrditi na backend
   strani (fetch.domovina.tv pipeline).

## 3. Kako Flutter app trenutno dohvaća

`lib/services/cdn_config.dart` + `web/_worker.js`:

- **Per-video JSON** (`info.json`, `summary.json`, `article.json`,
  `article.magisterium*.json`, `outline.json`, EN overlays,
  `diarized.srt`) — direktan fetch, bez cache-bustera (dobro: stabilan
  URL).
- **Channel listing** (`channels/data/index.json`, `<channel>.json`,
  `avatar_*.jpg`) — fetch s `?v=<5-min-bucket>` (`cdn_config.dart:14-17`).
  Cache-buster mijenja URL svakih 5 minuta = potencijalno 288
  fresh-fetcheva po useru po danu samo za channel index.
- **Slike** (`thumbnail.png`, `screenshots/HH-MM-SS.png`, `og-share.jpg`,
  `og-t-*.jpg`) — direktan fetch.
- **Video** (`video.mp4`) — HTTP 206 Range requestovi preko
  `media_kit`/`<video>`. Svaki seek + buffer chunk = 1 Class B op.
- **`web/_worker.js`** dodatno fetcha `info.json` + `summary.json`
  (+ optional `article.json`, `og-sections.json`) za svaki `/v/<id>`
  SPA request radi OG injectanja. Koristi
  `cf: { cacheTtl: 300, cacheEverything: true }` — to je **jedini sloj
  koji trenutno radi**.

## 4. Cloudflare R2 cijenik (Standard, svibanj 2026)

| Resurs | Free | Iznad free |
|---|---|---|
| Storage | 10 GB-mjesec | $0.015 / GB-mjesec |
| **Class A** (writes, list) | **1M / mj** | $4.50 / 1M |
| **Class B** (reads, head) | **10M / mj** | $0.36 / 1M |
| Egress | **neograničeno besplatno** | — |

**Egress je 100% besplatan.** Trošak skalira samo s brojem operacija.
Optimizacija = maksimizirati edge HIT ratio. **Edge cache HIT se NE
računa kao R2 Class B operacija.**

## 5. Simulacija — trenutno stanje (bez fixa)

Per active user-day pretpostavke:
- Channel browse (3× otvaranja zbog 5-min cache-bustera): **6 ops**
- 5 epizoda pregledano × 5 fileova (info/summary/article/magisterium/thumb): **25 ops**
- 1 video do kraja (~40 range chunks): **40 ops**
- OG worker fetch: zanemarivo

**≈ 70 R2 ops / aktivni korisnik / dan.**

| DAU | Ops/mj | Class B trošak | Storage (5 GB) | Ukupno |
|---|---|---|---|---|
| 50 | 105k | $0 | $0 | **$0** |
| 500 | 1.05M | $0 | $0 | **$0** |
| 4 500 | 9.45M | ~$0 (limit) | $0 | **~$0** |
| 10 000 | 21M | $3.96 | $0 | **~$4** |
| 50 000 | 105M | $34.20 | ~$0 | **~$34** |
| 200 000 | 420M | $147.60 | ~$1 | **~$148** |

## 6. Konkretni zahvati

### A) Cache Rules na zoni (Cloudflare Dashboard → Caching → Cache Rules)

Najveći ROI, 5 min posla:

```
Rule 1 — per-video immutable data
  When:  hostname eq "cdn.domovina.ai"
         AND uri.path matches "^/data/[^/]+/.*"
  Then:  Cache eligibility = Eligible for cache
         Edge TTL = Override origin, 1 year
         Browser TTL = Override origin, 1 day

Rule 2 — images
  When:  hostname eq "cdn.domovina.ai"
         AND uri.path matches "^/images/.*"
  Then:  Edge TTL = 1 year, Browser TTL = 7 days

Rule 3 — channel listings (mijenjaju se kad dođu novi videi)
  When:  hostname eq "cdn.domovina.ai"
         AND uri.path matches "^/channels/.*"
  Then:  Edge TTL = 1 hour, Browser TTL = 5 min
```

Očekivani efekt: prvi user u svakom CF datacentru pogađa R2, svi ostali
HIT. Procjena: **95–99% smanjenje Class B operacija**.

### B) Smart Tiered Cache (besplatno)

Caching → Tiered Cache → Enable Smart Tiered Cache. Smanjuje broj
POP-ova koji idu na origin sa ~300 na 1 upper-tier datacenter najbliži
R2 bucket-u.

### C) Backend uploader — ispravi origin headere

Na pipeline strani (fetch.domovina.tv R2 uploader):

| Pattern | Cache-Control |
|---|---|
| `/data/<id>/*.json`, `*.srt`, `*.md`, `/images/<id>/*` | `public, max-age=31536000, immutable` |
| `/data/<id>/video.mp4` | `public, max-age=31536000, immutable` |
| `/channels/data/*.json` | `public, max-age=300, s-maxage=3600` |
| `/channels/images/<id>/*` | `public, max-age=86400` |

Per-video sadržaj **je** immutable (URL vezan na YouTube ID, sadržaj se
ne mijenja nakon AI pipelinea), `immutable` direktiva ispravna. Nakon
ovoga Cache Rule edge TTL override postaje redundant.

### D) Frontend — ukloni 5-min cache-buster iz `cdn_config.dart`

`_channelCacheBuster()` (`lib/services/cdn_config.dart:14-17`) uništava
browser cache svakih 5 min. Defensive measure dodana jer "uploader stavlja
immutable na sve". Bolji pristup:

- Backend stavi pravi `max-age=300, s-maxage=3600` na `channels/*.json`.
- Frontend ukloni `?v=`. Browser refresh-a nakon 5 min, edge 1h.
- Cache-buster samo kod pull-to-refresh user action-a.

### E) Video range requestovi

Cache Rule "Cache everything" na `/data/<id>/video.mp4` cachira i range
responses. Drugi user koji gleda istu epizodu ne udara R2. CF ima
chunked range caching za fajlove >1MB.

Bonus: kad pipeline doda `video.h264.mp4` fallback (vidi AV1 memory),
oba file-a koriste istu strategiju.

### F) ETag/304

`info.json` već ima ETag. S `max-age=31536000, immutable` browser nikad
ne refetcha u jednoj sesiji. Između sesija If-None-Match dobija 304 iz
edge meta, bez R2 hit-a.

### G) Service Worker runtime cache (već imamo SW za iOS PWA)

```js
workbox.routing.registerRoute(
  /^https:\/\/cdn\.domovina\.ai\/data\/[^/]+\/.*\.(json|srt|md)$/,
  new workbox.strategies.CacheFirst({
    cacheName: 'domovina-ai-data',
    plugins: [
      new workbox.expiration.ExpirationPlugin({
        maxEntries: 500, maxAgeSeconds: 30*86400,
      }),
    ],
  })
);
```

Returning user na istu epizodu = 0 mrežnih requestova.

## 7. Simulacija — nakon A+B+C+G

HIT ratio: 95% images/video, 90% per-video JSON, 99% return useri (SW).

| DAU | R2 ops/mj | Class B trošak |
|---|---|---|
| 50 | ~15k | $0 |
| 500 | ~150k | $0 |
| 10 000 | ~3M | **$0** (free) |
| 50 000 | ~15M | **$1.80** |
| 200 000 | ~60M | **$18** |
| 1 000 000 | ~300M | **$104** |

**Breakeven se pomiče s ~4.5k DAU na ~30k DAU.**

## 8. Što NE dirati

- **Workers paid plan** — ne treba. Cache Rules su besplatne na free
  planu. Workers ti trebaju samo za OG injection (već radi),
  low-volume (crawler + share klikovi).
- **R2 Infrequent Access** — skuplji per-op ($0.90 vs $0.36) + retrieval
  naknada. Smiri da bi imalo smisla samo za jako stare videofile-ove
  koji se rijetko gledaju. Trenutno nema potrebe.
- **Migracija na drugi storage** — R2+CF je najjeftinija kombinacija jer
  egress free. B2 ima egress trošak, S3+CloudFront ima i egress i ops.

## 9. Redoslijed implementacije

1. **5 min, najveći ROI:** Cache Rules iz sekcije A. Provjera: drugi
   hit istog URL-a treba vraćati `cf-cache-status: HIT`.
2. **2 min:** Smart Tiered Cache enable.
3. **1 sat:** pipeline uploader — ispravi `Cache-Control` (sekcija C).
   Onda možeš maknuti Cache Rule edge TTL override.
4. **30 min:** Flutter — ukloni `_channelCacheBuster()` iz
   `cdn_config.dart` (sekcija D). Test da nove epizode i dalje stižu
   unutar ~1h.
5. **2 sata:** SW runtime cache za CDN data (sekcija G).
6. **Monitoring:** R2 dashboard pokazuje Class A/B counter dnevno.
   Postavi alert (CF Notifications) na 7M ops/mj = 70% free tier-a.

## 10. Reference

- [Cloudflare R2 Pricing](https://developers.cloudflare.com/r2/pricing/)
- [R2 Public Buckets & Custom Domains](https://developers.cloudflare.com/r2/buckets/public-buckets/)
- [CF Default Cache Behavior](https://developers.cloudflare.com/cache/concepts/default-cache-behavior/)
- [Cache-Control & CDN-Cache-Control](https://developers.cloudflare.com/cache/concepts/cache-control/)
