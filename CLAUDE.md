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

## Known Issues & Gotchas

> **Web delivery, rendering & caching** (service worker staleness, cache-busting
> header strategy, channel-list scroll perf, prefetch race, Flutter-web image
> debug decision tree) — vidi `docs/web-delivery-and-rendering.md`.

### SharedPreferences crashes on web release builds

`SharedPreferences` throws `MissingPluginException(No implementation found for method getAll on channel plugins.flutter.io/shared_preferences)` in dart2js release mode. The method channel plugin registration is stripped during minification.

**Fix**: Web uses `window.localStorage` directly via `package:web`. Native (iOS/Android/macOS) uses `SharedPreferences` normally. Gated by `kIsWeb` in `home_screen.dart`.

**Rule**: Never use `SharedPreferences` on web. Always check `kIsWeb` and use `localStorage` for browser persistence.

### ensureSemantics crashes on web release builds

`SemanticsBinding.instance.ensureSemantics()` creates a DOM overlay that causes `Uncaught Error` during the first frame render in release web builds. Removed from `main.dart`.

**Rule**: Do not call `ensureSemantics()` for web builds.

### flutter_svg crashes on web

`flutter_svg` (`SvgPicture.asset`) causes `Uncaught Error` on web builds. Replaced with `Image.asset` using PNG version of the logo.

**Rule**: Use PNG (`Image.asset`) instead of SVG for in-app images on web.

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

## Architecture Notes

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
