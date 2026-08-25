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
`docs/ai-tim-tmux.md`. Uloge: `.claude/commands/{delegiraj,tim,pregled}.md`,
kickoff `/pocni` (skripta ga sama pošalje planneru; `TIM_AUTOSTART=0` gasi).

`./scripts/tim-kickoff.sh [--fresh]` (skill `/digni`) gasi stari tim, diže
novi **headless**, pošalje planneru kickoff i na kraju `exec tmux attach` u
prozoru u kojem je pokrenuta. Višelinijski prompt ide u
`.tim/kickoff-prompt.md`, planneru se šalje samo putanja — TUI svaki `\n` čita
kao submit. Bez `--fresh` se attacha na postojeći tim i prompt se NE šalje.

**Rule (prozore otvara ČOVJEK)**: agent NIKAD ne otvara, ne resizea i ne
zatvara iTerm prozore — ni `osascript`, ni `open -a`. Za novi posao timu agent
napiše `.tim/kickoff-prompt.md` i **da korisniku komandu**; korisnik otvori
prozor (⌘N) i pokrene je. Razlog je izmjeren 8.8.2026.: kad se ubije session na
koji su prozori attachani, iTermov AppleScript se trajno zablokira
(`AppleEvent timed out -1712`, do restarta iTerma) — stari tim je bio ubijen a
novi se nije digao. Uz to `create window … command` vraća `missing value`, a
`current window` odmah nakon `create window` pokaže KRIVI prozor (`set bounds`
je otišao korisnikovom Claude prozoru). Puni popis u headeru
`scripts/tim-kickoff.sh`.

Session se zove `tim-<repo-slug>` (`tim-domovina-ai`) da timovi za različite
projekte na istom stroju ne kolidiraju. **Rule**: tmux radi prefix matching na
imenima sessiona — `kill-session`/`has-session`/`attach` uvijek s `=` prefiksom
(`-t "=$(./scripts/tim-status.sh session)"`), inače možeš ubiti tuđi tim.

**Rule**: agent NIKAD ne šalje poruke u planner panel (korisnik ondje tipka) —
napredak ide u tmux status bar preko `scripts/tim-status.sh set "…"`. Review
ide PRIJE commita i PRIJE `/clear`, da dorade padnu devu kojem je kontekst još
živ.

## Git & AI Co-authoring

**Rule (AI Commit Trailers)**: Kako bi se očuvala zajednička memorija o tome koji je AI asistent (Claude Code, Antigravity, Codex, itd.) odradio koji zadatak, **SVI** agenti prilikom kreiranja Git commitova MORAJU dodati standardni *Git trailer* u poruku commita.
Format mora biti: `Co-authored-by: <Ime Agenta> (<Verzija Modela>) <bot@domena>`
Primjer: `Co-authored-by: Antigravity (Gemini 3.1 Pro) <bot@antigravity.google>` ili `Co-authored-by: Claude Code (Claude 3.7 Sonnet) <bot@anthropic.com>`.

**Rule (dokumentacija se provjerava, ne vjeruje joj se)**: prije nego preuzmeš
tuđi (ili svoj stariji) `docs/*.md` kao izvor istine, pokreni
`./scripts/verify-doc-refs.sh docs/*.md` — provjeri postoji li svaka `lib/…`
putanja citirana u markdownu i predloži pravu ako ne. Povod je izmjeren
14.8.2026.: AI-generirana analiza citirala je 33 putanje od kojih 6 nije
postojalo (imena datoteka točna, direktoriji izmišljeni), uz 186 kB generirane
ispune u istom setu dokumenata. Dokument koji NAMJERNO citira krivu putanju
omeđi s `<!-- doc-refs:ignore-start -->` / `<!-- doc-refs:ignore-end -->`.
Isto pravilo vrijedi za brojke: ako broj ima decimalu, mora postojati naredba
koja ga reproducira (primjer: `docs/podcasterium_analysis_report.md` §7).

