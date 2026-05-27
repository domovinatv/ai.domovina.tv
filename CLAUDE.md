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

### Native Android splash je static (nije rotirajuc)

Pokušali smo runtime rotaciju biblijskih citata u native splash-u (4
različita pristupa), ali Android <12 starting window se ne može
runtime-modificirati. Rotacija je premjestena u Flutter splash. Detalji
u `docs/splash-bible-citations.md`.

**Rule**: ne dirati `MainActivity.kt` `setTheme()` logiku za splash — ne
radi. Za promjenu native splash teksta, regeneriraj
`drawable-nodpi/splash_tagline_1.png` i rebuild.

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
