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

---

# Dio II — Arhitektonska analiza: zašto je R2+CDN za ovaj use case (skoro) nedostižan

> Materijal za budući blog post o **content-addressable static-first
> arhitekturi** i tome zašto je za content-distribution aplikacije
> kombinacija immutable-static-na-CDN + DB-samo-za-mutable-user-state
> najskalabilniji moguci model 2026. godine.

## 11. Pitanje

Je li R2 (objektni storage) + Cloudflare Edge cache stvarno optimalan
izbor za serviranje AI-enriched podataka po video epizodi, ili bi
"normalna" arhitektura (DB + HTTP API) bila bolja?

Intuicija koja je vodila odluku: **svaka DB+API arhitektura uvodi
single-point-of-failure i probleme s vertikalnim/horizontalnim
skaliranjem. Statične konfiguracije se mogu jednom definirati i
distribuirati svijetu bez infrastrukturnih problema.**

Ova intuicija je točna — ali zaslužuje razložiti zašto, i gdje su
granice tog modela.

## 12. Zašto je R2+CDN tu strogo dominantan

Per-episode podaci imaju 4 svojstva koja čine static-files-on-CDN
**strogo dominantnim** rješenjem:

### 12.1 Content-addressed i immutable

URL je deterministička funkcija YouTube ID-a. `info.json` za
`dQw4w9WgXcQ` je uvijek `info.json` za `dQw4w9WgXcQ`. Nema "show me
latest version of X" semantike — kad pipeline jednom proizvede fajl,
ne mijenja se.

To je idealan slučaj za HTTP caching jer **cache invalidacija je
trivijalna (= nikad ne invalidira)**. Cache invalidacija je jedan od
dva najteža problema u računarstvu — kad ga jednostavno nemaš,
arhitektura postaje radikalno jednostavnija.

### 12.2 Read-heavy, write-rare

Pipeline napiše fajl jednom (1 Class A op), čita ga potencijalno
milijunima puta (0 Class A; eventualno N Class B prije nego edge
cachira). Asimetrija writes:reads je realno 1:10⁶+.

DB+API ima **konstantne CPU + memory + connection troškove po readu**,
čak i kad je u potpunosti cached u Postgres shared_buffers. CDN edge
HIT je literalno 0 CPU na origin strani.

### 12.3 Bez per-user customizacije

Article za jednu epizodu jednak je za sve korisnike. Nema
personalizacije, RLS provjera, A/B varijanti. Znači **jedan cached
response u edge POP-u opslužuje sve usere u toj geografiji.**

Multi-tenant DB API ovo **ne može** jer mora barem provjeriti auth
token. Čak i s aggressive query caching-om, svaki request konzumira
backend resurse.

### 12.4 Geo-distribuirana publika

HR + BIH + dijaspora. Cloudflare ima ~30 POP-ova u 1000km radijusu od
većine HR usera. Edge HIT u Zagrebu je <20ms.

Bilo koja DB+API arhitektura ima single-region origin (npr. Coolify
Oracle VM u jednoj zoni = ~50-200ms za usere izvan te zone). Multi-region
DB je dramatično složeniji (replikacija, conflict resolution, eventual
consistency tradeoffi).

## 13. Što DB+API daje, a CDN ne može

Trenutna arhitektura već radi ovaj split ispravno — Supabase postoji za
stvari gdje DB pobjeđuje:

| Property | Bolje na CDN | Bolje u DB |
|---|---|---|
| Mutable per-user state (favorites, watch_progress, onboarding) | — | ✅ Supabase |
| Real-time updates (live counts, presence) | — | ✅ Postgres LISTEN/NOTIFY |
| Cross-document upiti ("svi videi koji spominju X") | — | ✅ SQL/full-text |
| Granularna autorizacija (RLS, per-row policies) | — | ✅ Supabase RLS |
| Agregacije (top trending, creator stats) | teško | ✅ SQL aggregate |
| Atomic mutations (inkrement broja gledanja, voting) | nemoguće | ✅ ACID |
| Static read-only sadržaj | ✅ R2+CDN | overkill |
| Velike binarne datoteke (video, slike) | ✅ R2 | catastrophic |
| Search-driven discovery koji počinje s ID-em | ✅ CDN | OK ali skuplje |
| Search bez ID-a ("episodes about X") | nemoguće | ✅ DB + pgvector |