## Nightly store build (launchd, 01:00)

`scripts/nightly-build.sh` svaku noć — ako je HEAD drukčiji od zadnjeg uspješno
izgrađenog — gradi iOS + Android iz **odvojenog git worktreea** i šalje ih na
TestFlight i Play internal. Ishod ide u Telegram grupu preko
`scripts/telegram-notify.rb`. Puna slika: `docs/nightly-build-pipeline.md`.

- **Testovi su tvrda vrata** — pad → nema uploada. Poznati crveni testovi žive u
  `.nightly/test-baseline.txt` (praćen u gitu) i izuzeti su iz vrata, ali se i
  dalje vrte; kad prorade, nightly javi da ih makneš.
- **Build broj se računa** (`max(ASC, Play, pubspec) + 1` → `--build-number`),
  pubspec se NE dira i nightly ne piše u git.
- **Rule**: sve što ide u Telegram mora kroz `telegram-notify.rb` — grupa je
  javna, a ta skripta redigira vrijednosti iz `.env`, JWT-ove i `--dart-define`
  parove prije slanja. Nikad `curl` izravno na Bot API.
- **Rule**: launchd job mora biti **LaunchAgent** (`gui/$(id -u)`), ne Daemon —
  `xcodebuild` potpisivanje traži otključan login keychain iz Aqua sesije.
- Stanje storeova u bilo kojem trenutku: `./scripts/store-status.rb`
  (review state, TestFlight `processingState`, Play rollout %).
- **Rule (build artefakti NE idu izravno na `/Volumes/DOMOVINA2TB`)**: taj exFAT
  ima alokacijski blok od **512 KB**, pa je Gradle home od 14 GB u 156 000
  datoteka pri kopiranju narastao na **41 GB** (izmjereno 2026-08-13). Sve što
  ima puno sitnih datoteka ide u APFS sparsebundle
  (`domovina_ai_build_files/DOMOVINA_BUILD.sparsebundle` → `/Volumes/DOMOVINA_BUILD`,
  blok 4 KB). `~/.gradle` je simlink onamo; kontejner montira
  `launchd/ai.domovina.build-volume.plist` pri prijavi, a nightly ga digne sam ako
  treba. Ista logika kao emulatorski `DOMOVINA_ANDROID.sparsebundle`.

## Tripwire: registar podcasta ↔ glasački bazen (launchd, 08:30)

`domovina_ai.vote_candidates` je **snimka** `fetch.domovina.tv/data/podcasts_registry.json`,
ne živi pogled — podcast dodan u registar ne stigne u bazu dok se ne pokrene
`sync_voting_candidates.mjs --commit`. Izmjereno 25.8.2026.: registar je 17 dana
nosio 37 kandidata (AbbaCast među njima) kojih u bazi nije bilo, korisnici za njih
nisu mogli glasati, i ništa to nije javilo.

`scripts/voting-drift-check.sh` (launchd `ai.domovina.voting-drift`) svako jutro
usporedi registar i bazu; tiho je kad su poravnati, na drift javi u Telegram.
Sama usporedba je `node sync_voting_candidates.mjs --check` u fetch repou —
**filtar kandidata (§3) živi na jednom mjestu**, u sync skripti, i tripwire ga
ne prepisuje. (Reimplementacija filtra je pri prvom pokušaju dala 164 umjesto
218 kandidata.) `--check` preskače yt-dlp i CDN pa traje sekundu; exit 0 =
poravnato, 1 = drift, 2 = ne mogu provjeriti.

**Rule**: tripwire NE pokreće `--commit` sam od sebe — sync uploada avatare na
CDN i mijenja `status` redova, pa je to promjena produkcijskih podataka koju
potpisuje čovjek. `--sync` flag postoji ako se to ikad svjesno promijeni.

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

### Fontovi na webu — `<link>` u index.html NE oblikuje Flutter tekst

