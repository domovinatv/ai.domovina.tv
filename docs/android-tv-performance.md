# Android TV — performanse, tradeoff-evi i arhitekturni put

Analiza performansi DOMOVINA.ai Flutter aplikacije na Android TV hardveru,
s fokusom na EON SDSTB02 (Amlogic, Android 11 / API 30) kao referentni
low-end uređaj. Pisano 2026-05-28 nakon splash + cold-start optimizacijske
sesije.

> **TL;DR**: Cold start je riješen (~2.1s na EON). Preostali problem je
> **UI jank tijekom interakcije**. Još NIJE izmjereno je li raster-bound
> (GPU) ili UI-bound (Dart). Hipoteza: raster-bound zbog render rezolucije.
> Native Kotlin rewrite NIJE preporučen sada (TV je sekundarna platforma,
> solo dev, web je primaran). Prvo iscrpiti Flutter optimizacije.

---

## 1. Profile vs Release — razbijanje mita

**Profile build je već AOT-kompajliran**, isto kao release. Dart kod se
izvršava punom native brzinom u oba moda. Razlika:

| | Debug | Profile | Release |
|---|---|---|---|
| Dart compile | JIT (sporo) | AOT | AOT |
| Observatory / VM service | da | da | ne |
| Timeline tracing hooks | da | da | ne |
| Assertions | da | ne | ne |
| Tree-shake + obfuskacija | ne | djelomično | da |

**Zaključak**: release je **~10-25% glađi** od profile-a, NIJE
transformacija. Ako UI zastajkuje u profile-u, zastajkivat će i u release-u,
samo manje. Debug bi bio 3-5× sporiji (JIT) — ali sva mjerenja u ovoj
sesiji su rađena na **profile** buildu, koji je reprezentativan za release.

**Nemoj očekivati da release "popravi" jank.** Pomoći će na marginama.

---

## 2. Cold start — RIJEŠENO (~2.1s na EON)

Baseline mjerenje 2026-05-28 na EON-u (profile build, `am start -W`):

```
Run 1:  TotalTime 2255ms  (anomaly — prvi nakon installa, AOT warmup)
Run 2:  TotalTime 2122ms
Run 3:  TotalTime 2114ms
Median steady-state: ~2.1s tap-to-first-frame
```

Engine-side trace (`build/start_up_info.json`):
```
timeToFrameworkInitMicros:        584ms   ← framework boot
timeToFirstFrameMicros:          1275ms   ← prvi Flutter frame nakon engine entry
timeToFirstFrameRasterizedMicros: 1334ms
```
System cold-start (2.1s) − engine first-frame (1.3s) ≈ 900ms za Activity
creation + JNI lib load + native splash composition prije engine entry-a.

**Bivša pretpostavka od 12-19s bila je netočna** — to je bio percipirani
"wait" tijekom Flutter loading splash perioda (ChannelCache prefetch 40
kanala), ne tap-to-first-frame.

### Što je primijenjeno za cold start

- **Impeller off** (`io.flutter.embedding.android.EnableImpeller=false` u
  manifestu) — vidi §3. Marginalan učinak na cold start na ovom HW-u
  (Impeller nije bio glavni bottleneck u profile mode-u kako se pretpostavljalo).
- **Engine pre-warm POKUŠAN I POVUČEN** — `FlutterEngineCache` pre-warm u
  custom `Application.onCreate` + `getCachedEngineId()` u MainActivity
  **collide-a s audio_service plugin-om**. `AudioServiceActivity` override-a
  `provideFlutterEngine()` da vrati svoj plugin-managed engine, što ignorira
  naš cached engine → `main()` se izvršava DVAPUT (dva engine-a u procesu),
  `Displayed` time regredira na 2.9s, i pojavi se
  `MissingPluginException` jer prvi engine nema MainActivity channel-e.
  **Pravilo: ne koristiti FlutterEngineCache pre-warm s audio_service-om.**

---

## 3. Impeller vs Skia tradeoff

Trenutno: **Impeller OFF, Skia renderer aktivan** (potvrđeno logcat-om:
`Impeller opt-out deprecated`).

| | Impeller | Skia |
|---|---|---|
| Shader compile | precompila (spor first start na Amlogic) | on-demand (jank prvi put kad se efekt pojavi) |
| Maturity | noviji | zreliji, godinama na ovom HW-u |
| Cold start na Amlogic | sporiji (shader compile stall) | brži |

**Nije crno-bijelo.** Skia može uzrokovati "shader jank" prvi put kad se
neki efekt renderira (prvi scroll, prva tranzicija). Postoji srednji put
koji NISMO probali:

- **SkSL warmup bundle** (`flutter build --bundle-sksl-path`): snimiš
  shadere tijekom profile run-a, bundle-aš ih, Skia ih preloada → nema
  first-time jank-a. Pre-Impeller standard. **Vrijedi probati prije nego
  se odustane od Skia.**
- Alternativa: re-enable Impeller + zadrži neki način da se shader compile
  cost sakrije (ali engine pre-warm ne radi s audio_service-om — vidi §2).

