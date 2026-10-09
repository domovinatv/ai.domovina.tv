# Boot splash: od prvog bajta do prvog Flutter framea (9.10.2026.)

## 1. Što se događalo

Plavi HTML splash (`#boot-intro`) micao se na `flutter-first-frame` **ili nakon
fiksnih 6 s**. `<html>`/`<body>` nisu imali pozadinu, a `#legal-footer` je
namjerno trajno u DOM-u (Google OAuth provjera). Na sporoj mreži Flutter treba
puno više od 6 s, pa je korisnik gledao bijelu stranicu s footerom.

Mjereno na produkciji (v2.0.174), mobilni viewport 390 px, hladni cache:

| profil | splash nestaje | `main()` start | prvi frame | bijela praznina | `main()`→`runApp` |
|---|---|---|---|---|---|
| bez throttlinga | 1,5 s | 1,3 s | 1,5 s | 0 | 0,2 s |
| Slow 4G | 6,4 s | 16,7 s | 19,7 s | **13,3 s** | 3,0 s |
| 3G | 6,8 s | 34,0 s | 37,1 s | **30,3 s** | 3,0 s |

```bash
python3 scripts/measure-boot.py https://domovina.ai/ --profile none
python3 scripts/measure-boot.py https://domovina.ai/ --profile slow4g --mobile
python3 scripts/measure-boot.py https://domovina.ai/ --profile 3g --mobile
```

Profili su u headeru skripte (Slow 4G = 1,6 Mbit/s / 150 ms RTT, Lighthouse).

## 2. Gdje ode vrijeme na sporoj mreži

Put je **ograničen propusnošću**, ne latencijom:

| datoteka | preko žice | host |
|---|---|---|
| `main.dart.wasm` | 1,57 MB (br) | domovina.ai |
| `skwasm.wasm` | 1,2 MB | gstatic.com |
| google_fonts (7 varijanti TTF) | ~0,7 MB | fonts.gstatic.com |

≈ 3,5 MB pri 1,6 Mbit/s ≈ 17–18 s, što odgovara izmjerenom prvom frameu.

```bash
curl -s -o /dev/null -H 'Accept-Encoding: br' -w '%{size_download}\n' https://domovina.ai/main.dart.wasm
```

Usputni nalazi (nisu popravljeni u ovom koraku):

- `main()`→`runApp` je na sporoj mreži točno 3,0 s: `AppTypography.awaitPreload`
  dosegne svoj timeout, jer fontovi kreću tek kad Dart starta (serijski iza
  wasma). Preload fontova iz HTML-a ne bi pomogao — isti bajtovi, ista cijev.
  Pomaže samo manje bajtova (subset/woff2 umjesto punih TTF-ova).
- `main.dart.wasm` počinje tek kad stigne `main.dart.mjs` (~0,5 s na Slow 4G,
  ~1 s na 3G). `<link rel=preload>` bi to uštedio, ali na pregledniku bez
  WasmGC (stariji Safari, ide `main.dart.js`) bi potrošio 1,5 MB uzalud.
- `main.dart.wasm` ima `cf-cache-status: DYNAMIC`, TTFB ~0,5 s (ostali asseti
  ~0,07 s). Worker ga šalje uz `CDN-Cache-Control: no-store`.

## 3. Što je promijenjeno (`web/index.html`)

- **Splash se miče samo na `flutter-first-frame`.** Fiksni timeout od 6 s je
  maknut. Osigurač za slučaj da event izostane (promjena enginea): 20 s
  **nakon što stigne `main.dart.wasm`/`.js`** — tada je sve preuzeto, a
  `main()` do `runApp` traje ≤ ~3 s, pa osigurač nikad ne otkrije prazninu.
- **Boja prije prvog framea = boja teme.** Inline skripta u `<head>` čita
  `localStorage['theme_mode']` (isti ključ kao `ThemeController`) i postavlja
  `data-theme`; `html` i splash dobivaju `#111318` (tamna, default) ili
  `#faf7f2` (svijetla) — `scaffoldBackgroundColor` iz `AppTheme`. Prijelaz
  splash → aplikacija je fade unutar iste boje. Pozadina je samo na `html`,
  ne na `body`, jer bi body prekrio `#legal-footer` (`z-index:-1`).
- **Hijerarhija:** wordmark „DOMOVINA" + crveni „.ai" (kao u headeru),
  podnaslov, tanki indikator, faza. Opis za Google provjeru i linkovi ostaju u
  izvornom HTML-u, prigušeni na dnu.
- **Istinite faze:** „Preuzimanje aplikacije…" → „Pokretanje…" kad
  `PerformanceObserver` vidi da je stigao `main.dart.wasm`/`.js`. Nakon 8 s
  preuzimanja: „Veza je spora. Aplikacija se preuzima samo prvi put…"
  (istina: asseti se nakon toga revalidiraju s 304).
- **Greška:** neuspjelo učitavanje skripte enginea/aplikacije ili odbijen
  fetch/compile wasma prije prvog framea → „Učitavanje je zapelo." + gumb
  „Pokušaj ponovno".

Poslije (lokalni release build kroz `wrangler pages dev build/web`, Slow 4G,
mobilni): splash do 20,1 s, prvi frame 20,1 s, **praznina 0 ms**; snimke svake
2 s pokazuju samo splash.

```bash
python3 scripts/measure-boot.py http://localhost:8788/ --profile slow4g --mobile --shots /tmp/shots
```

## 4. Otvoreno (sljedeći koraci, po učinku)

1. Fontovi: ~0,7 MB TTF-ova je ~3 s na Slow 4G (= 3 s timeout u `main()`).
   Subset (latin + latin-ext) kao asset ili manje varijanti.
2. Edge cache za `main.dart.wasm` (TTFB 0,5 s → ~0,07 s) — provjeriti je li
   `CDN-Cache-Control: no-store` još nužan uz purge u deploy skripti.
3. Preload `main.dart.wasm` samo kad preglednik ima WasmGC (inline detekcija).