canvaskit/skwasm ne čita `@font-face` iz dokumenta (to je radio samo stari HTML
renderer). Sve dok je `AppTypography` na webu postavljao goli
`fontFamily: 'Playfair Display'` i računao na `<link>` u `web/index.html`,
Flutter je taj font tražio među **registriranima**, ne nalazio ga i padao na
ugrađeni fallback: naslovi i wordmark su se na webu crtali sans-serifom umjesto
Playfairom (izmjereno 25.8.2026. na produkciji), a pojedini glyphovi znali su
nestati dok asinkroni Noto fallback ne stigne.

Fontovi se zato registriraju kroz `google_fonts` na **svim** platformama.
`web/index.html` `<link>` ostaje — njime se crta HTML boot-intro splash (pravi
DOM, prije Fluttera) i ugrije `fonts.gstatic.com`.

**Rule**: novi font/težina u `lib/theme/typography.dart` mora ići i u
`AppTypography._usedVariants`. `main()` zove `startPreload()` odmah, a
`awaitPreload()` pred `runApp` — inače se prvi frame crta fallbackom pa cijela
stranica prelomi kad pravi font stigne.

### Hero na naslovnici se otkriva TEK kad je izbor konačan

`ChannelCache` javlja svakim učitanim kanalom, a `HomeFeed.pickFeaturedCarousel`
rangira po **trenutno** učitanom bazenu. Hero je zato tijekom prefetcha
prelistavao kandidate (bljeskanje + skakanje stranice). Sada
`_ChannelGridViewState` latcha izbor jednom — kad je `channelCache.done` (ili
nakon 6 s grace prozora, uz `hasMinimumData`) — i više ga ne dira.

**Rule**: `HeroSkeleton` mora biti **točno jednako visok** kao `HeroCarousel`,
uključujući `kHeroControlBarHeight` (zato karusel s jednim pickom zadržava
praznu kontrolnu traku). Kontrakt čuva `test/hero_slot_layout_test.dart`;
mijenjaš li hero layout, mijenjaj i skeleton. Testni font je širi od Intera pa
test namjerno drži meta red u jednom retku.

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

**RIJEŠENO** (provjereno 15.8.2026., ovo je nekad bio TODO): pipeline producira
H.264 verziju kao **`video_h264.mp4`** (podvlaka, ne točka) paralelno s
`video.mp4`/AV1. Klijent bira sam — `DataService.resolveMedia()` probe-a redom
`video_h264.mp4` → `audio.mp3` → legacy `video.mp4`. H.264 hardware decode radi
univerzalno od Android 4 nadalje.

**Rule**: probe URL MORA nositi cache-buster (`videoH264ProbeUrl`) — CDN cachira
404 četiri sata, pa bi jedan prerani probe zaključao fallback na cijeli prozor.

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

### Kontrole reprodukcije — brzina, seek-undo, rotacijski fullscreen

Uvedeno 2026-07-27 (plan `docs/plans/2026-07-27-playback-overhaul.md`, zaključak
i otvoreni dug u `-zakljucak.md`). Servisi: `services/playback_speed.dart`
(globalna brzina po uređaju, kružno kroz `kPlaybackRates`),
`services/seek_undo.dart` (detekcija RUČNOG skoka nad `player.stream.position`),
`services/screen_orientation.dart`. Dijeljeni widgeti:
`widgets/playback_controls.dart`.

**Rule**: nova kontrola playera ide u `playback_controls.dart` i mora se
pojaviti na **tri** mjesta — video traka, `video_panel.dart` i `_PlayerTab` u
`episode_simple_screen.dart`. Zadnja dva su jedina putanja za **audio-only**
epizode, gdje `EpisodeVideo` uopće ne postoji.

