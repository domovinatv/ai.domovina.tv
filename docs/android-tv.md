# Android TV (Leanback) podrška

Standalone 10-foot UI varijanta DOMOVINA.ai aplikacije za Android TV uređaje (Philips,
EON Smart Box, NVIDIA Shield, Chromecast s Google TV-om, itd.). Ne pokušava se
retrofitati postojeći desktop/mobile layout — paralelni `lib/screens/tv/` modul
dijeli `services/*` i `models/*` s ostatkom aplikacije, ali ima vlastiti home,
channel, episode/player i widget set.

## TV detekcija flow

Detekcija je sinhrona u runtimeu (resolve-ana jednom u `main()` prije `runApp`):

```
main()                                            lib/main.dart
  └─ await TvMode.init()                          lib/services/tv_mode.dart
       ├─ if (FORCE_TV dart-define) → isTv=true
       ├─ if (kIsWeb || !Android)    → isTv=false
       └─ else MethodChannel("ai.domovina/tv_mode").invokeMethod("isLeanback")
            └─ MainActivity.kt
                 packageManager.hasSystemFeature(FEATURE_LEANBACK) → true/false
```

Nakon `init()`, `TvMode.isTv` je sync getter koji čitaju:

- **`lib/main.dart`** — odabire `AppTheme.tv()` umjesto `light()/dark()` + forsira `ThemeMode.dark`
- **`lib/router/app_router.dart`** — `/` ruta i `errorPageBuilder` rute na `TvHomeScreen` umjesto `HomeScreen`

URL strukturu (`/`, `/c/:slug`, `/v/:id`, itd.) **držimo identičnu** za TV i ne-TV — bitno
za deep linking, social sharing, i potencijalan handoff iz mobitela na TV kasnije.

## Dev workflow

### Lokalno (Mac/Chrome) — primarni iteracijski loop

```bash
flutter run -d macos  --dart-define=FORCE_TV=true
flutter run -d chrome --dart-define=FORCE_TV=true
```

Tab/Shift+Tab simulira D-pad LEFT/RIGHT, Enter = OK. Većina Faze 2-5 razvija se
ovako jer je hot reload <1s. TV se koristi za finalni sanity check po fazi.

### Na pravom Android TV uređaju

ADB-over-Tailscale je najbolji setup (vidi memory `tv_dev_workflow.md`):

```bash
adb connect <tailscale-hostname>:5555
flutter devices                                # provjera
flutter run -d <ip>:5555                       # bez FORCE_TV — pravi Leanback
adb -s <ip>:5555 logcat -s flutter             # uživo logovi
scrcpy --tcpip=<ip>:5555                       # mirror TV ekrana na Mac
```

Operatorski Android TV box-ovi (Telemach EON, A1, T-Com) često **otvaraju port
5555 čim uključiš USB debugging u Developer Options** — ne treba USB ni `adb pair`.
Provjera: `nc -zv <ip> 5555`.

## Faza plan

| Faza | Status | Sadržaj |
|---|---|---|
| 1 | ✅ Done | TV detekcija (MethodChannel + FORCE_TV), `AppTheme.tv()`, skeleton `TvHomeScreen` s autofocus hero gumbom + jednim placeholder rail-om, Leanback launcher manifest |
| 2 | ⏳ Next | Pravi rail-ovi (Featured hero + Nastavi slušati + Najnovije + Kanali) wired-up na `HomeFeed`/`ChannelCache`/`WatchProgressService` |
| 2.5 | Planned | TV search ekran s on-screen IME tipkovnicom |
| 3 | Planned | `TvChannelScreen` (`/c/:slug` TV varijanta) — 4×N grid s D-pad nav, sort chips |
| 4 | Planned | `TvEpisodeScreen` (`/v/:id` TV varijanta) — fullscreen player s overlay kontrolama, MEDIA_PLAY_PAUSE handling, BACK overlay-aware |
| 4.5 | Planned | TV handoff ekran (`/handoff` TV varijanta) — XL kod + QR za cross-device sign-in |
| 5 | Planned | Polish + Play Store TV listing (banner PNG, screenshots, AAB) |

## Build & deploy

```bash
flutter build apk --debug                      # za sideload
flutter build appbundle --release              # za Play Store TV track
adb install build/app/outputs/flutter-apk/app-debug.apk
```

`scripts/deploy.sh` ostaje web-only (Cloudflare Pages). TV release ima vlastiti
track u Play Console-u — listing zahtijeva 3 TV screenshota 1920×1080, banner
320×180 (trenutno placeholder XML, vidi `android/.../drawable/tv_banner.xml`),
i `<uses-feature leanback />` u manifestu (već postoji).

## Focus model (Faza 1+)

Svaki interaktivni element ima vlastiti `FocusNode` + `FocusableActionDetector`.
Vizualna pravila:

- **Card fokus**: scale 1.08 + 4px ring u `colorScheme.primary` (crveni)
- **Primary button fokus**: scale 1.06 + 4px ring u `colorScheme.onSurface` (bijeli na crvenom)
- **Subtle button fokus**: `primaryContainer` background + 4px ring u `primary`
- **Auto-scroll**: `Scrollable.ensureVisible(alignment: 0.5)` kad fokus dođe na karticu izvan viewport-a

Detalji: `lib/screens/tv/tv_home_screen.dart` (Faza 1 lokalni helperi se
promoviraju u `lib/screens/tv/widgets/` kad počnu služiti drugim TV screenovima
u Fazi 2+).

## Theme adjustments

`AppTheme.tv()` (`lib/theme/app_theme.dart`):

- Dark base (Croatian navy seed, `Brightness.dark`)
- 1.3× tipografija (`textTheme.apply(fontSizeFactor: 1.3)`)
- Crveni `tertiary` ostaje za primarne CTA (PLAY)
- Ostatak ColorScheme tokena nasljeđen iz `_build(scheme)` — `surface`, `outline`,
  `surfaceContainerHighest`, itd. su konzistentni s dark mode-om

## Known device quirks

- **Telemach EON Smart Box (SDMC SDSTB02)**: Android 11, ali density je 320 dpi
  što daje logički ekran 960×540 dp na 1080p TV-u. `TvHomeScreen` koristi
  `LayoutBuilder` da hero skalira na 45% visine (clamp 220-380 dp).
- **Philips 55PUS7303/12 (Android 8.0 Saphi)**: ADB authorization dialog je
  bug-an na operator-customized Saphi launcheru. Bez USB-a ne može se autorizirati
  ključ. Workaround: jednokratni USB visit s `adb tcpip 5555` +
  `setprop persist.adb.tcp.port 5555` preživi reboot.

## Files added/modified u Fazi 1

```
lib/services/tv_mode.dart                                  +new
lib/screens/tv/tv_home_screen.dart                         +new
lib/theme/app_theme.dart                                   +tv() factory
lib/main.dart                                              +TvMode.init() + theme branch
lib/router/app_router.dart                                 +TV import + / route + error branch
android/app/src/main/AndroidManifest.xml                   +leanback features + LEANBACK_LAUNCHER + banner
android/app/src/main/kotlin/ai/domovina/MainActivity.kt    +MethodChannel handler
android/app/src/main/res/drawable/tv_banner.xml            +new placeholder
```
