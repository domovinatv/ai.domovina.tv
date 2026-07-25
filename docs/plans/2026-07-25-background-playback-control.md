# Kontrola reprodukcije u pozadini + prestanak pregaživanja korisnikove pauze

## Cilj

Korisnikova Pauza postaje neopoziva: ništa je više ne poništava — ni zatvaranje
video drawera swipe-rightom, ni odlazak aplikacije u pozadinu. Uz to korisnik
dobiva prekidač **„Reprodukcija u pozadini"** u `/account` (default: uključeno)
koji određuje nastavlja li ono što svira raditi kad app/tab izgubi prvi plan.
Usput se zatvara rupa: `/m/` (jednostavni prikaz) na webu uopće nema Media
Session, pa nema ni lock-screen kontrola ni iOS Safari background audija.

Ugovor u jednoj rečenici, identičan na webu i nativeu:

> Dok je „Reprodukcija u pozadini" uključena, odlazak u pozadinu ne prekida ono
> što svira. Dok je isključena, reprodukcija se pauzira. Izričitu korisnikovu
> pauzu ne poništava ništa.

## Kontekst

### Zatečeno stanje — tri mjesta koja zovu `play()` bez korisnikova traženja

| # | Gdje | Okidač | Guard danas |
|---|---|---|---|
| A | `episode_screen.dart:1836-1853` i `:2223-2234` (dvije kopije, dva layouta) | zatvaranje endDrawera | stale snapshot → **puca** |
| B | `episode_screen.dart:664-690` + `episode_simple_screen.dart:244-257` | `AppLifecycleState.paused`/`hidden`, samo native | **nikakav** — bezuvjetni `play()` nakon 150 ms |
| C | `episode_video.dart:121-131` | ulaz/izlaz iz fullscreena (web DOM re-parent) | `wasPlaying` uhvaćen neposredno prije akcije → **korektan, NE dirati** |

**A je prijavljeni bug.** `_wasPlayingWhenDrawerOpened` se snima kad se drawer
*otvori* (`episode_screen.dart:1840`) i nikad se ne ažurira kad korisnik u
međuvremenu stisne Pause. Zato: player svira → snapshot `true` → Pause →
swipe-right → 120 ms kasnije kod vidi „nije playing, a bio je" → `play()`.

**B je šira ista greška**: na nativeu pauziraš pa stisneš home → app te sam
otpauzira u pozadini, bez ikakvog opt-outa.

### Zašto intent NE smije ići kroz naše gumbe

`episode_video.dart:276` i `:281` imaju `playAndPauseOnTap: true`; uz to
`MaterialDesktopPlayOrPauseButton` (`:247`) i tipkovničke kratice (`:194-221`)
zovu `player.playOrPause()` **interno i ne daju nam callback**. Omatanje naših
gumba (`video_panel.dart:366`, `episode_simple_screen.dart:479`) pokrilo bi
manjinu putanja. Jedini pouzdan izvor istine je `player.stream.playing`.

### Background reprodukcija danas

| | `/v/` detaljno | `/m/` jednostavno |
|---|---|---|
| native (`audio_service`) | ✅ `episode_screen.dart:866` | ✅ `episode_simple_screen.dart:379` |
| web (Media Session API) | ✅ `episode_screen.dart:878-899`, `:984` | ❌ **ne postoji** (fajl ne importa `media_session.dart`) |

`BackgroundAudio.init()` se zove jednom u `main.dart:70`; `attach()` po ekranu,
`detach()` u `dispose()`.

### Odluke koje su već pale (ne preispitivati)

1. Toggle živi **samo u `/account`**, ne u control baru playera.
2. Default je **uključeno** — bez regresije za postojeće slušatelje.
3. Web se ponaša **isto kao native**: isključeno → aktivno pauziramo kad tab
   ode u `hidden`.

## Taskovi

### T1 — `PlaybackIntent` servis + unit test

- **Fajlovi**:
  - `lib/services/playback_intent.dart` (novo)
  - `test/playback_intent_test.dart` (novo)
