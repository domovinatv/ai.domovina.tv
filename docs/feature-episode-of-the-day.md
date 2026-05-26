# Epizoda dana — Feature Plan

**Verzija:** v1 — initial draft
**Datum:** 2026-05-26
**Status:** Backlog (after homepage redesign deploy)
**Motivacija:** Product Hunt-style daily archive za hrvatske katoličke podcaste — creator marketing magnet.

> Ovaj dokument opisuje **novi feature** koji dopunjava trenutni client-side "ISTAKNUTO" hero (dnevna rotacija u browseru). Cilj: prebaciti odluku **što je epizoda dana** s klijenta na server (pipeline cron) tako da svaka datumom-označena epizoda ima **trajan permalink, OG share, public archive i creator-facing badge**.

---

## 1. Zašto — creator marketing angle

Producenti i moderatori hrvatskih katoličkih podcasta žele **socijalni signal kvalitete** koji mogu istaknuti:

- "Naša epizoda razgovora s nadbiskupom Bozanićem bila je **Epizoda dana** na domovina.ai 4. lipnja 2026."
- Embeddable badge na stranici emisije ("Epizoda dana ✦ DOMOVINA.ai")
- Permalink koji **nikad ne propada** (`/dan/2026-06-04`) — frozen u CDN JSON-u, deterministic
- Vidljiv crawler-friendly social share (`og-eotd-<date>.jpg` s overlayom "EPIZODA DANA")

Tipičan use case: emisija postuje na Instagram/FB/X **"Bila smo Epizoda dana — vidi zašto"** + link na `/dan/<date>`. Klikom dolazi user koji možda nikad nije čuo za domovina.ai → conversion.

