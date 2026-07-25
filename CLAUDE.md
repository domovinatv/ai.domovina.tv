# CLAUDE.md — DOMOVINA.ai

## Project Overview

Flutter web/mobile app for AI-processed Croatian podcast episodes.
All data loads from CDN (`cdn.domovina.ai`). Deployed on Cloudflare Pages.

- **Package ID**: `ai.domovina`
- **Display name**: `DOMOVINA.ai`
- **Platforms**: Web (primary), Android (+ Android TV / Leanback), iOS, macOS

## Build & Deploy

```bash
./scripts/deploy.sh          # release build + deploy + CDN purge
./scripts/deploy.sh --debug  # profile build (unminified) + deploy + CDN purge
```

Deploy script runs: `flutter pub get` → `flutter analyze` → `flutter build web` → `wrangler pages deploy` → Cloudflare cache purge → HTTP verification.

`.env` must contain `CLOUDFLARE_ZONE_ID` and `CLOUDFLARE_PURGE_TOKEN`.

## AI tim (tmux, 5 panela)

`./scripts/tim.sh` diže jedan tmux session s pet Claude Code panela:
**planner** (opus, tu čovjek promptira) → **orkestrator** (fable) →
**dev1/dev2** (opus) → **reviewer** (fable, diže se na opus za rizičan diff).
Petlja, helperi (`tim-send.sh`/`tim-read.sh`/`tim-status.sh`) i zamke:
`docs/ai-tim-tmux.md`. Uloge: `.claude/commands/{delegiraj,tim,pregled}.md`.

Session se zove `tim-<repo-slug>` (`tim-domovina-ai`) da timovi za različite
projekte na istom stroju ne kolidiraju. **Rule**: tmux radi prefix matching na
imenima sessiona — `kill-session`/`has-session`/`attach` uvijek s `=` prefiksom
(`-t "=$(./scripts/tim-status.sh session)"`), inače možeš ubiti tuđi tim.

**Rule**: agent NIKAD ne šalje poruke u planner panel (korisnik ondje tipka) —
napredak ide u tmux status bar preko `scripts/tim-status.sh set "…"`. Review
ide PRIJE commita i PRIJE `/clear`, da dorade padnu devu kojem je kontekst još
živ.

## Known Issues & Gotchas

> **Web delivery, rendering & caching** (service worker staleness, cache-busting
> header strategy, channel-list scroll perf, prefetch race, Flutter-web image
> debug decision tree) — vidi `docs/web-delivery-and-rendering.md`.
>
> **Tech-stack odluka (Flutter vs Expo/RN, 2026)** — zašto OSTAJEMO na Flutteru
> unatoč web-bolu, i kad bi Expo bio bolji: `docs/tech-stack-assessment-flutter-vs-expo.md`.
> TL;DR: ne prepisivati; web zamke su omeđene i dokumentirane.

### SharedPreferences crashes on web release builds

`SharedPreferences` throws `MissingPluginException(No implementation found for method getAll on channel plugins.flutter.io/shared_preferences)` in dart2js release mode. The method channel plugin registration is stripped during minification.

**Fix**: Web uses `window.localStorage` directly via `package:web`. Native (iOS/Android/macOS) uses `SharedPreferences` normally. Gated by `kIsWeb` in `home_screen.dart`.

**Rule**: Never use `SharedPreferences` on web. Always check `kIsWeb` and use `localStorage` for browser persistence.

### ensureSemantics na webu — stara zabrana OPOVRGNUTA (2026-07-22)

Povijesno pravilo "ensureSemantics crasha release web build" retestirano na
Flutter 3.41.6: **crash se NE reproducira** ni na skwasm (`--wasm`) ni na
dart2js putanji, ni s pozivom odmah nakon `ensureInitialized()`. Originalna
atribucija (2026-03-31) gotovo je sigurno bila kriva — u istom periodu su
postojali SharedPreferences/flutter_svg crashevi na minificiranom buildu.