- **Opis**: mali servis koji odgovara na pitanje „želi li korisnik da ovo
  svira?", ožičen na `player.stream.playing` (jedini izvor koji hvata i
  media_kitove interne kontrole).

  API koji T3 i T4 očekuju — držati se doslovno:

  ```dart
  class PlaybackIntent {
    /// [playingStream] i [isPlayingNow] umjesto samog Playera → testabilno
    /// bez media_kita (u testu StreamController + zatvorena varijabla).
    PlaybackIntent({
      required Stream<bool> playingStream,
      required bool Function() isPlayingNow,
      bool initiallyWants = true,
    });

    /// True dok korisnik nije sam pauzirao.
    bool get wantsPlayback;

    /// Otvori prozor tolerancije NEPOSREDNO prije poznate framework
    /// tranzicije (zatvaranje drawera, odlazak u pozadinu). Unutar prozora
    /// `playing:false` NE gasi namjeru — jer ga nije izazvao korisnik.
    void suppress({Duration window = const Duration(milliseconds: 800)});

    /// Namjera postoji, ali player stvarno ne svira → treba ga vratiti.
    bool get shouldResume;

    void dispose();
  }
  ```

  Semantika: svaki prijelaz iz `playingStream` ažurira `wantsPlayback`
  (`true` → `true`, `false` → `false`), OSIM kad je `suppress()` prozor još
  otvoren — tada se `false` ignorira, a `true` se prihvaća.
- **Definicija gotovog**: `test/playback_intent_test.dart` prolazi i pokriva
  najmanje ova četiri slučaja:
  1. korisnikova pauza bez prozora → `wantsPlayback == false`,
     `shouldResume == false`;
  2. `suppress()` pa pauza unutar prozora → `wantsPlayback` ostaje `true`,
     `shouldResume == true` (uz `isPlayingNow() == false`);
  3. pauza NAKON isteka prozora → `wantsPlayback == false`;
  4. korisnik pauzira, pa `suppress()`, pa framework pauza → i dalje
     `wantsPlayback == false` (prozor ne uskrsava ugašenu namjeru).
  `flutter analyze` čist.

### T2 — Pref „Reprodukcija u pozadini" + prekidač u `/account`

- **Fajlovi**:
  - `lib/services/background_playback.dart` (novo)
  - `lib/l10n/app_hr.arb`
  - `lib/l10n/app_en.arb`
  - `lib/screens/account/account_screen.dart`