**Analogija**: [Product Hunt — Product of the Day](https://www.producthunt.com/). Frozen daily winner s history-jem koji creatori share-aju mjesecima nakon.

---

## 2. Trenutno stanje (v2.0.x — homepage redesign)

Implementirano client-side u `lib/screens/home/`:

- `home_feed.dart` — `pickFeatured()` algoritam, 4-tier fallback (hi-quality recent → hi-quality → any AI → newest)
- Tier 1 ima **dnevnu rotaciju**: top 5 kandidata seedani po `dayOfYear`
- `hero_section.dart` — hero s "ZAŠTO?" gumbom koji otvara dialog s objašnjenjem

**Limit**: izbor je per-browser i per-trenutak (svaki user na drugom kontinentu može vidjeti drugačiji featured ako su mu satovi različiti, ili ako cache nije gotov). Ne može se share-ati permalinkom.

---

## 3. Arhitektura

```
┌────────────────────┐    daily cron    ┌──────────────────────────┐
│ fetch.domovina.tv  │ ───────────────> │ cdn.domovina.ai          │
│ (pipeline repo)    │  23:55 Zagreb    │ eotd/index.json          │
│                    │                  │ eotd/<YYYY-MM-DD>.json   │
└────────────────────┘                  └──────────────────────────┘
                                              │
                                              │ runtime fetch
                                              ▼
┌────────────────────┐  worker handles  ┌──────────────────────────┐
│ web/_worker.js     │ ─── OG inject ── │ HTML response            │
│ Cloudflare Pages   │  za /dan/<date>  │ <meta og:* za crawlere>  │
│                    │                  │ + SPA payload za browser │
└────────────────────┘                  └──────────────────────────┘
                                              │
                                              ▼
┌────────────────────────────────────────────────────────────────┐
│ Flutter web (lib/screens/eotd/)                                │
│   /dan          — kronološka arhiva (lista svih dana)          │
│   /dan/:date    — single day stranica (hero stilom)            │
└────────────────────────────────────────────────────────────────┘
```

**Princip**: pipeline donosi **autoritativnu** odluku jednom dnevno, sve drugo samo prikazuje.

---

## 4. CDN file struktura

### `eotd/index.json` — manifest svih dana

```json
{
  "version": "1.0",
  "generated_at": "2026-05-26T22:55:00+02:00",
  "first_date": "2024-09-01",
  "last_date": "2026-05-26",
  "days": [
    {
      "date": "2026-05-26",
      "video_id": "Ma5rS3rIJ28",
      "channel_id": "laudato",
      "channel_name": "Laudato",
      "title_hr": "Razgovor s nadbiskupom Bozanićem",
      "thumbnail": "https://cdn.domovina.ai/images/Ma5rS3rIJ28/thumbnail.png",
      "magisterium_score": 87,
      "reason": "hi_quality_recent"
    }
  ]
}
```

Veličina: ~200 bytes po danu, za 5 godina ~365KB. CDN-edge-cached, gzip ~80KB.

### `eotd/<YYYY-MM-DD>.json` — frozen pick za jedan dan

```json
{
  "version": "1.0",
  "date": "2026-05-26",
  "frozen_at": "2026-05-26T22:55:00+02:00",
  "video_id": "Ma5rS3rIJ28",
  "channel_id": "laudato",
  "channel_name": "Laudato",
  "title": "Sve počinje s Bogom",
  "title_hr": "Razgovor s nadbiskupom Bozanićem",
  "thumbnail": "https://cdn.domovina.ai/images/Ma5rS3rIJ28/thumbnail.png",
  "og_image": "https://cdn.domovina.ai/eotd/og/og-eotd-2026-05-26.jpg",
  "duration_seconds": 4980,
  "magisterium_score": 87,
  "reason": "hi_quality_recent",
  "reason_details": {
    "tier": 1,
    "combined_score": 83.4,
    "score_weight": 0.6,
    "recency_weight": 0.4,
    "candidate_pool_size": 12,
    "candidate_pool_top5": ["Ma5rS3rIJ28", "abc123", "def456", "ghi789", "jkl012"]
  },
  "speakers": ["mons. Dražen Kutleša", "Davor Dijanović"],
  "topics": ["evangelizacija", "Crkva u Hrvatskoj", "mladi"],
  "integrity_hash": "sha256:..."
}
```

`integrity_hash` = `sha256(date + video_id + magisterium_score)` — frontend može verify-at da pipeline nije naknadno mijenjao odabir.

### `eotd/og/og-eotd-<YYYY-MM-DD>.jpg` — social share image

1200×630 JPEG (<600KB za WhatsApp), generiran iz Tier B pipeline-a. Sadrži:
- Pozadina: blurred `og-share.jpg` od video-a
- Overlay: "EPIZODA DANA · DOMOVINA.ai" gornji red, datum middle, naslov + kanal donji
- Crveno-bijelo-plavi accent (suptilno, ne literalna zastava)

---

## 5. Worker rute (Cloudflare `_worker.js`)

Postojeći worker već handle-a OG injection za `/v/<ytId>` i `/v/<ytId>/t/<sec>` (vidi `[[share_og_architecture]]` u memory). Dodajemo:

```js
// /dan/<YYYY-MM-DD>
if (pathname.startsWith('/dan/')) {
  const date = pathname.slice(5);  // YYYY-MM-DD
  if (!isValidDate(date)) return env.ASSETS.fetch(request);
  const eotd = await fetch(`${CDN}/eotd/${date}.json`, { cf: { cacheTtl: 300 }});
  if (!eotd.ok) return new Response('Epizoda dana nije dostupna', { status: 404 });
  const data = await eotd.json();
  const html = await env.ASSETS.fetch(new URL('/index.html', request.url)).then(r => r.text());
  return new Response(injectEotdTags(html, data), {
    headers: { 'content-type': 'text/html;charset=UTF-8' }
  });
}

// /dan (kronoloska lista) — bez special OG, samo prosli SPA
if (pathname === '/dan') return env.ASSETS.fetch(request);
```

`injectEotdTags` replace-a meta tagove s:
- `og:title` = "Epizoda dana · {{date_long_hr}} — {{video.title_hr}}"
- `og:description` = "{{channel_name}} · Magisterium {{score}}/100. Slušaj sad."
- `og:image` = `eotd/og/og-eotd-<date>.jpg`
- `og:url` = `https://domovina.ai/dan/{{date}}`
- JSON-LD `BreadcrumbList`: Početna → Epizoda dana → {{date}}
- JSON-LD `PodcastEpisode` (postojeći schema iz `/v/<id>`)

---

## 6. Flutter rute

### `/dan` — kronološka arhiva

Lista grupirana po mjesecu, novost desc. Svaka kartica:
```
┌──────────────────────────────────────┐
│ SVIBANJ 2026                          │
├──────────────────────────────────────┤
│ 26 ✦ [thumb] Razgovor s nadbiskupom  │
│      Laudato · ✝ 87                   │
├──────────────────────────────────────┤
│ 25 ✦ [thumb] Druga epizoda...        │
│      Crta · ✝ 82                      │
└──────────────────────────────────────┘
```

Source: `eotd/index.json` (jedan fetch, sve dani).

### `/dan/:date` — single day

Identičan layout kao home hero, ali:
- Header "EPIZODA DANA · 26. svibnja 2026."
- Pored "ZAŠTO?" gumba dodatni "PREUZMI BADGE" gumb (vidi sekciju 8)
- Footer navigacija: `← Prethodni dan` · `Sutra (zaključano)` ili `Sljedeći dan →`
- Magisterium pill linkom na trenutni `/v/<id>` da user klikne na "Slušaj"

Source: `eotd/<date>.json`.

### `lib/screens/eotd/`

Nova mapa, paralelno sa `home/` i `channel/`. Klase:
- `eotd_archive_screen.dart` — `/dan`
- `eotd_day_screen.dart` — `/dan/:date`
- `eotd_card.dart` — kompaktna kartica za arhiv listu
- `eotd_service.dart` — fetcher za index.json + per-day JSON s cache-om

---

## 7. Algoritam (server-side)

Replicira `lib/screens/home/home_feed.dart::pickFeatured`, ali:
- **Snapshot ulaza**: pipeline u trenutku run-a fixira channel listing JSON u memoriju, pa odluka ne ovisi o naknadnim promjenama
- **Bez rotacije**: server ne treba seed jer svaki dan ima jedan output
- **Deterministic**: za isti dataset uvijek isti winner

Output uključuje `reason_details.candidate_pool_top5` — pipeline serializira top 5 kandidata pa frontend može pokazati "Today's runner-ups" ako želimo kasnije.

### Edge case: dan bez ijedne epizode

Ako tier 1-3 prazan, ne emitirati `eotd/<date>.json` taj dan. `eotd/index.json` preskače taj dan. Worker vraća 404, frontend pokazuje "Tog dana nije bilo epizode dana".

### Edge case: backfill

Prvi pipeline run nakon deploya generira sve passed days od **datuma početka projekta** (npr. `2024-09-01`). Za svaki dan pipeline:
1. Filtrira `channel index` na epizode `date <= <iter_date>`
2. Primjenjuje algoritam
3. Emitira `eotd/<iter_date>.json`

Backfill je idempotentan — može se ponoviti.

---

## 8. Creator-facing assets

### 8.1 Public badge (HTML embed)

URL: `https://domovina.ai/badge/eotd/<date>.html` (worker route, vraća izolirani HTML snippet).

```html
<a href="https://domovina.ai/dan/2026-05-26" target="_blank"
   style="display:inline-flex;align-items:center;text-decoration:none;font-family:sans-serif">
  <img src="https://cdn.domovina.ai/eotd/badge/badge-2026-05-26.svg"
       alt="Epizoda dana — DOMOVINA.ai — 26. svibnja 2026."
       width="240" height="80">
</a>
```

SVG badge ima fixed dimenzije, retina-ready, pokazuje: "✦ EPIZODA DANA · DOMOVINA.ai · 26.05.2026."

### 8.2 Email outreach template (creator)

Pipeline cron generira po Epizodi dana automatski email šablon:
```
Subject: Vaša epizoda "{{title}}" izabrana je za Epizodu dana 26.05.2026.

Pozdrav {{channel_name}},

vaša epizoda je danas Epizoda dana na DOMOVINA.ai.

Permalink: https://domovina.ai/dan/2026-05-26
Badge za vašu stranicu: https://domovina.ai/badge/eotd/2026-05-26
Social share image: https://cdn.domovina.ai/eotd/og/og-eotd-2026-05-26.jpg

Kriteriji izbora (Magisterium {{score}}/100, top 5 dnevne rotacije, AI obrada): ...

Slobodno share-ajte!
```

Šaljemo manualno preko Gmail (ili automatski preko Supabase trigger-a ako odlučimo opt-in).

### 8.3 "Preuzmi badge" gumb

Na `/dan/:date` stranici, pored "ZAŠTO?" gumba na hero-u: dropdown s 4 opcije:
- Copy permalink URL
- Copy HTML badge embed kod
- Download PNG share image (`og-eotd-<date>.jpg`)
- Download SVG badge (`badge-<date>.svg`)

---

## 9. Edge cases

| Scenarij | Ponašanje |
|---|---|
| Cron failed taj dan | `index.json` preskače dan; worker vrati 404; manualni re-run mogućuje. |
| Featured epizoda obrisana s YouTube-a kasnije | JSON ostaje (frozen), ali video player na single-day pokaže "Više nije dostupno". Permalink i badge i dalje rade. |
| Magisterium score-a naknadno mijenja | `frozen_at` timestamp u JSON-u dokumentira kad je odluka donesena. Pipeline NE prepisuje povijesne dane. |
| Vremenske zone | Pipeline koristi Europe/Zagreb. Date u URL-u je Zagreb-local, ne UTC. |
| Više winnera s istom kombiniranom ocjenom | Tiebreaker: alphabetical po `video_id`. Deterministic. |
| Buduća epizoda izaberi se neka | Pipeline filter: `date <= today_zagreb`. |

---

## 10. Open questions

1. **Manual override**: hoćemo li dopustiti admin tooling da prepiše odabir za određeni dan (npr. urednik insistira na nekoj epizodi)? **Predlažem: ne za v1**, pure algorithmic. Manual override stvara kontroverzu.
2. **"Nedjelja samo Magisterium-only"**: ima li smisla da subotni/nedjeljni izbor ima viši threshold (npr. score≥80)? Razlog: aktivniji religijski content kraj tjedna. **Predlažem: ne, drži se uniform-a.**
3. **Multi-language**: hoćemo li imati EOTD i za `/en/dan/...` ako bude engleska verzija? **Predlažem: pričekati realnu potražnju.**
4. **Per-channel "Episode of the Month"**: derived feature, kompliciraniji. **Backlog.**
5. **Voting / community input**: bez moderacije rizično. **Backlog.**

---

## 11. Implementation phases

### Faza 0 — Spec freeze
- Ovaj dokument review + approve
- Razgovor s pipeline repo-om (fetch.domovina.tv) o cron-u

### Faza 1 — Pipeline backend (fetch.domovina.tv repo)
1. Implementiraj `pickFeatured` u Python-u (parity s Dart-om u `home_feed.dart`)
2. Cron job 23:55 Zagreb time
3. Output `eotd/index.json` + `eotd/<date>.json`
4. Backfill skripta za sve passed days od `2024-09-01`
5. Generate `og-eotd-<date>.jpg` (postojeći Tier B compositor + EOTD overlay)
6. Generate `badge-<date>.svg`

### Faza 2 — Worker (web/_worker.js u ovom repo)
1. `/dan/:date` route s OG injection (recikliraj postojeći `injectShareTags` pattern)
2. `/dan` route → passthrough na SPA (SEO-friendly meta)
3. `/badge/eotd/:date` → vrati standalone HTML
4. JSON-LD breadcrumb + PodcastEpisode schema

### Faza 3 — Flutter frontend (ovaj repo)
1. `lib/services/eotd_service.dart` — fetch + cache
2. `lib/screens/eotd/eotd_day_screen.dart`
3. `lib/screens/eotd/eotd_archive_screen.dart`
4. Router rute u `lib/router/app_router.dart`
5. Footer link "Arhiva — Epizoda dana"
6. "Preuzmi badge" dropdown na single-day stranici
7. Update home `HeroSection` — "Vidi sve epizode dana →" link

### Faza 4 — Creator outreach
1. Email template generator (može biti CLI skripta u pipeline-u)
2. Lista kontakata za podcast kreatore (manualno održavana)
3. First batch outreach (5-10 kreatora) — feedback loop
4. Twitter/X anuncia "Predstavljamo Epizodu dana"

---

## 12. Memory references

- [[cdn-file-layout]] — kompletna CDN mapa, dodati `eotd/` sekciju
- [[share-og-architecture]] — postojeći OG injection pattern (recikliraj za `/dan/<date>`)
- [[share-timestamp-clips]] — Tier B og-image generation (recikliraj za `og-eotd-<date>.jpg`)
- [[project-pipeline]] — fetch.domovina.tv pipeline koji dobiva cron job

---

## 13. Implementacija — kad krećemo

**Trigger**: nakon što homepage redesign (v2.0.13+) bude deployed i stabilan ~tjedan dana, krenuti Fazom 1 (pipeline backend) u fetch.domovina.tv repo-u. Frontend dolazi nakon što pipeline emitira makar 5-10 dana podataka.

**Vrijeme procjena**:
- Faza 1: 1-2 dana (Python algoritam port + cron + backfill)
- Faza 2: pola dana (worker route)
- Faza 3: 1 dan (Flutter rute + UI)
- Faza 4: ongoing (manualno outreach)

Ukupno: ~3 dana fokusiranog rada za MVP.