Semantics ipak NIJE uključen svima uvijek, zbog poznatih **bihevioralnih**
web bugova (flutter/flutter#163576 P1 — click-through kroz preklapajuće
widgete). Trenutni mehanizam u `main.dart`:

- `?a11y=1` query param → `ensureSemantics()` odmah (za Playwright/Cypress
  e2e i ručnu inspekciju a11y DOM-a).
- Screen readeri: Flutterov ugrađeni `flt-semantics-placeholder` (pali
  identično stablo — potvrđeno, 73 čvora na home).
- `Semantics(identifier: 'pinka-*')` sidra na doniraj ekranu izlaze kao
  `flt-semantics-identifier` atribut. Vidi `docs/e2e-testing.md`.

**Rule**: prije eventualnog always-on uključivanja ručno protestirati
overlay klikove (search palette, share sheet) zbog #163576.

### flutter_svg crashes on web

`flutter_svg` (`SvgPicture.asset`) causes `Uncaught Error` on web builds. Replaced with `Image.asset` using PNG version of the logo.

**Rule**: Use PNG (`Image.asset`) instead of SVG for in-app images on web.

### Universal/App Links NE smiju hvatati auth callback rute

Web OAuth povratak (`GoTrue → https://domovina.ai/auth/callback`) je
cross-origin redirect — ako ga native app presretne kao universal/app link,
web prijava se prekine otvaranjem appa (bug viđen na iOS-u 2026-07-22).

- **iOS** (`web/_worker.js` AASA_JSON): `components` s `exclude: true` za
  `/auth/*`, `/login-callback`, `/youtube-claim/*` + legacy `NOT` u `paths`.
  Apple CDN/uređaji cachiraju AASA — propagacija tek nakon reinstalacije
  appa ili do ~tjedan dana.
- **Android** (`AndroidManifest.xml`): intent filter nema exclude sintaksu —
  App Links su ALLOWLIST content putanja (`/v/`, `/m/`, `/c/`, `/p/`,
  `/handoff`, `/`, `/channels`). Auth rute namjerno izostavljene.
- Native login flow koristi `ai.domovina://` custom scheme — na njega ovo
  ne utječe.

**Rule**: nova javna content ruta → dodaj u OBA popisa (AASA components +
Android intent filter). Nova auth/callback ruta → NE dodavati, i provjeri
da je pokrivena AASA exclusionom. Deploy skripta ima tripwire koji provjeri
live AASA exclusion.

### Auth return-to (povratak na izvornu rutu nakon prijave)

Prije OAuth/magic-link full-page redirecta `AuthService` sprema path+query u
localStorage (`auth_return_to`); `AuthCallbackScreen` vraća korisnika tamo
umjesto na `/`. Čista logika u `lib/services/auth_return_path.dart`,
kontrakt čuvaju unit testovi u `test/auth_return_path_test.dart`
(open-redirect guard + callback-loop guard). Ne zaobilaziti sanitizaciju.

### Auth nudge NIKAD ne prekida reprodukciju

Onboarding momenti M1 (snackbar o napretku) i M2 (auth sheet nakon 30 s
slušanja) obrisani su 2026-07-25 — modal preko videa prekida upravo ono zbog
čega je korisnik došao. Zamjena je `widgets/anonymous_signin_bar.dart`: trajna
slim traka u `bottomNavigationBar` ekrana epizode, vidljiva samo dok je
`AuthService.instance.isAnonymous`.

**Rule**: novi nudge (prijava, pretplata, install) → persistent surface
(traka/kartica/chip). Modal SAMO kad ga je korisnik svojim tapom pozvao;
snackbar SAMO kao potvrda korisnikove radnje (kao M3 na favorit).

**Rule (safe area na dnu)**: kad se u `bottomNavigationBar` slaže više traka
koje se nezavisno pale/gase (gost traka, `PinkaSupportBar`, mobilna nav),
donji `SafeArea` ide na zajednički Column — nikad na pojedinu traku. Inače je
ili duplo (dvije sestre primijene isti inset) ili nula (sve se sakriju).