- **Opis**:
  1. Servis po uzoru na `lib/services/theme_mode_service.dart` — `ChangeNotifier`
     singleton, `init()` iz `main.dart` prije `runApp()`, `bool get enabled`
     (default `true` dok se ne učita), `Future<void> setEnabled(bool)`.
     Perzistencija: `kIsWeb` → `local_prefs.dart` (`getLocalStorageString` /
     `setLocalStorageString`), inače `SharedPreferences`. Ključ:
     `background_playback`.
     **NAPOMENA**: `main.dart` NIJE u tvom popisu fajlova — poziv
     `BackgroundPlayback.instance.init()` u `main()` dodaje orkestrator/dev
     nakon što oba kruga prođu, ILI se traži izričito odobrenje. Servis mora
     raditi ispravno i bez tog poziva (lazy read pri prvom `enabled` pristupu),
     pa ovo ne blokira.
  2. Nova sekcija u `account_screen.dart` — `_sectionLabel(theme, l.authSectionPlayback)`
     + `_card(...)` sa `SwitchListTile`. Umetnuti **iznad** sekcije Jezik
     (`account_screen.dart:194-195`). Prati `ChangeNotifier` (npr.
     `ListenableBuilder`) da se prekidač osvježi bez ručnog `setState`.
  3. Novi ARB ključevi (PRVO `app_hr.arb` s `@key` metapodacima, pa
     `app_en.arb`, pa `flutter gen-l10n`):
     - `authSectionPlayback` — naslov sekcije („REPRODUKCIJA")
     - `mediaBackgroundPlaybackTitle` — „Reprodukcija u pozadini"
     - `mediaBackgroundPlaybackSubtitle` — objašnjenje u jednoj rečenici,
       neformalno „ti", npr. „Nastavi slušati kad zaključaš zaslon ili
       prijeđeš u drugu aplikaciju."
     Prefiks `media*` jer je postavka o reprodukciji; `authSection*` samo za
     naslov sekcije, radi konzistencije s ostalim sekcijama tog ekrana.
- **Definicija gotovog**: `/account` prikazuje prekidač iznad sekcije Jezik;
  promjena preživi reload (web) i restart (native); HR i EN tekstovi ispravni;
  `flutter analyze` i `flutter gen-l10n` čisti.

### T3 — Ožiči `/v/` (detaljni prikaz)

- **Fajlovi**: `lib/screens/episode_screen.dart`
- **Ovisi o**: T1 i T2 (importa oba servisa) — NE počinjati prije nego su
  spojeni.
- **Opis**:
  1. Instanciraj `PlaybackIntent` u `_initVideo()` odmah nakon što player
     postoji (`:819-841`), otpusti ga u `dispose()` (`:649-661`).
  2. **Slučaj A — drawer** (`onEndDrawerChanged`, obje kopije: `:1836-1853` i
     `:2223-2234`). Zamijeni stale snapshot `_wasPlayingWhenDrawerOpened`:
     na `isOpen == false` pozovi `intent.suppress()`, pa nakon postojećih
     120 ms resumiraj samo ako `intent.shouldResume`. Polje
     `_wasPlayingWhenDrawerOpened` (`:471`, `:1840`, `:2225`) obriši —
     `PlaybackIntent` ga zamjenjuje. Grana `isOpen == true` više ne treba
     ništa raditi.
     **PROVJERITI prvo**: fira li `onEndDrawerChanged(false)` na *početku*
     zatvaranja, prije disposea `Video` widgeta u draweru. Postojeći 120 ms
     delay to sugerira. Ako fira tek nakon disposea, `suppress()` stiže
     prekasno — tada prozor treba otvoriti na početku gesture (vidi fallback
     u „Rizik").
  3. **Slučaj B — lifecycle** (`didChangeAppLifecycleState`, `:664-690`).
     Nova logika, i za web i za native (makni `kIsWeb` early-return
     asimetriju, ali zadrži postojeće ponašanje endDrawera na `paused`):
     - na `paused`/`hidden`: `intent.suppress()`;
       - ako `!intent.wantsPlayback` → ne radi ništa (korisnik je pauzirao);
       - inače ako `BackgroundPlayback.instance.enabled` → zadrži postojeći
         150 ms `play()` **samo na nativeu** (kontra SurfaceView auto-pauze;
         web to ne treba, browser sam drži audio);
       - inače (pref isključen) → `_player?.pause()`.
     - `resumed` grana (reopen endDrawera, `:682-689`) ostaje kakva jest.
  4. Ne dirati `episode_video.dart` (slučaj C je korektan) ni `openAndResume`.
- **Definicija gotovog**: na `/v/<id>` na mobitelu — Pauza pa swipe-right
  zatvaranje drawera NE pokreće reprodukciju; swipe-right dok svira NE prekida
  zvuk (regresijski test postojećeg ponašanja). `flutter analyze` čist.

### T4 — Ožiči `/m/` (jednostavni prikaz) + Media Session na webu

- **Fajlovi**: `lib/screens/episode_simple_screen.dart`
- **Ovisi o**: T1 i T2 — NE počinjati prije nego su spojeni.
- **Opis**:
  1. `PlaybackIntent` instanciraj u `_initVideo()` (`:297-390`), otpusti u
     `dispose()` (`:232-241`).
  2. **Slučaj B — lifecycle** (`:244-257`): ista logika kao T3 korak 3. Ovaj
     ekran nema drawer, pa slučaja A nema.
  3. **Media Session na webu** — presilkaj obrazac iz
     `episode_screen.dart:878-899` i `:984-987`:
     - import `../services/media_session.dart`;
     - u `_initVideo()`, uz postojeći `BackgroundAudio.instance.attach(...)`
       (`:379-385`), dodaj `MediaSession.attachMetadata(...)` +
       `setActionHandlers(...)` + `player.stream.playing` → `setPlaybackState`;
     - u postojećem `sec != _lastUrlSyncedSec` gateu (`:311-328`) dodaj
       `MediaSession.setPositionState(...)` — isti throttle;
     - `MediaSession.clear()` u `dispose()`.
     Artwork: `_audioArtUrl` / `squareUrl` je već razriješen (`:366-370`),
     koristi `squareUrl ?? thumbUrl` kao na `/v/`.
- **Definicija gotovog**: na `/m/<id>` u iOS Safariju lock screen pokazuje
  naslov/kanal/artwork i play/pause radi; Pauza pa prelazak u drugu aplikaciju
  NE pokreće reprodukciju. `flutter analyze` čist.

## Ovisnosti

- `T1 ‖ T2` — prvi krug, potpuno disjunktni fajlovi.
- `T3 ‖ T4` — drugi krug, disjunktni međusobno, ali **oba ovise o spojenim T1 i
  T2** (importaju `playback_intent.dart` i `background_playback.dart`). Ne
  dispatchati dok prvi krug nije prošao review i commit.
- `lib/l10n/app_hr.arb` / `app_en.arb` dira **isključivo T2**.
- `lib/main.dart` ne dira **nitko** u ovom planu (vidi napomenu u T2).

## Rizik

`srednji`.

Ne dira auth, plaćanja/pinka, Supabase shemu, `web/_worker.js` ni deploy
putanju — ali mijenja jezgru reprodukcije na oba glavna ekrana, a to je
funkcija zbog koje korisnici dolaze.

Dvije nepoznanice označene kao PROVJERITI, obje s fallbackom:

1. **Redoslijed drawer callbacka vs. dispose `Video` widgeta** (T3 korak 2).
   Ako `suppress()` stigne prekasno, framework pauza pogasi namjeru prije nego
   je prozor otvoren. Fallback: prozor otvoriti već na `isOpen == false` prije
   ikakvog `await`/`Future.delayed`, a ako ni to ne pomogne — `PlaybackIntent`
   proširiti `lastPauseAt` timestampom pa `suppress()` retroaktivno oprašta
   pauzu mlađu od ~200 ms.
2. **Redoslijed `didChangeAppLifecycleState(paused)` vs. media_kitova
   SurfaceView auto-pauza na Androidu** (T3/T4 korak 3). Postojeći kod to
   implicitno pretpostavlja (150 ms delay) ali nitko nije izmjerio. Isti
   `lastPauseAt` fallback rješava i ovaj slučaj — ako dev posumnja na race,
   neka ga ugradi u T1 API odmah i javi orkestratoru da su T3/T4 ovisni o
   proširenju.

## Verifikacija

`flutter analyze` mora biti čist nakon svakog taska.

`flutter test test/playback_intent_test.dart` mora prolaziti (T1).

**NAPOMENA za reviewera**: `test/widget_test.dart` (HttpClient smoke) i
`test/home_feed_test.dart` (datum-ovisan) padaju i na čistom `main`-u — to NISU
regresije ovog plana.

Ručna matrica (mobitel; `/v/<id>` i `/m/<id>`, oba jezika nebitna):

| Polazno | Radnja | Očekivano |
|---|---|---|
| svira | swipe-right zatvori drawer (`/v/`) | i dalje svira |
| **pauzirano** | swipe-right zatvori drawer (`/v/`) | **ostaje pauzirano** |
| svira, pref ON | home / zaključan zaslon | i dalje svira, lock screen kontrole rade |
| **pauzirano**, pref ON | home / zaključan zaslon | **ostaje pauzirano** |
| svira, pref OFF | home / zaključan zaslon | pauzira se |
| svira, pref OFF (web) | prebacivanje taba | pauzira se |
| svira | ulaz/izlaz iz fullscreena | i dalje svira (slučaj C, regresija) |

Plus: `/m/` na iOS Safariju — lock screen pokazuje naslov, kanal i artwork,
play/pause s lock screena radi.

## Van opsega

- **Mini-player** — reprodukcija koja preživi izlazak s ekrana epizode.
  `BackgroundAudio.detach()` je u `dispose()` (`episode_screen.dart:657`,
  `episode_simple_screen.dart:239`) i tako ostaje.
- **Autoplay pri otvaranju epizode** — `openAndResume` (`player_resume.dart:40`)
  uvijek pokreće reprodukciju. Otvaranje epizode je namjera slušanja; toggle na
  to ne utječe. Zasebna odluka za budući krug.
- **`lib/widgets/episode_video.dart`** — slučaj C već hvata `wasPlaying`
  neposredno prije akcije i korektan je. Ne dirati (drži diff disjunktnim).
- **Android TV ekrani** (`lib/screens/tv/*`) — TV nema pojam „pozadine" u ovom
  smislu; njihovi `play()` pozivi ostaju kakvi jesu.
- **`lib/main.dart`** — poziv `BackgroundPlayback.instance.init()` namjerno je
  izvan svih taskova da se devovi ne sudare na dijeljenom fajlu.