**Rule (stanje kontrole ide kroz singleton, ne kroz propove)**: iste kontrole
crtaju tri odvojena stabla, a na mobitelu je player u `endDraweru` — prop
drilling se tu neizbježno negdje ispusti. `PlaybackSpeed`, `BackgroundPlayback`
i `PlayerMute` su zato singletoni; `VideoPanel` nema parametre za njih.
(Povijest: `mutedAutoplay`/`onUnmute` su bili propovi i **nedostajali su na
obje mobilne pozivne točke** — unmute na mobitelu nije postojao.)

### Muted autoplay — browserska politika, ne naš bug

Autoplay **sa zvukom** dopušten je samo uz prethodni gesture: Chromium traži
klik/tap po domeni u toj sesiji (ili MEI prag na desktopu / PWA na home
screenu), WebKit traži `muted` element ili audio-less stream i **pauzira
reprodukciju ako se element odmuta bez gesturea**. Hladno otvoren share link
(`/v/<id>/t/<sec>`) nema ništa od toga → `openAndResume` pada na muted
autoplay i to zapiše u `PlayerMute` singleton.

Iz tog se stanja izlazi ISKLJUČIVO korisnikovim tapom. Zato UI mora ponuditi
tri izlaza: `UnmuteOverlay` preko slike, `MuteToggleButton` u trakama, i (na
mobitelu) gumb „Video" u donjoj traci koji se pretvori u „Uključi zvuk" — jer
je on jedina površina koju korisnik vidi dok je player u zatvorenom draweru.

**Rule (mute na webu = `muted` property, NIKAD `volume`)**: na iOS-u
`HTMLMediaElement.volume` nije zapisiv (setter je no-op, getter uvijek 1), a
media_kitov `setVolume` usput **skida** `muted` flag — pa `setVolume(0)` na
iPhoneu ne mutira ništa i autoplay ostane odbijen. Mute na webu ide preko
`services/media_element_mute_web.dart` (`<video>.muted`); `player.setVolume`
je samo native putanja i fallback.

**Rule (širinski budžet trake)**: `MuteToggleButton` ide SAMO u mobilnu
media_kit traku — desktop varijanta već ima `MaterialDesktopVolumeButton`, a
osmi slot bi joj probio 328 dp (`test/playback_bar_layout_test.dart`).

**Rule**: prag detekcije skoka ne spuštati ispod 1 s — `position` stream fira
~5×/s, pa je pri brzini 2,0× prirodni pomak ~0,4 s i niži prag bi generirao
lažne skokove. Programski seek (resume, tap na poglavlje, sam Undo) mora ići uz
`SeekUndo.suppress()`.

**Rule**: fullscreen su **tri** putanje, ne jedna — pravi landscape na nativeu
(`SystemChrome`, probija sistemsku bravu rotacije), `screen.orientation.lock`
na Android Chromeu, vizualna rotacija (`RotatedBox`) ondje gdje oboje padne
(iPhone Safari/Chrome). Desktop široki viewport ostaje na media_kitovoj ruti.
Naša ruta jednako re-parenta `<video>` → koristi postojeći
`_resumeAfterTransition`, ne piši novi.

**Poznato, nepopravljeno**: `MediaSession.clear()` na webu ne postavlja
`playbackState = 'none'`, pa iOS ostavlja *mrtvu* stavku u Dynamic Islandu
(vidljiva, tap ne radi ništa). Dizajniran popravak i zamke re-registracije:
`docs/ios-background-playback.md` §4.3. Tap na Dynamic Island koji otvara
aplikaciju je namjerno iOS ponašanje — to nije bug i ne može se isključiti dok
želimo pozadinski zvuk.

### Thumbnail caching + WebP varijante — `CachedThumbnail`

Sve slike epizoda idu kroz `CachedThumbnail` (`lib/widgets/cached_thumbnail.dart`):
disk-persistent cache, sivi placeholder, error widget, i — ako je URL kanonski
`/images/{id}/thumbnail.png` — **automatska zamjena WebP varijantom** po
render-širini (`thumb-320/640/1280.webp`, pipeline KORAK 9.7). Call-siteovi ne
znaju za varijante. Fallback na PNG ide kroz `errorWidget` (ne `errorListener`).