Prolaz kroz auth UI/UX + otvoreni backlog: `docs/auth-ux-backlog.md`.

### Backend placement — Cloudflare Worker vs Supabase Edge Function

**Rule (decide by purpose):** does the backend code read/write our Postgres
(`api.domovina.ai`, Supabase on Coolify) for a logged-in user, or need the
service role / GoTrue admin / RLS context?

- **No** (pure proxy / presentation / third-party SaaS that hides a vendor key
  but doesn't touch our DB) → **Cloudflare Pages Worker** (`web/_worker.js`).
  Examples: SPA routing, OG injection, the Cal.com proxy (`/api/cal/*`,
  `CAL_API_KEY`). Never put `SUPABASE_SERVICE_ROLE_KEY` or DB writes here.
- **Yes** → **Supabase Edge Function** (`domovina-api/supabase/functions/`),
  where the service role is auto-injected and lives only on Coolify. Examples:
  `revenuecat-webhook` (writes entitlement state), `pinka-webhook`, auth bridges.

Full rationale + examples: `domovina-api/docs/backend-architecture.md`.

### Cloudflare Pages pretty URLs

Cloudflare auto-strips `.html` extensions (`/social-test.html` → `/social-test`). The worker in `_worker.js` checks for `.html` files in ASSETS before falling back to SPA routing.

### Cache purge required after deploy

Cloudflare CDN caches aggressively. Always purge cache after deploy (the deploy script does this automatically). Without purge, users may see stale versions.

### Android TV — AV1 codec ne-radi u hardware decoder-u

EON SDSTB02 (Amlogic, Android 11) i većina Android TV box-ova prije ~2024.
godine **nemaju funkcionalan AV1 hardware decoder** unatoč tome što
`av1_mediacodec` postoji u sistemu. Pokušaj otvaranja AV1 streama daje:

```
ffmpeg/video: av1_mediacodec: Both surface and native_window are NULL
ffmpeg/video: av1_mediacodec: Unsupported or unknown profile
```

**Trenutni video.mp4 na CDN-u je AV1 Main @ 640×360**. Software decode
radi (bitrate je nizak ~94 kbps), ali zahtijeva eksplicitno `hwdec=no`
u libmpv konfiguraciji. Vidi `lib/screens/tv/tv_episode_screen.dart`
gdje se to setira preko `player.platform.setProperty('hwdec', 'no')`.

**Production deployment strategija** (TODO): pipeline bi trebao producirati
i H.264 fallback verziju (`video.h264.mp4` paralelno s `video.mp4`/AV1).
App bi onda pickao codec ovisno o platformi/device-u. H.264 hardware
decode radi univerzalno od Android 4 nadalje. Bez ovoga, novi 720p/1080p
AV1 sadržaj neće glatko playati na većini Android TV box-ova.

### Android TV lokalni emulator (dev loop)

EON-matched emulator na Mac miniju za brzu TV layout/D-pad iteraciju. Auto-detektira
se kao Leanback (bez `FORCE_TV`), ali **ne reproducira EON perf/jank** (Mac GPU +
arm64 native). Setup, svakodnevne komande i objašnjenje rezolucije (960×540 dp je
logički dp prostor uz dpr 2.0, NE downsampling — EON crta native 1920×1080):
`docs/android-tv-emulator.md`.

**Rule**: prije `emulator @EON_TV_API31` mora se mountati APFS kontejner
(`hdiutil attach /Volumes/DOMOVINA2TB/android_emulators/DOMOVINA_ANDROID.sparsebundle`)
jer SSD je exFAT i sve živi u tom kontejneru. Perf mjeriš samo na fizičkom EON-u.

### Native Android splash je static (nije rotirajuc)

Pokušali smo runtime rotaciju biblijskih citata u native splash-u (5
različitih pristupa), ali Android <12 starting window se ne može
runtime-modificirati (komponira se iz manifest teme PRIJE Activity-a).
Puna istraga: `docs/splash-randomization-research.md`. Verdict: nemoguće
na API <12 bez vidljivih nuspojava (activity-alias rotacija razbacuje
ikonu po Leanback Apps row-u).

**Trenutna splash arhitektura** (vidi `docs/splash-bible-citations.md`):
- Native splash = premium full-frame 4K PNG (`splash_full_1.png`,
  Mt 10,26-27 KS Jeruzalemska Biblija).
- Flutter `TvBootSplash` prikazuje istu sliku + "Učitavanje…" progress
  za seamless native→Flutter kontinuitet.
- Generiranje: `scripts/generate-premium-splash-taglines.py` (PIL auto-fit;
  `--all` za svih 14 citata). Mirror u `assets/splash/` za Flutter asset.

**Rule**: ne dirati `MainActivity.kt` za splash rotaciju — nemoguće. Za
promjenu native splash teksta: edit `VERSES` u Python skripti, rerun,
rebuild. Citati MORAJU biti KS Jeruzalemska Biblija (biblija.ks.hr), ne
Magisterium AI raw — vidi `docs/splash-bible-citations-factcheck.md`.

### Flash između native i Flutter splash-a — NormalTheme windowBackground

`NormalTheme.windowBackground` MORA biti isti drawable kao
`LaunchTheme.windowBackground` (`@drawable/launch_background`). Inače Flutter
theme swap pri prvom frame-u zamijeni splash sliku za crno → vidljiv flash.
Vidi `values/styles.xml` + `values-night/styles.xml`.

### Impeller disabled na svim Android buildovima — Skia renderer

`io.flutter.embedding.android.EnableImpeller=false` u AndroidManifest.xml.
Razlog: Impeller shader compile na low-end Amlogic GPU (EON). Trenutno
koristimo Skia. Tradeoff + buduće opcije (SkSL warmup) + cijela TV perf
analiza: `docs/android-tv-performance.md`.

**Rule**: ne re-enable-ati Impeller bez re-mjerenja cold starta na EON-u.
NE koristiti `FlutterEngineCache` engine pre-warm — collide-a s
audio_service `provideFlutterEngine()` (dupli `main()`). Detalji u perf docu.

### media_kit web — fullscreen/tap/subtitle gotchasi

media_kit (2.0.1) na webu ima 4 zamke; sve ih rješava zajednički wrapper
`lib/widgets/episode_video.dart` (koriste ga VideoPanel i episode_simple_screen):

1. Ulazak u fullscreen pauzira video — enterFullscreen pusha novu rutu s novim
   `Video` widgetom pa se `<video>` re-parenta u DOM-u (remove+insert = pauza
   po HTML spec-u). Fix: auto-resume nakon tranzicije (retry 300/900 ms).
2. Esc izađe iz browser fullscreena, ali Flutter fullscreen ruta ostane —
   paket nema `fullscreenchange` listener. Fix: `lib/services/browser_fullscreen.dart`
   (conditional import web/stub) + exit preko `GlobalKey<VideoState>`.
3. `playAndPauseOnTap` je default OFF — klik na video ne radi ništa bez toga.
4. `setSubtitleTrack` na webu traži VTT (`<track>` element; SRT ne radi) i u
   sourcu piše "UNTESTED". Titlove rendamo SAMI: `diarized.srt` → cue text u
   `SpeakerTimeline` → overlay kroz `controls:` builder (radi i u fullscreenu).

**Rule**: za video u episode ekranima koristi `EpisodeVideo`, ne goli `Video`.
YouTube embed mode = službeni youtube-nocookie iframe (`lib/widgets/youtube_embed.dart`,
web-only) — NIKAD ad-stripping ili stream extraction (YouTube ToS).

### Thumbnail caching — cached_network_image (TV)

TV thumbnail-i koriste `CachedThumbnail` widget (`lib/widgets/cached_thumbnail.dart`)
koji wrap-a `cached_network_image` — disk-persistent cache (preživljava app
restart) + sivi placeholder + error widget. Cache key = URL, pa CDN `?v=`
cache-buster prirodno invalidira. Web/mobile screens još koriste raw
`Image.network` (TODO: proširiti ako se potvrdi benefit).

**Rule**: za nove TV thumbnail-e koristi `CachedThumbnail`, ne `Image.network`.

## Logging

`main.dart` exports a `log()` function that prefixes messages with `[DOMOVINA v{version}]`. Use it throughout the app for console debugging:

```dart
import '../main.dart' show log;

log('MyWidget.build()');
log('fetch complete: ${items.length} items');
```

Logs are visible in browser DevTools console and help trace the exact point of failure in release builds where stack traces are minified.

**Rule**: When adding new async operations or widget builds that could fail, add `log()` calls at key checkpoints. This is critical because release web builds minify all symbols — without logs, errors show only `Uncaught Error` at an unreadable line number.

## Internationalization (i18n)

> Puna referenca s mermaid dijagramima (UI vs sadržaj, string resolution,
> locale perzistencija, key-prefiksi, Magisterium uzrok) —
> `docs/i18n-and-localization.md`.

App UI is fully localized via Flutter `gen-l10n` (ARB). **Hrvatski je izvorni/template
jezik**, engleski je drugi jezik. Konfiguracija u `l10n.yaml`; ključevi u
`lib/l10n/app_hr.arb` (template, s `@key` metapodacima + placeholderima) i
`lib/l10n/app_en.arb` (prijevod). Generirana klasa: `lib/l10n/app_localizations.dart`
(`flutter gen-l10n` ili automatski preko `generate: true`).

**Razlika UI jezik vs. jezik sadržaja**: ovo je jezik *chrome-a* (gumbi, naslovi,
poruke) i bira ga `LocaleController` (`services/locale_service.dart`, persist u
localStorage/SharedPreferences, default HR, prebacivač u `/account`). ODVOJENO od
per-epizoda jezika *sadržaja* (`services/episode_language.dart` +
`widgets/language_toggle_chip.dart`), koji bira HR/EN CDN članak/Magisterium preko
`pickLang(...)`. CDN/model tekst se NIKAD ne lokalizira kroz ARB — samo hardkodirani
Dart literali.

**Kako lokalizirati novi string:**
- Dodaj ključ PRVO u `app_hr.arb` (+ `@key` ako ima placeholdere/plural), pa prijevod
  u `app_en.arb`, pa `flutter gen-l10n`.
- U widgetu s contextom: `final l = AppLocalizations.of(context); … l.mojKljuc`.
- Bez contexta (servisi, callbackovi, modeli): `appStrings.mojKljuc` (globalni getter u
  `services/locale_service.dart` → `lookupAppLocalizations(LocaleController…locale)`).
- **Rule (live language switch)**: `appStrings` NE registrira dependency na
  Localizations scope — tekst renderiran preko njega u buildu ostaje na starom
  jeziku nakon promjene UI jezika (stale dok se widget ne rebuilda iz drugog
  razloga). Zato: sve što se perzistentno renderira → `AppLocalizations.of(context)`
  (ili proslijeđen `AppLocalizations l` parametar); `appStrings` SAMO za
  jednokratni event-time resolve (SnackBar, `_error` u catch bloku, outreach
  poruke, servisi). Enum/model copy getteri primaju `AppLocalizations l`
  parametar (primjeri: `ChannelSortMode.label(l)`, `UpgradeTriggerCopy.headline(l)`,
  `MagisteriumSection.scoreLabel(score, l)`). Sweep 2026-07-23 poravnao codebase.
- **Rule (dvosmjerna sprega jezika)**: svaki prebacivač UI jezika
  (`LanguageToggleButton`, account SegmentedButton) sprema i preferirani jezik
  sadržaja (`savePreferredLanguage`), a `LanguageToggleChip` (jezik sadržaja na
  epizodi) postavlja i UI locale — sadržaj i sučelje se uvijek prebacuju zajedno.
- Imenovanje ključeva: `<područje>CamelCase` (npr. `home*`, `episode*`, `magisterium*`,
  `legal*`, `auth*`, `channel*`, `ownership*`, `tv*`, `pinka*`, `service*`, `common*`).
  `common*` za stringove dijeljene kroz aplikaciju (Odustani, Zatvori, Pokušaj ponovno…).
- ICU plural za brojive imenice (hrvatski one/few/other). Imena jezika u prebacivaču su
  endonimi ("Hrvatski"/"English") — namjerno NISU u ARB-u.

**Rule (registar/ton)**: aplikacija oslovljava korisnika **neformalno „ti"**
(topli, izravan glas, usklađen s pinka SDK-om). Iznimka: **outreach poruke trećim
stranama** (npr. `ownershipInviteMessage` vlasniku kanala) i pravni/formalni tekst —
tu je „Vi" ispravno. Ne miješaj registar unutar istog konteksta.

**Rule (lektor)**: svaki user-facing string mora imati ispravne dijakritike
(č/ć/š/ž/đ), gramatiku i pravopis (Hrvatski pravopis IHJJ — npr. „sažetci", „pogreške",
„adresa e-pošte"). Bez ALL-CAPS u ARB vrijednostima; vizualni caps radi se u kodu preko
`.toUpperCase()` na već lokaliziranom stringu.

**TODO (poznato)**: `widgets/founder_booking.dart` koristi ručne hrvatske nazive
mjeseci/dana (`_hrWeekdayShort`/`_hrMonthsGen`) — za pravu lokalizaciju datuma treba
`intl` `DateFormat` s locale podrškom (van opsega string-ekstrakcije).

## Architecture Notes

### Scrollabilne liste — rubni padding UNUTAR scrolla

Scrollabilni sadržaj (horizontalni railovi, breadcrumbovi, vertikalne liste)
mora klizati do fizičkog ruba ekrana; rubni razmak postoji samo u mirovanju.
Vanjski `Padding` oko scrollabla "reže" sadržaj na uvučenom rubu — izgleda
odrezano, posebno na mobile.

**Rule**: padding ide kao `padding:` parametar NA listu
(`ListView`/`SingleChildScrollView`/`SliverPadding`), nikad kao `Padding`
wrapper oko nje. Scrollabilni sadržaj u `AppBar`/`SliverAppBar` title →
`titleSpacing: 0` + padding unutar scrollabla (primjer: `home_app_bar.dart`).
Bottom sheet s horizontalnom listom → sheet padding bez horizontalne
komponente, sekcije nose svoj h-padding (primjer: `founder_booking.dart`).
Iznimka: bordered card/panel/dialog gdje je padding chrome kartice.
Sweep 2026-07-23 poravnao cijeli codebase na ovaj pattern.

### Routing

`main.dart` uses `onGenerateRoute` with `PageRouteBuilder(transitionDuration: Duration.zero)` for instant navigation. The initial route uses `home: const HomeScreen()` — do NOT replace with `initialRoute` or `onGenerateInitialRoutes` as both crash on web.

### Croatian flag theme

Colors from the logo SVG:
- Red: `#FF0000` (`_croRed`)
- White: `#FFFFFF`
- Navy blue: `#002F6C` (`_croBlue`)

Theme seed: `Color(0xFF002F6C)` (Croatian navy).

### Social sharing

- Homepage: static OG tags in `web/index.html` + JSON-LD structured data
- Episode pages: dynamic OG injection in `web/_worker.js` (Cloudflare Worker)
- OG image: `web/og-image.png` (1200x630) generated from `assets/icons/og-image.svg`
- Test page: `https://domovina.ai/social-test`
- Test script: `node scripts/test-social-tags.mjs`