---

## 4. Preostali problem — UI jank tijekom interakcije (NEIZMJERENO)

Nakon brzog cold starta, korisnik prijavljuje da **UI zastajkuje** tijekom
interakcije (scroll, navigacija).

**Ključno: još NISMO izmjerili koji je thread bottleneck.** Dva potpuno
različita uzroka koji se različito rješavaju:

- **UI thread jank** = Dart prespor (build / layout / setState) →
  fix: widget optimizacija (const, RepaintBoundary, flatten tree, manje
  rebuilds)
- **Raster thread jank** = GPU ne stiže crtati → fix: manje piksela
  (niži DPR), manje overdraw, manje GPU-teških efekata (BackdropFilter/blur)

**Sljedeći korak (5 min, odlučuje sve ostalo)**: `flutter run --profile`
na EON-u + performance overlay (`PerformanceOverlay` widget ili pritisni
`P` u konzoli). Crvena traka = koji thread je bottleneck.

### Hipoteza: raster-bound zbog render rezolucije

Flutter renderira na `devicePixelRatio`. Na 4K TV-u to je ~8M piksela po
frameu kroz slab Amlogic GPU fill-rate. **Forsiranje nižeg DPR-a**
(renderiraj na 1080p, pusti TV da hardware-upscale-a) može dati **2-4× više
GPU headroom-a** — često najveći single win na slabom TV hardveru.

EON je density 320 → 960×540 dp (vidi memory `tv_known_devices`), ali
fizički renderira na puno više piksela. Provjeriti `MediaQuery.devicePixelRatio`
i razmotriti override preko `MediaQuery.copyWith` ili native window scaling.

---

## 5. Native Kotlin vs Flutter — iskrena procjena

**Pitanje**: bi li full native (Leanback / Compose for TV) bio osjetno
glađi, ili su problemi fundamentalni za ovaj HW bez obzira na framework?

**Odgovor: native JEST osjetno glađi na ovoj klasi hardvera.** Razlozi:

- Flutter crta **svaki piksel sam** kroz Skia/Impeller → GPU. Ne koristi
  native Android view sistem.
- Native `RecyclerView` je godinama optimiziran baš za scroll listu kartica
  na slabom hardveru; hardware-accelerated native compositing koji OEM-ovi
  (Amlogic, MediaTek) tuneaju za svoj silicij.
- Leanback library (`BrowseSupportFragment`) je purpose-built za D-pad TV
  navigaciju.
- Netflix / YouTube / Disney+ na ovim box-evima su native (ili teško
  customizirani) **upravo zato** što moraju raditi na najslabijem
  zajedničkom nazivniku.

**ALI — protuargumenti presudni za DOMOVINA kontekst:**

- Solo dev (vidi memory `user_profile`); web je **primarna** platforma.
- Flutter codebase već servira web + mobile + macOS iz jednog koda.
- Native TV = **drugi codebase paralelno**, dupli maintenance, duplo featurea.
- Compose for TV je relativno mlad, ima vlastite perf čudnovatosti.
- TV je tek u Fazi 1-4 (započeto 2026-05-27), još se **validira** kao
  platforma.

**Native rewrite za sekundarnu platformu koja se još validira = premature
optimization s ogromnim troškom za solo dev-a.**

---

## 6. Preporučeni dugoročni put

Redoslijed (svaki korak mjerljiv, jeftin prije skupljeg):

1. **IZMJERI** — performance overlay na EON-u. Raster ili UI bound? Ovo
   prvo; sve ostalo ovisi o tome.
2. **Ako raster-bound (najvjerojatnije)**:
   - Forsiraj niži DPR na TV-u (render 1080p umjesto 4K)
   - `RepaintBoundary` na rail kartice (izolira repaint)
   - Makni `BackdropFilter` / blur efekte (GPU ubojice na slabom HW-u)
   - `const` konstruktore gdje god ide
3. **Shader jank**: SkSL warmup bundle (`--bundle-sksl-path`).
4. **Release build** za zadnjih 10-25%.
5. **TEK AKO** sve gore plateau-ira iznad prihvatljivog jank-a **I** TV
   postane primarna platforma s pravim korisnicima na slabim box-evima →
   razmotri native, i to možda samo TV shell (Leanback browse) s Flutter-om
   za detalje (add-to-app hybrid).

**Realna procjena**: koraci 2-4 vjerojatno dovedu Flutter na "dovoljno
glatko" za EON-klasu. Većina Flutter TV jank-a je render rezolucija +
overdraw, ne fundamentalni Flutter limit. Native je nuklearna opcija s
troškom koji se za sad ne isplati.

---

## Reference

- Cold start baseline: `build/start_up_info.json` (regeneriraj s
  `flutter run --profile --trace-startup -d <eon>`)
- Splash arhitektura: `docs/splash-bible-citations.md`
- Splash randomization research: `docs/splash-randomization-research.md`
- Impeller cold start issue: flutter/flutter#175128
- Memory: `tv_performance_architecture`, `tv_known_devices`,
  `feedback_flutter_engine_prewarm_audioservice`
