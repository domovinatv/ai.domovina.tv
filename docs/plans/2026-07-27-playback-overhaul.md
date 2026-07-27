# Sustavna dorada reprodukcije — Undo skoka, brzina, rotacijski fullscreen, pozadina

## Cilj

Player na `/v/` (detaljno, `episode_screen.dart`) i `/m/` (jednostavno,
`episode_simple_screen.dart`) dobiva četiri stvari koje danas nema, jednako na
webu, iOS-u i Androidu: prekidač „Reprodukcija u pozadini" **i u samom playeru**
(ne samo u `/account`); **Undo nakon ručnog skoka po timelineu** da slučajan
swipe ne izbriše podatak dokle je korisnik stigao; **brzinu reprodukcije** kao
YouTube-ov kružni prekidač 1,0× → 1,25× → 1,5× → 1,75× → 2,0× → 1,0×, zapamćenu
između epizoda; i **rotacijski („virtualni") fullscreen** koji u portretu — i uz
uključenu bravu rotacije — daje landscape sliku. Peta stavka, iOS pozadinska
reprodukcija, je **istraga s izvještajem** (T5), ne unaprijed zadan popravak.

## Kontekst

### Zatečeno stanje (provjereno u kodu 2026-07-27)

| Tema | Gdje | Stanje |
|---|---|---|
| Pozadina | `services/background_playback.dart`; čita se u `episode_screen.dart:681` i `episode_simple_screen.dart:265` | ✅ servis postoji, UI **samo** u `account_screen.dart:317-337` |
| Brzina | — | ❌ `player.setRate()` se ne zove nigdje; `MediaSession.setPositionState(playbackRate:)` hardkodiran na `1.0` (`media_session.dart:43`) |
| Undo skoka | — | ❌ ne postoji |
| Fullscreen | `widgets/episode_video.dart:133-166` | media_kitova ruta (`vs.enterFullscreen()`) + dvije web zakrpe (DOM re-parent pauza, Esc desync) |
| Orijentacija | — | ❌ `SystemChrome`/`DeviceOrientation` se **ne koriste nigdje u repou** — greenfield |

### Seek ide kroz pet putanja bez zajedničkog callbacka

`video_panel.dart` `_SeekBar.onChangeEnd`; slider u `episode_simple_screen.dart:1029`;
`seekOnDoubleTap` unutar media_kita; tipkovničke kratice J/L/←/→
(`episode_video.dart:194-221`); Media Session `seekto` s lock screena.
**Nijedna ne daje hook.** Isti problem kao kod pauze i isto rješenje: jedini
pouzdan izvor istine je `player.stream.position`, kao što je za pauzu
`player.stream.playing` (`services/playback_intent.dart`). Novi servis mora
kopirati taj oblik — stream + getter umjesto `Player`, plus `suppress()` prozor
tolerancije za programske seekove.

### Saznanja o media_kitu (1.2.6 / video 2.0.1, provjereno u pub-cacheu)

- `Player.setRate(double)` postoji (`player.dart:239`); stanje ide kroz `rateController`.
- Fullscreen ruta (`media_kit_video_controls/src/controls/methods/fullscreen.dart`)
  pusha `PageRouteBuilder` s `Material` u korijenu i **novim `Video` widgetom** nad
  istim controllerom. **Nema hooka za ubacivanje rotacije** → rotacijski
  fullscreen mora biti naša ruta, ne njihova. Dvije `Video` instance nad istim
  controllerom su OK — media_kit i sam to radi.
- `onEnterFullscreen`/`onExitFullscreen` su naši callbackovi i zovu se i iz
  njihove rute → tu ide `SystemChrome` forsiranje orijentacije.

### Odluke koje su pale s korisnikom (ne preispitivati)

| # | Odluka |
|---|---|
| D1 | Brzina se **pamti globalno** (uređaj), ne resetira po epizodi. |
| D2 | Undo se nudi **samo za scrub/swipe timelinea i dvoklik ±10 s**. Tap na poglavlje je namjerna navigacija i NE pali Undo. |
| D3 | Na nativeu fullscreen **forsira pravi landscape** (`SystemChrome`) i probija sistemsku bravu rotacije. Vizualna rotacija je fallback samo gdje pravi landscape nije moguć. |
| D4 | iOS istraga (T5) ide **nakon** T1–T4. |
| D5 | Ovaj plan **poništava odluku #1** iz `docs/plans/2026-07-25-background-playback-control.md` („toggle živi samo u /account, ne u control baru playera"). Razlog: prekidač je kontekstualna odluka („sad idem u džep, nastavi svirati"), ne postavka koju se traži u postavkama. `/account` prekidač **ostaje** — isti singleton, dva ulaza. |

---

## Taskovi

### T1 — Servisi: brzina i detekcija skoka

- **Fajlovi**: `lib/services/playback_speed.dart` (novi),
  `lib/services/seek_undo.dart` (novi), `test/seek_undo_test.dart` (novi),
  `test/playback_speed_test.dart` (novi; dodan tijekom izvedbe — pokriva clamp,
  krug, pokvarenu vrijednost i perzistenciju, reviewer r1 potvrdio zadržati),
  `lib/main.dart` (jedna linija inita)

- **Opis**:

  **`playback_speed.dart`** — `ChangeNotifier` singleton **identičnog oblika kao
  `services/background_playback.dart`** (lazy `init()`, `_loaded` guard protiv
  utrke sa setterom, `kIsWeb` → `local_prefs.dart`, native → `SharedPreferences`).
  Ne izmišljaj novi pattern, kopiraj postojeći.

  ```dart
  const kPlaybackRates = <double>[1.0, 1.25, 1.5, 1.75, 2.0];

  class PlaybackSpeed extends ChangeNotifier {
    static final PlaybackSpeed instance = …;
    double get rate;                 // default 1.0
    Future<void> setRate(double r);  // clamp na najbliži iz kPlaybackRates
    double get nextRate;             // kružno, 2.0 → 1.0
  }
  ```

  Ključ `playback_speed`, vrijednost string (`"1.5"`) jer `local_prefs.dart` radi
  sa stringovima. Nepoznata/pokvarena vrijednost → 1.0. Init uz
  `BackgroundPlayback.instance.init()` u `main.dart:124`.

  **`seek_undo.dart`** — čista logika **bez ovisnosti na `media_kit`** (prima
  stream, ne `Player`), po uzoru na `playback_intent.dart`:

  ```dart
  class SeekUndo {
    SeekUndo({
      required Stream<Duration> positionStream,
      Duration jumpThreshold = const Duration(seconds: 2),
      Duration ttl = const Duration(seconds: 8),
    });
    ValueListenable<Duration?> get undoTarget;  // null = nema ponude
    void suppress({Duration window = const Duration(milliseconds: 1200)});
    void consume();   // korisnik prihvatio; seek radi pozivatelj
    void dispose();
  }
  ```

  Detekcija: pamti zadnju viđenu poziciju; `|nova − zadnja| > jumpThreshold` uz
  **zatvoren** prozor tolerancije → ručni skok, `undoTarget = zadnja`, timer na
  `ttl` gasi ponudu.

  Zamke koje moraju biti pokrivene:
  - **Prag vs. brzina 2,0×**: stream fira ~5×/s → prirodni pomak pri 2,0× je
    ~0,4 s. Prag od 2 s je siguran; ne spuštaj ga ispod 1 s.
  - Buffering stall ne pomiče poziciju unaprijed pa ne generira lažni skok —
    ali dokaži to testom (rupa u streamu pa nastavak).

- **Definicija gotovog**: `flutter analyze` čist;
  `flutter test test/seek_undo_test.dart` prolazi s pokrivenim slučajevima:
  prirodni tijek ne pali ponudu; skok naprijed pali; skok natrag pali; skok
  unutar `suppress` prozora ne pali; ponuda istekne nakon `ttl`; `consume()`
  gasi odmah; rupa u streamu (stall) ne pali.

---

### T2 — Dijeljeni widgeti kontrola + i18n

- **Fajlovi**: `lib/widgets/playback_controls.dart` (novi),
  `test/playback_controls_test.dart` (novi; traži ga Definicija gotovog),
  `lib/l10n/app_hr.arb`, `lib/l10n/app_en.arb`, generirani
  `lib/l10n/app_localizations*.dart`

- **Opis**: tri widgeta u jednoj datoteci, jer ista kontrola mora postojati na
  tri mjesta (video control bar, `video_panel` red kontrola, `_PlayerTab` red u
  jednostavnom prikazu) — i za **audio-only** epizode gdje `EpisodeVideo` uopće
  ne postoji (`AudioPoster` putanja).

  - **`SpeedCycleButton`** — tekstualni gumb koji piše trenutnu brzinu
    (`1×`, `1,25×`, `1,5×`, `1,75×`, `2×`); tap → `PlaybackSpeed.instance.nextRate`.
    Brojku formatiraj kroz `NumberFormat.decimalPattern(localeName)` (`intl` je
    već u pubspecu) — hrvatski traži **zarez**, engleski točku. Ne hardkodiraj
    separator.
  - **`BackgroundPlaybackButton`** — `Icons.headset` / `Icons.headset_off`,
    `ListenableBuilder` nad `BackgroundPlayback.instance`; tap prebacuje +
    SnackBar potvrda (SnackBar je ovdje dopušten: potvrda korisnikove radnje).
  - **`SeekUndoPill`** — `↺ Natrag na 1:12:03`, `AnimatedSwitcher` fade, prati
    `SeekUndo.undoTarget`. Stil posudi od `widgets/resume_hint_banner.dart` da
    dvije pilule u istom ekranu izgledaju kao ista obitelj.

  Widgeti primaju `SeekUndo` / callbackove kao parametre — **ne** dohvaćaju
  ekranski state. Boje isključivo kroz `theme.colorScheme.*`.

  Novi ARB ključevi (prefiks `media*`, registar „ti", HR prvo pa EN, pa
  `flutter gen-l10n`):

  | Ključ | HR |
  |---|---|
  | `mediaPlaybackSpeed` | Brzina reprodukcije |
  | `mediaPlaybackSpeedSet` | Brzina: {rate}× |
  | `mediaBackgroundPlaybackTooltipOn` | Reprodukcija u pozadini je uključena |
  | `mediaBackgroundPlaybackTooltipOff` | Reprodukcija u pozadini je isključena |
  | `mediaBackgroundPlaybackToastOn` | Nastavit će svirati kad izađeš iz aplikacije |
  | `mediaBackgroundPlaybackToastOff` | Reprodukcija će stati kad izađeš iz aplikacije |
  | `mediaSeekUndo` | Natrag na {time} |
  | `mediaSeekUndoTooltip` | Poništi skok |

  Postojeći `mediaBackgroundPlaybackTitle`/`Subtitle` (za `/account`) ostaju
  netaknuti.

- **Definicija gotovog**: `flutter analyze` čist; widgeti se kompajliraju i
  imaju kratak widget test ili su barem instancirani u `flutter test` smoke-u;
  `flutter gen-l10n` prolazi bez upozorenja; nijedan ARB string nema ALL-CAPS
  ni izgubljene dijakritike.

---

### T3 — Ožičenje brzine, pozadine i Undo pilule u oba playera

- **Fajlovi**: `lib/widgets/episode_video.dart`, `lib/widgets/video_panel.dart`,
  `lib/screens/episode_screen.dart`, `lib/screens/episode_simple_screen.dart`,
  `lib/services/background_audio.dart`

- **Opis**:

  **`episode_video.dart`** — dodaj `SpeedCycleButton` i `BackgroundPlaybackButton`
  u `desktopBottomBar` i `mobileBottomBar`, lijevo od CC gumba. Isti popisi se
  koriste i za `fullscreen:` varijante teme → kontrole postoje i u fullscreenu
  besplatno. U `controls:` Stack dodaj `SeekUndoPill` (iznad
  `AdaptiveVideoControls`, ispod titlova) → pilula radi i u fullscreen ruti.
  Tipkovnička kratica za brzinu (`Shift+>` / `Shift+<`, YouTube konvencija) je
  nice-to-have i ne blokira task.

  **Oba ekrana** (`episode_screen.dart`, `episode_simple_screen.dart`):
  - Kreiraj `SeekUndo` uz `PlaybackIntent` u `_initVideo`, **subscribe prije**
    `openAndResume` — isti razlog kao za ostale subscribee, vidi komentar na
    `episode_simple_screen.dart:321-325` (media_kit streamovi su broadcast, ne
    replay).
  - `suppress()` neposredno prije: `openAndResume` (resume-seek pri otvaranju),
    chapter-tap seeka (`episode_simple_screen.dart:_seekTo:465` + ekvivalent u
    `episode_screen.dart`) — to je D2 — i prije samog Undo seeka (inače Undo
    ponudi Undo).
  - `dispose()`: `_seekUndo?.dispose()` uz postojeće.
  - Primijeni spremljenu brzinu odmah nakon `openAndResume`
    (`player.setRate(PlaybackSpeed.instance.rate)`) i pretplati se na promjene
    dok je ekran živ.
  - **Proslijedi stvarnu brzinu u obje media sesije**, inače lock-screen scrub
    bar drifta pri 1,5×:
    - web: `MediaSession.setPositionState(…, playbackRate: <trenutna brzina>)`
      (`episode_simple_screen.dart:340` + ekvivalent u `episode_screen.dart`);
    - native: `background_audio.dart` `_MediaKitHandler` →
      `playbackState.copyWith(speed: rate)`.

  **`video_panel.dart`** i **`_PlayerTab`** (u `episode_simple_screen.dart`) —
  dodaj oba gumba u postojeći red kontrola i `SeekUndoPill` iznad seek bara.
  **Ovo je jedina putanja za audio-only epizode**, gdje `EpisodeVideo` ne
  postoji.

- **Definicija gotovog**: na `/v/<id>` i `/m/<id>` brzina radi, mijenja se
  kružno i preživi reload i prelazak na drugu epizodu; oba gumba vidljiva u oba
  prikaza, u fullscreenu i na audio-only epizodi; povlačenje slidera nudi Undo
  koji vrati točno na prethodnu poziciju; **tap na poglavlje NE nudi Undo**;
  otvaranje epizode s resume pozicijom NE nudi Undo. `flutter analyze` čist.

---

### T4 — Rotacijski fullscreen

- **Fajlovi**: `lib/services/screen_orientation.dart` +
  `screen_orientation_web.dart` + `screen_orientation_stub.dart` (novi),
  `lib/widgets/rotated_fullscreen.dart` (novi),
  `lib/widgets/episode_video.dart`

- **Opis**: tri putanje, jer platforme daju tri razine mogućnosti. **Ne
  pokušavaj jedno rješenje za sve.**

  | Putanja | Kada | Kako |
  |---|---|---|
  | **A — pravi landscape (native)** | iOS/Android app | Postojeća media_kit ruta + `SystemChrome.setPreferredOrientations([landscapeLeft, landscapeRight])` u `_onEnterFullscreen` + `setEnabledSystemUIMode(immersiveSticky)`; na izlazu vrati `DeviceOrientation.values` i `edgeToEdge`. iOS poštuje app-forsiranu orijentaciju unatoč sistemskoj bravi rotacije — to je D3. |
  | **B — pravi landscape (web gdje ide)** | Android Chrome | Postojeća ruta + `screen.orientation.lock('landscape')` **nakon** `requestFullscreen`. |
  | **C — vizualna rotacija** | web bez Screen Orientation API-ja (iPhone Safari **i** iOS Chrome), i svaki uski portretni viewport gdje A/B padnu | **Naša** fullscreen ruta s `RotatedBox(quarterTurns: 1)` (90° u smjeru kazaljke) preko cijelog portretnog viewporta. |

  `screen_orientation.dart` — uvjetni import, gate na **`dart.library.js_interop`,
  ne `dart.library.html`** (inače puca `--wasm` build; poznata zamka). Izloži
  `bool get canLockOrientation`, `Future<bool> lockLandscape()`, `unlock()`.

  `rotated_fullscreen.dart` —
  `Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(… transitionDuration: Duration.zero …))`,
  sadržaj `RotatedBox(quarterTurns: 1)` → `EpisodeVideo` nad **istim**
  `Player`/`VideoController`.
  - **Zamka (web)**: naša ruta jednako re-parenta `<video>` element u DOM-u kao
    i media_kitova → browser to čita kao remove+insert i **pauzira** (CLAUDE.md,
    media_kit zamka #1). Iskoristi postojeći `_resumeAfterTransition(wasPlaying)`
    iz `episode_video.dart:121-131`, ne piši novi.
  - **PROVJERITI PRVO**: da `RotatedBox` ispravno rotira i hit-testing, pa
    kontrole i gestikulacija rade bez ručnog preračunavanja koordinata.
    Dokaži minimalnim probnim ekranom **prije** nego kreneš graditi ostalo; ako
    ne radi, javi orkestratoru umjesto da improviziraš.
  - Izlaz iz rotiranog fullscreena: gumb, sistemska Back tipka (`PopScope`) i
    Esc na webu.

  Gumb: zamijeni `MaterialFullscreenButton`/`MaterialDesktopFullscreenButton`
  vlastitim koji bira putanju A/B/C. **Desktop (širok viewport) mora ostati
  bit-za-bit na današnjem ponašanju** — ne diraj Esc-desync fix
  (`episode_video.dart:106-115`) ni speaker badge.

- **Definicija gotovog**: na uskom portretnom viewportu u Chromeu (desktop, uz
  device toolbar) tap na fullscreen daje rotiranu sliku preko cijelog viewporta
  s funkcionalnim kontrolama; na desktop širini ponašanje je nepromijenjeno;
  video se ne pauzira pri ulasku ni izlasku; `flutter analyze` čist. Provjera
  na stvarnom iPhoneu ide u T5.

---

### T5 — iOS istraga: pozadinska reprodukcija i Dynamic Island

- **Fajlovi**: `docs/ios-background-playback.md` (novi), po nalazu i
  `lib/services/media_session.dart` + `lib/screens/episode_*.dart`, `CLAUDE.md`

- **Opis**: **dijagnostika s izvještajem, ne unaprijed zadan popravak.** Ne
  izmišljaj zaključke — izmjeri. Traži korisnika uz stroj (signing, „Trust" na
  uređaju, fizički iPhone 15 Pro na kabelu).

  **Build/deploy**: `flutter devices` → `flutter run --release -d <udid>`, ili
  `flutter build ipa` + `xcrun devicectl device install app`. Ako vanjski disk
  nije montiran, koristi `xcodebuild -derivedDataPath build/ios_dd`.

  **Matrica koju treba popuniti** — za svaku ćeliju: svira li zvuk 60 s nakon
  odlaska u pozadinu, i što pokazuju Dynamic Island i lock screen.

  | | native iOS app | iOS Safari | iOS Chrome | PWA s home screena |
  |---|---|---|---|---|
  | zaključan zaslon | | | | |
  | druga aplikacija u prvom planu | | | | |
  | brzina 1,5× u pozadini | | | | |

  **Hipoteze, ovim redom:**
  1. **iOS Chrome jednostavno ne drži web audio u pozadini.** Ako native app i
     Safari rade a Chrome ne — to je ograničenje Chromeovog WKWebView hosta, ne
     naš bug. Isporuka je onda: zapis u `CLAUDE.md` + persistent „instaliraj
     app" traka na iOS Chromeu (traka, **ne modal** — Rule o nudgeovima).
  2. **Zastarjela Media Session.** Ako playback umre a `navigator.mediaSession`
     ostane registrirana, iOS i dalje drži stavku u Dynamic Islandu i svaki tap
     vraća u browser. **Ovo je popravljivo**: kad reprodukcija stvarno stane
     (ili je pref „u pozadini" isključen), pozovi `MediaSession.clear()` i
     `playbackState = 'none'`. Prvo izmjeri je li to stvarno slučaj.
  3. **PiP kao izlaz za iOS web** — ako pozadinski audio nije moguć, native
     Picture-in-Picture nad `<video>` elementom je jedini način da zvuk preživi
     izlazak iz browsera. **Samo procijeni trošak, ne implementiraj u ovom
     krugu.**

  **Što napisati korisniku bez uljepšavanja**: „tap na Dynamic Island otvara
  aplikaciju koja svira" je **namjerno ponašanje iOS-a** i ne može se isključiti
  dok god želimo pozadinski zvuk — to je ista sprega koja zvuk drži živim.
  Popravljivo je samo da ondje ne ostane *mrtva* stavka nakon što playback stane
  (hipoteza 2) i da u native appu tap vodi u našu aplikaciju umjesto u browser.

- **Definicija gotovog**: popunjena matrica u `docs/ios-background-playback.md`
  sa zaključcima po hipotezama, plus jedan konkretan popravak ako hipoteza 2
  padne na naš teren. `flutter analyze` čist.

---

## Ovisnosti

```
T1 ‖ T2          → paralelno, fajlovi su disjunktni
T1, T2  →  T3    → T3 troši oba (servise i widgete)
        T3 →  T4 → serijski: T4 dira lib/widgets/episode_video.dart, isti fajl kao T3
        T4 →  T5 → T5 provjerava T3 i T4 na stvarnom uređaju
```

**Zajednički fajlovi — izrijekom, ne slati istovremeno:**
- `lib/widgets/episode_video.dart` → T3 i T4. **Serijski.**
- `lib/l10n/app_hr.arb` / `app_en.arb` → **isključivo T2**. Nijedan drugi task
  ne dira i18n; ako T3/T4 zatrebaju novi string, traži ga od orkestratora kao
  dopunu T2, ne diraj ARB sam.
- `lib/screens/episode_screen.dart`, `episode_simple_screen.dart` → T3, a
  potencijalno i T5 (hipoteza 2). **Serijski.**

## Rizik

**srednji.** Ne dira auth, plaćanja/pinka, Supabase shemu, `web/_worker.js` ni
RevenueCat. Ali dira najosjetljiviji dio UX-a (playback putanje s tri postojeće
dokumentirane web zamke) i uvodi prvu upotrebu `SystemChrome` u repou. T4 je
najrizičniji pojedinačni task jer zaobilazi media_kitovu fullscreen rutu — ako
`RotatedBox` hit-testing ne prođe provjeru, task se zaustavlja i vraća
orkestratoru, ne improvizira se.

## Verifikacija

- `flutter analyze` čist **nakon svakog taska**, ne samo na kraju.
- `flutter test test/seek_undo_test.dart test/playback_intent_test.dart` prolazi.
- **Nisu regresije** (padaju i na čistom `main`-u): `test/widget_test.dart`
  (HttpClient smoke) i `home_feed_test` (datum-ovisan). Prije nego prijaviš
  regresiju, provjeri stashem.
- Ručna provjera prije verdikta reviewera:
  1. `/v/<id>` u Chromeu na desktopu — brzina se mijenja kružno i preživi
     reload; oba gumba rade; fullscreen se ponaša **kao prije**.
  2. `/m/<id>` — isto, plus Undo pilula na scrub, **bez** pilule na tap
     poglavlja.
  3. Uski portretni viewport (device toolbar) — rotacijski fullscreen.
  4. Jedna **audio-only** epizoda — gumbi i Undo postoje iako `EpisodeVideo` ne
     postoji.
- Deploy **ne radi dev ni reviewer** — pripada orkestratoru, i to tek nakon
  korisnikove potvrde.

## Van opsega

- Implementacija Picture-in-Picture (T5 ga samo procjenjuje).
- Bilo kakva promjena YouTube embed moda (`youtube_embed.dart`) — ondje brzinu i
  fullscreen kontrolira YouTube iframe, ne mi.
- TV player (`lib/screens/tv/`) — D-pad model i libmpv `hwdec=no` ostaju
  netaknuti.
- Dual-encode H.264 pipeline (postojeći TODO, nema veze s ovim krugom).
- Deploy i bump verzije.