*(Povijesno: do 25.8.2026. su varijante koristili SAMO TV ekrani, a web je i
dalje vukao PNG od ~830 KB po slici — naslovnica ~20 MB. Sada ~0,9 MB.)*

**Rule**: za slike epizoda koristi `CachedThumbnail`, ne `Image.network`.
Uvijek proslijedi `width` kad ga znaš — bez njega widget pesimistično uzima
širinu ekrana i bira najveću varijantu.

**Rule (CORS je tvrdi uvjet)**: `CachedNetworkImage` povlači bajtove kroz
`package:http`, pa URL MORA imati `access-control-allow-origin`.
`Image.network` na webu ima `<img>` fallback koji CORS preživi — `CachedThumbnail`
ga NEMA. Ne prosljeđuj mu strane hostove bez provjere. Zato su namjerno ostavljeni
na `Image.network`: person avatar + `person_monogram` (host iz `mcp.domovina.ai`),
`pinka_campaign_screen`, i `episode_simple_screen` (`info.thumbnail` =
`i.ytimg.com`, što ionako krši pravilo "nikad `info.thumbnail`").

**Rule (WebP na webu dekodira BROWSER, ne Flutter)**: na nativeu dekodira Skia pa
WebP radi svugdje; na webu podrška prati browser (Chrome 32+, Firefox 65+,
Safari/iOS Safari **14+**). Ne tvrditi da je "Flutter neovisan o browseru" — to
vrijedi samo za native.

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

**Rule (auto-scroll unutar ugniježđenog scrolla)**: `Scrollable.ensureVisible`
scrolla **sve** nadređene scrollable-ove, ne samo najbliži. U horizontalnoj
traci unutar vertikalne stranice to povuče i stranicu — vlastiti
`ScrollController` + ručni izračun offseta (primjer: `PeopleRail` u
`widgets/entities_section.dart`, koji bi inače poništio `_scrollToPersonAnchor`
u `episode_screen.dart`).

### Person hub — osoba postoji i bez gostovanja

`/p/:slug` agregira DVA disjunktna izvora: `episodes[]` (osoba GOVORI,
diarizirano) i `mentions[]` (osoba se SPOMINJE). Identitet je disjunkcija —
povijesna/pokojna figura (bl. Ivan Merz) ima valjan profil samo iz spomena;
404 tek kad nema ni jedno ni drugo. Backend živi u `domovina-rag`
(`docs/person-hub.md`), ne ovdje.

**Rule**: spomen ima ILI razriješen `first_ts` (tap seeka na sekundu) ILI ga
nema (~40% — tap otvara epizodu od početka). Te dvije stvari se NE smiju
prikazivati isto: `_MentionMomentChip` u `person_screen.dart` je puna brand
crvena vs prigušena obrubljena.

**Rule**: dolazak na epizodu s `?p=<slug>` mora raditi i BEZ `/t/<sec>` —
sidro se tada traži po sadržaju (prva sekcija koja referencira osobu), članak
se doscrolla onamo, ali se video NE seeka (znamo sekciju, ne sekundu). Pill
bez ciljne sekunde nikad ne tvrdi „govori ovdje", nego „ovdje se spominje".

### Routing

Ruting je **go_router 14.8** u `lib/router/app_router.dart` (`createRouter()`).
Puna tablica ruta: `docs/podcasterium_technical_manual.md` §3.

*(Povijesno: ovdje je do 15.8.2026. pisalo da `main.dart` koristi
`onGenerateRoute` s `home: const HomeScreen()` i da `initialRoute` /
`onGenerateInitialRoutes` crashaju na webu. To je zastarjelo — migracija na
go_router se dogodila u međuvremenu, a ova sekcija nije bila ažurirana.)*

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