**Trenutna arhitektura je konceptualno čista:**

- **CDN sloj** = "the catalogue" (immutable AI-enriched podaci po video ID-u)
- **DB sloj** = "the user layer" (sve što se mijenja per-user / per-time)

To je textbook **JAMstack** / **content-addressable static-first**
pattern. Netflix katalog metadata, Spotify album metadata, Wikipedia
static dumps, npm package tarballs — svi imaju istu strukturu.

## 14. Granice — gdje bi morao prebaciti dio u DB

Tri scenarija u kojima CDN-only model puca:

### 14.1 Search/discovery koji ne počinje s YT ID-em

"Pronađi sve epizode koje spominju ‘Bartulović’" — to **ne možeš** iz
CDN-a bez fetchanja svih `article.json` fajlova.

- **Opcija A (jeftino, do nekih 10k epizoda):** generiraj static
  `search-index.json` (~5-50MB) jednom kad pipeline završi, hostaj na
  CDN, client-side full-text. Skalira do ~10k epizoda × ~5KB indexirani
  podataka = 50MB index.
- **Opcija B (kad A pukne):** Supabase `pg_trgm` ili `pgvector`
  embedding tablica + RPC.

MCP toolset `count_mentions` već implicira postojeci search backend —
to **mora** biti DB jer CDN model to ne podržava elegantno.

### 14.2 Per-user feed / preporuke

"Pokaži useru epizode preporučene baš za njega" → ne možeš servirati
jedan cached response svima.

Rješenje je hibrid: **personalisation API** koji vraća **listu ID-eva**,
client onda fetcha pune podatke iz CDN-a po ID-u. API ostaje lightweight
(low ops), CDN handla težak read tonnage. Ovo je arhitektonski najljepši
pattern — **DB radi rangiranje, CDN radi serviranje**.

### 14.3 Stvarni real-time

Live chat, live broj gledatelja, push notifikacije. CDN nije rješenje
— SSE/WebSocket s backenda.

## 15. SPOF analiza — gdje je rizik manji

DB+API arhitektura ima 4 SPOF-a koje R2+CDN nema:

1. **Connection pool** (PgBouncer/Supavisor limit, najčešće 500–2000
   konekcija). Viral moment = pool exhaustion. CDN nema connection pool
   — TCP terminira na edge-u, milijuni konkurentnih konekcija su
   normalan throughput.

2. **Origin DB CPU/RAM** — DDoS ili viral moment zatrpa origin. CDN
   edge absorbira spike-ove (Reddit hug of death = ne primijetiš).

3. **Single region latency** — Oracle VM u jednoj zoni = svi useri
   izvan te zone pate. CDN je 300+ POP-ova po defaultu.

4. **Migracije, restartovi, deploy downtime** — DB zahtijeva maintenance
   prozore. R2 objekt ima 11-nine durability bez ikakvog maintenance-a.

Jedini SPOF kod CDN+R2 modela: **Cloudflare sam**. To je realan, ali
distribuiran rizik — kad CF padne (zadnji veliki outage ~1h u 2024)
padne i pol interneta, što je drugačija (kratko-trajna) vrsta problema
od "moj single VM se srušio".

## 16. Konkurentske opcije

Provjera tržišta (svibanj 2026):

| Kandidat | Egress | Read ops cijena | Edge POPs | Verdict |
|---|---|---|---|---|
| **R2 + CF CDN** | $0 | $0.36/1M | ~310 | ✅ tvoj choice |
| AWS S3 + CloudFront | $0.085/GB egress + S3 ops | $0.40/1M | ~600 | egress te ubije |
| Backblaze B2 + bunny.net | $0.01/GB egress | $0 (bunny) | ~120 | egress nije free |
| GCS + Cloud CDN | $0.08/GB egress | $0.40/10k (!) | ~200 | catastrophic ops cost |
| Bunny Storage + Bunny CDN | $0.01/GB egress | $0 | ~120 | OK za EU-only |
| Vlastiti nginx + Hetzner | bandwidth limited | varies | 1 | gubitak svih CDN benefita |

**R2+CF je jedini koji ima $0 egress + $0 edge cache HIT + free tier
10M reads/mj.** Za HR/EU audience, jedina realna alternativa je Bunny
(jeftiniji ops, ali plaća egress).

## 17. Praktičan zaključak (i naslov budućeg blog posta)

**"Immutable static content na CDN, mutable user state u DB" je literalno
najbolja praksa 2026. godine za content-distribution aplikacije.**

Razlog zašto je ovaj pattern superioran:

1. **Cache invalidacija nestaje kao problem** kad URL je
   content-addressed i sadržaj immutable.
2. **Skaliranje nestaje kao problem** kad edge HIT je free i bez
   origin involvement.
3. **Multi-region nestaje kao problem** kad CDN je default geo-distribuiran.
4. **SPOF se distribuira** s tvog origina na CF, što je inherentno
   distribuirano i izdržava DDoS.
5. **Cijena skalira s broj-novih-objekata, ne s broj-readova** — što
   je obrnuto od svih klasičnih cloud arhitektura.

Trenutna domovina.ai arhitektura već radi ovaj split ispravno. Jedino
što treba popraviti je **postaviti edge cache da konačno radi** (vidi
sekciju A–G iznad) — trenutno se plaća "DB+API" cijena u Class B
operacijama dok se ima "CDN" arhitektura, što je worst-of-both-worlds.

**Future-additive promjene** (ne zamjenjuju trenutni model):

- **Search index** kao zaseban static fajl (`search-index.json` na
  CDN-u) ili DB tablica — ovisno o veličini kataloga.
- **Recommendation API** kad/ako dođe personalizacija — minimalan
  endpoint koji vraća listu ID-eva, sav težak read i dalje ide na CDN.

## 18. Blog post outline (za kasnije)

Naslov kandidati:
- "Zašto je 10MB statičnih JSON fajlova skalabilnije od bilo koje API arhitekture"
- "Content-addressable static-first: arhitektura koja ne pada"
- "$0 do 30k DAU: kako smo izgradili domovina.ai na R2 i Cloudflare edge-u"

Glavne teze:
1. Cache invalidation je riješen problem kad URL je content-hash.
2. Edge je nova "database" za read-only sadržaj.
3. SPOF-ove premiještaš s vlastite infrastrukture na inherentno
   distribuirane CF/AWS edge mreže.
4. DB je sloj **samo za mutable user state**, ne za content delivery.
5. Razdvajanje "catalogue" (CDN) od "user layer" (DB) je tekstbook
   JAMstack — ali za AI-enriched dinamičan sadržaj, ne samo za statične
   site-ove.
6. Anti-pattern: koristiti DB+API za read-only content jer "lakše je
   za query-ati" — zapravo dobijaš sve troškove DB-a + ništa od benefita
   edge-a.

Materijali za blog (iz ovog repoa):
- `lib/services/cdn_config.dart` — kompletna mapa file layouta
- `lib/services/data_service.dart` — fetch logika
- `web/_worker.js` — OG injection pattern (single Worker fetch s
  `cacheEverything: true`)
- Sekcije 5 i 7 ovog dokumenta — konkretne brojke troška po DAU
- Memory `cdn_file_layout.md` — file taksonomija

Vizuali:
- Tablica iz sekcije 13 (CDN vs DB tradeoffs)
- Graf "trošak / DAU" prije i poslije Cache Rules
- Diagram "request flow": client → CF edge HIT (95%) → R2 (5%)
- Tablica iz sekcije 16 (konkurentske opcije)
