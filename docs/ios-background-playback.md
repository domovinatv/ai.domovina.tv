# iOS pozadinska reprodukcija i Dynamic Island — istraga

**Status: PRIPREMLJENO, ČEKA PROMATRAČA.** Analiza koda je gotova, build je na
uređaju, mjerni instrumenti rade. Matrica je i dalje prazna jer svaka njena
ćelija traži ljudsku radnju (zaključati zaslon, prebaciti app) i ljudsko oko
(Dynamic Island, lock screen) — ništa od toga se ne da pročitati iz koda ni s
kabela. Nijedna ćelija nije popunjena pretpostavkom: ako piše „čeka
promatrača", to znači da to nitko nije izmjerio.

Task: T5 iz `docs/plans/2026-07-27-playback-overhaul.md`.
Datum analize koda: 2026-07-27 (nakon T1–T4).
Datum pripreme mjerenja: 2026-07-27.

---

## 1. Okruženje

### 1.1 Uređaji (`flutter devices`, 2026-07-27)

| Uređaj | ID | Platforma |
|---|---|---|
| iPhone MS 15 Pro | `00008130-00184D0111FA001C` | iOS 26.5.2 (23F84) |
| moto g86 5G | `ZY32M4Q2GJ` | Android 16 (API 36) |
| macOS | `macos` | darwin-arm64 26.5.1 |
| Chrome | `chrome` | 150.0.7871.184 |

iPad (10th Yellow) se javio samo kao neuspješan wireless probe — nije spojen.

### 1.2 Što je stvarno napravljeno (izmjereno, ne planirano)

**Native build je na uređaju.** Korisnik je potvrdio „Trust", signing prolazi
automatski (`DEVELOPMENT_TEAM = 6SCK58757K`, `CODE_SIGN_STYLE = Automatic`):

```bash
flutter build ios --release \
  --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=… --dart-define=MEILI_URL=…
# → build/ios/iphoneos/Runner.app (62,9 MB), 82,8 s
xcrun devicectl device install app --device 00008130-00184D0111FA001C build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device … --terminate-existing ai.domovina
```

`-derivedDataPath build/ios_dd` **nije trebao**: Xcode DerivedData pokazuje na
`/Volumes/DOMOVINA2TB/xcode_temp_files/DerivedData/`, a taj je disk montiran.
Ako sljedeći put nije, override iz plana i dalje vrijedi.

Instalirani build je **v2.0.117 (+139), zatečeni HEAD `01e2d2e`** — dakle sadrži
T1–T4, a popravak iz §4.3 **nije** primijenjen. To je namjerno: matrica se mjeri
na zatečenom stanju.

**Statička provjera native strane** — `UIBackgroundModes = ["audio"]` u
`ios/Runner/Info.plist` je prisutan, `audio_service` se inicijalizira u
`BackgroundAudio.init()`. Preduvjeti za pozadinski zvuk postoje; drži li ih iOS
stvarno, mjeri matrica.

### 1.3 Mjerni instrumenti koji rade

**Device log** (potvrđeno — hvata naše `log()` linije iz release builda):

```bash
idevicesyslog -u 00008130-00184D0111FA001C -m "DOMOVINA"
# bez -m: cijeli syslog, korisno za mediaserverd/nowplaying tragove
```

Primjer uhvaćenog izlaza:
`Runner(Flutter)[6647] <Notice>: flutter: [DOMOVINA v2.0.117] main() start`.

`log stream --device-udid …` **ne radi** na macOS 26 (opcija uklonjena) —
`idevicesyslog` (homebrew) je zamjena.

**Prebacivanje u pozadinu se da skriptirati** za ćeliju „druga aplikacija u
prvom planu": `xcrun devicectl device process launch --device … com.apple.Preferences`
digne Postavke u prvi plan i time našu aplikaciju gurne u pozadinu. Zaključavanje
zaslona se **ne** da skriptirati.

**Snimka zaslona se NE da uhvatiti.** `idevicescreenshot` na iOS-u 26 javlja
„Could not start screenshotr service" — CoreDevice je tu uslugu maknuo s
lockdownd-a. Posljedica za cijeli protokol: **što se vidi na zaslonu može
potvrditi samo čovjek**, nema programatske provjere. Vidi i §7.1.

### 1.4 Web putanje — tri različita okruženja, ne miješati ih

| Okruženje | URL | Kod | Siguran kontekst | SW |
|---|---|---|---|---|
| **produkcija** | `https://domovina.ai` | **pre-T1** | da | da |
| **LAN dev server** | `http://192.168.1.102:5173` | T1–T4 | **ne** | **ne** |
| **diag stranica** | `http://192.168.1.102:5174` | — | ne | ne |

Produkcija **nema T1–T4**, iako `version.json` prijavljuje isti `2.0.117` kao
lokalni repo (zadnji deploy `2f45f0c` prethodi T1–T4, a taskovi ne bumpaju
verziju). Dokaz nije verzija nego sadržaj bundlea: `curl https://domovina.ai/main.dart.js`
**ne sadrži** string `Brzina reprodukcije` (T2), lokalni `build/web/main.dart.js`
ga sadrži. **Verzija ovdje ne razlikuje buildove — ne oslanjati se na nju.**

LAN server (per uputi: **bez deploya**):

```bash
flutter run -d web-server --release --web-hostname 0.0.0.0 --web-port 5173 \
  --dart-define=…
```

Deep rute rade (`/m/<id>`, `/v/<id>` vraćaju 200 — SPA fallback je uključen).

### 1.5 Ograničenja LAN servera — izmjerena, ne pretpostavljena

Provjereno u Chromeu nad `http://192.168.1.102:5173`:

```json
{"isSecureContext": false, "hasMediaSession": true, "hasServiceWorker": false}
```

| Ograničenje | Status | Posljedica za matricu |
|---|---|---|
| **Service Worker** | **nedostupan** (dokazano) | Cijeli SW sloj iz `web/index.html` otpada. Ono što memo „web background audio" pripisuje sprezi Media Session + SW/PWA ne može se reproducirati. |
| **Media Session** | u Chromeu **postoji** i na nesigurnom origin-u; za WebKit **neizmjereno** | Ako iOS Safari gate-a po sigurnom kontekstu, LAN mjerenje weba mjeri „nema sesije", ne naš kod. **Prvi korak protokola to razrješava.** |
| **PWA install** | „Dodaj na početni zaslon" na iOS-u vjerojatno napravi ikonu (manifest se servira), ali **bez SW-a to nije naša PWA** | Ćelija „PWA" nad LAN-om **nije** valjana zamjena za produkcijsku PWA. Označiti kao indikativno. |
| **Renderer** | LAN server servira **dart2js**, produkcija servira **wasm** (`main.dart.wasm`) s JS fallbackom | Različita putanja izvođenja; za audio nije očekivano bitno, ali nije isto. |

**Zaključak koji iz ovoga slijedi:** LAN server je dobar za ono što traži
**T1–T4 kod** (gumb za brzinu, Undo pilula, rotacijski fullscreen), a loš za
ono što traži **sigurni kontekst** (Media Session + SW = pozadinski zvuk).
Zato je matrica dolje podijeljena po okruženju, a ne slijepo mjerena na jednom.

---

## 2. Matrica — što treba izmjeriti

Za svaku ćeliju bilježimo tri stvari:

- **A** — svira li zvuk **60 s** nakon odlaska u pozadinu (štoperica, ne dojam);
- **DI** — što pokazuje Dynamic Island (ništa / živa stavka / mrtva stavka) i
  kamo vodi tap;
- **LS** — što pokazuje lock screen (naslov, izvođač, artwork, scrub bar) i
  rade li play/pause/±10 s.

| | native iOS app | iOS Safari | iOS Chrome | PWA s home screena |
|---|---|---|---|---|
| **zaključan zaslon** | ⏳ čeka promatrača | ⏳ čeka promatrača (prod) | ⏳ čeka promatrača (prod) | ⏳ čeka promatrača (prod) |
| **druga aplikacija u prvom planu** | ⏳ čeka promatrača | ⏳ čeka promatrača (prod) | ⏳ čeka promatrača (prod) | ⏳ čeka promatrača (prod) |
| **brzina 1,5× u pozadini** | ⏳ čeka promatrača | 🚫 blokirano do deploya | 🚫 blokirano do deploya | 🚫 blokirano do deploya |

**Gdje se koja ćelija mjeri i zašto:**

- **native app** — na instaliranom buildu (§1.2). Sadrži T1–T4, pa i red
  brzine ide odmah.
- **web, redovi 1–2** — na **produkciji** `https://domovina.ai`, ne na LAN
  serveru. Produkcija je pre-T1, ali ta dva reda mjere **mehanizam držanja
  zvuka u pozadini (Media Session + SW)**, a T1–T4 ga nisu dirali: jedina
  izmjena u tom sloju je `setPositionState(playbackRate:)` iz T3, koja mijenja
  *prijavljenu brzinu*, ne to hoće li zvuk svirati. Mjerenje je zato valjano.
- **web, red brzine** — 🚫 **blokirano.** Traži istovremeno T3 kod **i** siguran
  kontekst, a to danas ne postoji nigdje: produkcija je sigurna ali bez T3, LAN
  ima T3 ali nije siguran (§1.5). Ovaj red se popunjava **nakon prvog deploya**;
  bilo koja brojka izmjerena prije toga ne bi bila mjerenje ovog koda.
  Rezultat kroz diag stranicu (§2.1, Blok F) je zamjena samo za pitanje „drži li browser
  audio uopće", ne za „prijavljuje li naš kod ispravnu brzinu".

### 2.1 Protokol za promatrača

Sve što slijedi traži čovjeka uz uređaj. Koraci su numerirani i namjerno
doslovni; za svaki treba **jedna rečenica odgovora**. Gdje nešto ne možeš ili
ne stigneš — napiši „preskočeno", to je uredan ishod, izmišljen podatak nije.

**Testne epizode** (provjereno da postoje na CDN-u, 2026-07-27):

| Uloga | ID | Što je | Trajanje |
|---|---|---|---|
| **glavna (video)** | `nOCD7LosCxc` | „Zašto ne idete moliti ispred tvornice oružja?", ima članak i `video_h264.mp4` | 44:08 |
| **audio-only** | `0475c583ce5` | „96: Plinky — Joe Fabisevich" (kanal `launched`), samo `audio.mp3` | 1:09:21 |

**Prije svake ćelije**: force-quit aplikacije/browsera (swipe up i baci
karticu), pa svježe otvaranje epizode. Uvijek `nOCD7LosCxc` osim gdje piše
drukčije. Provjeri da je „Reprodukcija u pozadini" **uključena** (default je
uključeno) osim u koraku P3.

---

#### Blok A — native aplikacija (ikona DOMOVINA.ai, već instalirana)

**A1.** Otvori aplikaciju, otvori epizodu `nOCD7LosCxc`, pusti reprodukciju i
pusti je da prijeđe 10 s.
**A2.** Pritisni Power tipku (zaključan zaslon). Štoperica **60 s**.
**A3.** Bez otključavanja odgovori:
  - **a)** svira li zvuk cijelih 60 s (da / ne / stao nakon ~N s)?
  - **b)** što piše na lock screenu — naslov, izvođač, slika, scrub bar?
  - **c)** rade li play/pause i ±10 s s lock screena?
  - **d)** što pokazuje Dynamic Island i kamo vodi tap na njega?
**A4.** Otključaj i vrati se u aplikaciju. Je li reprodukcija nastavila ondje
gdje je bila, ili je skočila/pauzirala?
**A5.** Ponovi A1, pa umjesto Power tipke swipe-up i otvori **Poruke**.
Štoperica 60 s. Odgovori na ista pitanja a)–d).
**A6.** Ponovi A1, ali prije prebacivanja u pozadinu tapni gumb brzine dok ne
piše **1,5×**. Pa zaključaj zaslon na 60 s. Uz a)–d) dodaj:
  - **e)** je li kroz tih 60 s prošlo ~90 s sadržaja (1,5 × 60) ili ~60 s?
  - **f)** slaže li se scrub bar na lock screenu s tim, ili zaostaje/žuri?
    (Zaostajanje = `setPositionState` ne dobiva pravu brzinu. T3 je to trebao
    riješiti; ovo je provjera je li stvarno riješeno.)
**A7.** Ponovi A1 na **audio-only** epizodi `0475c583ce5` i samo zaključaj
zaslon na 60 s: svira li, i pokazuje li lock screen naslov i sliku?

> Ako ti odgovara, javi kad kreneš s blokom A — mogu u istom trenutku pokrenuti
> `idevicesyslog` i uhvatiti što aplikacija prijavljuje, pa da uz tvoje
> opažanje ide i zapis s uređaja. Korak A5 (prebacivanje u drugu aplikaciju)
> mogu i skriptirati umjesto tebe.

#### Blok B — iOS Safari (produkcija)

**B1.** Safari → `https://domovina.ai/m/nOCD7LosCxc`, pusti reprodukciju, 10 s.
**B2.** Power tipka, štoperica 60 s → odgovori a)–d) kao u A3.
**B3.** Vrati se, pa ponovi s prebacivanjem u **Poruke** umjesto zaključavanja.

#### Blok C — iOS Chrome (produkcija)

**C1.** Chrome → `https://domovina.ai/m/nOCD7LosCxc`, pusti reprodukciju, 10 s.
**C2.** Power tipka, štoperica 60 s → a)–d).
**C3.** Vrati se, pa ponovi s prebacivanjem u **Poruke**.

> Ovo je odlučujuće za hipotezu 1 (§3): ako A i B daju „svira", a C „ne svira",
> to je ograničenje Chromeovog hosta, ne naš bug.

#### Blok D — PWA s home screena (produkcija)

**D1.** U Safariju na `https://domovina.ai` → Podijeli → **Dodaj na početni
zaslon**. Otvori ikonu (mora se otvoriti bez Safarijeve adresne trake).
**D2.** Otvori `nOCD7LosCxc`, pusti, 10 s, pa Power tipka, štoperica 60 s →
a)–d).
**D3.** Ponovi s prebacivanjem u **Poruke**.

#### Blok E — „mrtva stavka" (hipoteza 2, §4) — najvažniji blok

Ovo je jedini dio koji pada na naš teren, pa ga ne preskakati. Radi ga **u
native aplikaciji i u Safariju na produkciji** (dva prolaza).

**E1 (P1 — kraj epizode).** Otvori epizodu, skoči na ~10 s prije kraja i pusti
da završi. Kad zvuk stane:
  - ostaje li stavka u Dynamic Islandu / na lock screenu?
  - radi li tap na play na njoj, ili je „mrtva"?
**E2 (P1b — replay).** Odmah zatim pokreni istu epizodu ponovno iz aplikacije.
Vraća li se stavka s naslovom, slikom i ispravnim scrub barom, i rade li
lock-screen kontrole?
**E3 (P2 — navigacija).** U toku reprodukcije s `/v/<id>` idi na Početnu.
Nestane li stavka?
**E4 (P3 — pref isključen).** U `/account` **isključi** „Reprodukcija u
pozadini". Pusti epizodu, pa zaključaj zaslon.
  - staje li zvuk (mora stati — to je smisao prekidača)?
  - **ostaje li stavka u Dynamic Islandu unatoč tome?** (Analiza koda kaže da
    ostaje — §4.2 N3. Ovo je provjera te tvrdnje na uređaju.)
  - Nakon toga **vrati prekidač na uključeno.**
**E5 (N5 — prijelaz epizoda, usput).** Dok jedna epizoda svira, otvori drugu.
Pokazuje li lock screen novu epizodu, ili je stavka nestala/ostala na staroj?

#### Blok F — sposobnosti okoline (brzo, 3 × 30 s)

Otvori `http://192.168.1.102:5174` (Mac mora biti na istoj mreži) u **Safariju**,
pa u **Chromeu**, pa iz **PWA ikone** ako je dodana. Stranica ispiše tablicu —
prepiši (ili slikaj) prva tri retka: `isSecureContext`,
`navigator.mediaSession`, `serviceWorker API`.

**Zašto ovo:** razrješava jedino otvoreno pitanje iz §1.5 — gate-a li WebKit
Media Session po sigurnom kontekstu. Ako u Safariju piše `mediaSession: true`
i na nesigurnom origin-u, LAN server postaje upotrebljiv i za dio web mjerenja;
ako piše `false`, LAN putanja za web je mrtva i red brzine ostaje blokiran do
deploya, kako je i označen.

Ista stranica ima i gumb **Pusti** + mjerač: pustiš zvuk, odeš u pozadinu 60 s,
vratiš se i ona **sama ispiše** koliko je sekundi zvuka prošlo naspram
stvarnog vremena (npr. „SVIRA: 59,4 s zvuka / 60,2 s zida"). To je gruba, ali
objektivna provjera drži li browser web audio u pozadini — **bez** našeg koda,
pa razdvaja „browser ne može" od „naš kod ne valja".

#### Blok G — rotacijski fullscreen na stvarnom iPhoneu (dug iz T4)

T4 u planu izrijekom kaže: „Provjera na stvarnom iPhoneu ide u T5." Nije o
pozadinskom zvuku, ali traži isti uređaj u istoj sesiji, pa ide ovdje da se
korisnika ne zove dvaput.

**G1 (putanja A — native).** U aplikaciji, epizoda `nOCD7LosCxc`, **uključi
sistemsku bravu rotacije** (Control Center). Drži telefon u portretu i tapni
fullscreen. Očekivano po D3: slika ide u **pravi landscape unatoč bravi**.
  - Je li slika landscape preko cijelog zaslona?
  - Rade li kontrole (play/pause, seek, brzina, CC) i titlovi?
  - Je li se video **pauzirao** pri ulasku ili izlasku (ne smije)?
  - Izlaz: gumb i **swipe/Back gesta** — vraća li se uredno u portret?
**G2 (putanja C — web, vizualna rotacija).** Safari →
`http://192.168.1.102:5173/m/nOCD7LosCxc` (LAN server, jer produkcija nema T4).
Isti tapni-fullscreen test u portretu s bravom rotacije.
  - Je li slika rotirana preko cijelog viewporta?
  - **Rade li kontrole na dodir** — tapni play/pause i povuci seek bar. Ovo je
    hit-testing provjera `RotatedBox`-a: ako tapovi promašuju (pogađaju krivo
    mjesto), to je nalaz koji odmah javi.
  - Pauzira li se video pri ulasku/izlasku?
**G3.** Isto kao G2, ali u **iOS Chromeu** — po planu i Chrome na iOS-u nema
Screen Orientation API pa mora pasti na istu vizualnu rotaciju.

### 2.2 Što ide natrag devu

Za svaku ćeliju: **A** (svira / ne svira / stao nakon N s), **DI** (ništa /
živa stavka / mrtva stavka + kamo vodi tap), **LS** (što piše i rade li
kontrole). Slobodno u telegrafskom stilu — matricu i zaključke po hipotezama
popunjava dev.

### 2.3 Zasebna provjera „mrtve stavke" (hipoteza 2) — obrazloženje

Ovo nije u matrici jer nije o pozadini, nego o čišćenju sesije. **Izvedbeni
oblik je Blok E gore** (E1–E5); ovdje stoji *zašto* svaki korak postoji, da se
pri čitanju rezultata zna što je bio ulog. Tri koraka, svaki na Safariju i u
PWA:

- **P1** — pusti epizodu do kraja (ili skoči 10 s prije kraja i pusti da
  završi). Nakon što zvuk stane: ostaje li stavka u Dynamic Islandu / na lock
  screenu? Radi li tap na play?
  **P1b (replay)** — odmah zatim pokreni istu epizodu ponovno iz aplikacije.
  Vraća li se stavka s naslovom, artworkom i ispravnim scrub barom, i rade li
  lock-screen kontrole? Ovo je regresijska provjera za popravak iz §4.3: on na
  `completed` zove `clear()`, pa replay ostaje bez metadata i handlera sve dok
  ih zajednička metoda za re-registraciju ne vrati.
- **P2** — u toku reprodukcije navigiraj s `/v/<id>` na Početnu (`context.go`).
  Nestane li stavka? (Ovdje se zove `MediaSession.clear()` — vidi §4.)
- **P3** — isključi „Reprodukcija u pozadini" u `/account`, pusti epizodu, pa
  zaključaj zaslon. Zvuk mora stati (to je smisao prekidača) — ali ostaje li
  stavka u Dynamic Islandu?

---

## 3. Hipoteza 1 — iOS Chrome ne drži web audio u pozadini

**Status: neizmjereno.** Ovo je hipoteza o tuđem softveru i nema je smisla
razrješavati čitanjem našeg koda.

Što je poznato bez uređaja: svi browseri na iOS-u su WKWebView nad WebKitom,
ali svaki host sam odlučuje što radi s medijem kad izgubi prvi plan, i
`navigator.mediaSession` ne mora biti izložen jednako. Naša detekcija to već
razlikuje — `isIosSafari()` u `lib/services/mobile_web_detect_web.dart:31`
gleda `CriOS|FxiOS|EdgiOS|OPiOS|GSA` u userAgentu.

**Kriterij razrješenja:** ako u matrici native app i Safari daju A = da, a
Chrome A = ne → hipoteza potvrđena, nije naš bug.

**Isporuka u tom slučaju** (ne prije potvrde): zapis u `CLAUDE.md` +
persistent traka „instaliraj aplikaciju" na iOS Chromeu. Traka, **ne modal** —
Rule o nudgeovima iz `CLAUDE.md`. Ulazna točka postoji: `mobileWebOs() ==
'ios' && !isIosSafari() && !isStandalonePwa()`. Apple Smart App Banner
(`apple-itunes-app` meta, `web/index.html:46`) pokriva samo Safari, pa se
poruke ne bi preklapale.

---

## 4. Hipoteza 2 — zastarjela Media Session

**Ovo je jedina hipoteza koja pada na naš teren, i analiza koda je pronašla
konkretan nedostatak i prije mjerenja.** Mjerenje i dalje treba — da znamo je
li nedostatak *uzrok* onoga što je korisnik vidio, a ne samo defekt po
specifikaciji.

### 4.1 Gdje se `clear()` zove danas

| Mjesto | Fajl |
|---|---|
| `dispose()` detaljnog ekrana | `lib/screens/episode_screen.dart:688` |
| `dispose()` jednostavnog ekrana | `lib/screens/episode_simple_screen.dart:273` |

I to je sve. `MediaSession.clear()` se ne zove nigdje drugdje u repou.

### 4.2 Nalazi

**N1 — `clear()` ne gasi `playbackState`.**
`clearImpl()` (`lib/services/media_session_web.dart:119-127`) postavlja
`metadata = null` i odjavljuje svih pet action handlera, ali **nikad ne
postavlja `playbackState = 'none'`**. Vrijednost ostaje ono što je zadnje
upisao `setPlaybackStateImpl` — u praksi `'paused'`.

Po specifikaciji je `playbackState` upravo taj signal („nema aktivne sesije").
Kombinacija koja ostaje nakon `clear()` je najgora moguća: OS-u i dalje piše
da sesija postoji i da je pauzirana, a svi handleri su `null` — dakle stavka
je vidljiva, a tap na play ne radi ništa. To je doslovno opis „mrtve stavke"
iz hipoteze.

**N2 — API ne zna izraziti `'none'`.**
`MediaSession.setPlaybackState(bool)` (`lib/services/media_session.dart:33`)
prima `bool` → može poslati samo `'playing'` i `'paused'`. Popravak N1 traži i
proširenje ovog potpisa (ili zaseban `setInactive()`).

**N3 — nedostaju tri poziva `clear()`.**

- **Kraj reprodukcije.** `player.stream.completed` se **ne sluša nigdje u
  aplikaciji** (provjereno grepom). Epizoda završi, zvuk stane, sesija ostane
  registrirana s metadatom → stavka preživi playback. Kandidat za P1 (§2.3) — mjeri se u Bloku E1.
- **Pref „u pozadini" isključen + odlazak u pozadinu.**
  `didChangeAppLifecycleState` (`episode_screen.dart:708-714`,
  `episode_simple_screen.dart:293-296`) pozove `_player?.pause()` i vrati se.
  Sesija ostaje. Korisnik je izričito rekao „ne sviraj u pozadini", a i dalje
  dobije stavku u Dynamic Islandu. Kandidat za P3 (§2.3) — mjeri se u Bloku E4.
- **Neuspjelo otvaranje medija.** `_initVideo` catch blok — ovdje **nema
  problema**, jer se `attachMetadata` zove tek nakon uspješnog `openAndResume`,
  pa nema što čistiti. Navedeno samo da se ne provjerava dvaput.

**N4 — native putanja je već ispravna, web zaostaje.**
`_MediaKitHandler.detachPlayer()` (`lib/services/background_audio.dart:142-156`)
postavlja `mediaItem = null` **i** `AudioProcessingState.idle` — dakle native
uredno raspušta sesiju. Web ekvivalent je nepotpun. Popravak je poravnavanje
weba na ono što native već radi, ne novi mehanizam.

**N5 — redoslijed pri prijelazu epizoda (za provjeru, vjerojatno bezopasno).**
`navigator.mediaSession` je procesno globalan, a oba ekrana pišu po njemu.
Prijelaz s epizode na epizodu ide preko `context.go` (npr.
`episode_screen.dart:1727`), rute imaju ključ po `videoId`
(`lib/router/app_router.dart:179`, `:317`) → stari ekran se dispose-a, novi
gradi. Teoretski rizik: `clear()` starog ekrana pregazi metadata novog
(suprotan kvar — živa reprodukcija bez sesije). U praksi vrlo malo vjerojatno
jer novi ekran zove `attachMetadata` tek nakon `await openAndResume` (sekunde
kasnije), a `dispose()` ide u istom frameu. **Provjeriti usput** dok je uređaj
na stolu; ne graditi ništa preventivno.

### 4.3 Predloženi popravak — NIJE PRIMIJENJEN

Namjerno nije primijenjen: matrica se mora izmjeriti na **zatečenom** buildu,
inače više ne možemo utvrditi je li N1/N3 stvarno uzrok onoga što je korisnik
prijavio. Popravak ide odmah nakon mjerenja, u istom tasku.

Tri izmjene, sve u web putanji:

```dart
// lib/services/media_session_web.dart — clearImpl()
void clearImpl() {
  if (!_supported) return;
  try {
    _nav.mediaSession!.metadata = null;
    // 'none' je jedini signal OS-u da sesije više nema. Bez njega iOS drži
    // stavku u Dynamic Islandu, a handleri su već odjavljeni → mrtav tap.
    _nav.mediaSession!.playbackState = 'none';
    for (final a in const ['play', 'pause', 'seekto', 'seekbackward', 'seekforward']) {
      _nav.mediaSession!.setActionHandler(a, null);
    }
  } catch (_) {}
}
```

```dart
// lib/screens/episode_*.dart — u _initVideo, uz ostale subscribee.
// Subscription se sprema i cancela u dispose(), po obrascu `_positionSub` —
// ostali subscribei to već rade. (Benigno je i bez toga jer player.dispose()
// zatvori streamove, ali ne odstupamo od obrasca.)
_completedSub = player.stream.completed.listen((done) {
  if (!mounted || !done) return;
  MediaSession.clear();   // epizoda je gotova; stavka nema što raditi ondje
});
```

```dart
// lib/screens/episode_*.dart — didChangeAppLifecycleState,
// grana `!BackgroundPlayback.instance.enabled`
_player?.pause();
MediaSession.clear();     // pref kaže tišina → i sesija odlazi
return;
```

Za treću izmjenu treba i put natrag: kad se ekran vrati u prvi plan
(`AppLifecycleState.resumed`) sesiju treba ponovno registrirati, inače
korisnik ostane bez lock-screen kontrola do reloada. To je jedini dio
popravka koji nije trivijalan i traži izdvajanje `attachMetadata` +
`setActionHandlers` iz `_initVideo` u zasebnu metodu koju obje putanje zovu.

**Dva ekrana tu nisu simetrična** (nalaz reviewera r5, provjereno u kodu):

- `episode_simple_screen.dart:281` — handler ima early-return za sve osim
  `paused`/`hidden`, dakle `resumed` grana **ne postoji**. Re-registracija
  ondje znači pisati novu granu, ne dopunjavati postojeću.
- `episode_screen.dart:730` — `resumed` grana postoji, ali nosi
  `_endDrawerWasOpenBeforeBg` guard (vraća endDrawer koji je zatvoren pri
  odlasku u pozadinu). Re-registracija se dodaje **uz** taj guard, ne umjesto
  njega i ne unutar njegove `if` grane — sesiju treba vratiti bez obzira na
  to je li drawer bio otvoren.

Ista zajednička metoda pokriva i **replay**: nakon `clear()` na `completed`
ponovno pokretanje iste epizode (in-app play nakon kraja) ostaje bez metadata
i handlera dok je se ne pozove. Vidi P1 u §2.3 — protokol (Blok E2) to izrijekom
provjerava.

### 4.4 Što reći korisniku bez uljepšavanja

**Tap na Dynamic Island otvara aplikaciju koja svira — to je namjerno
ponašanje iOS-a i ne može se isključiti dok god želimo pozadinski zvuk.** To
je ista sprega: stavka u Dynamic Islandu *jest* razlog zašto OS ne oduzme
audio fokus. Tražiti „zvuk u pozadini, ali bez stavke" znači tražiti dvije
međusobno isključive stvari.

Popravljivo je samo dvoje:

1. da ondje ne ostane **mrtva** stavka nakon što reprodukcija stane (N1/N3
   gore) — to je naš posao;
2. da u native aplikaciji tap vodi u **našu** aplikaciju, a ne u browser —
   što se rješava time da se sluša native app, ne web. `audio_service` to već
   radi ispravno (N4).

---

## 5. Hipoteza 3 — Picture-in-Picture kao izlaz za iOS web

**Samo procjena troška. Ništa nije implementirano, i ne preporučuje se
započeti prije nego matrica pokaže da Safari/PWA stvarno padaju.**

### 5.1 Je li uopće izvedivo

Da, bez forka media_kita. Element je dohvatljiv:
`WebVideoController` čuva `HTMLVideoElement` u JS globalu
`$com.alexmercerind.media_kit.instances`, ključan po `await player.handle`
(`media_kit_video-2.0.1/lib/src/video_controller/web_video_controller/real.dart:52-54`).
Iz Darta je to jedan `globalContext.getProperty(...)` u `js_interop` fajlu.

API se **mora feature-detektirati, ne izvoditi iz verzija**: standardni
`requestPictureInPicture()` / `document.pictureInPictureEnabled` i WebKitov
stariji `webkitSupportsPresentationMode('picture-in-picture')` /
`webkitSetPresentationMode(...)` nisu jednako dostupni po browserima, a
verzijska podrška je upravo ono što ne smijemo tvrditi bez uređaja. Kod bi
probao standardni pa pao na webkit varijantu; ako nijedan nije prisutan, gumb
se ne prikazuje.

### 5.2 Opseg izmjene

| Fajl | Što |
|---|---|
| `lib/services/pip.dart` + `pip_web.dart` + `pip_stub.dart` (novi) | uvjetni import, gate na `dart.library.js_interop` (**ne** `dart.library.html` — puca `--wasm`); `canPip`, `enterPip()`, `exitPip()`, listeneri `enterpictureinpicture`/`leavepictureinpicture` |
| `lib/widgets/playback_controls.dart` | `PipButton`, isti obrazac kao `SpeedCycleButton` |
| `lib/widgets/episode_video.dart` | gumb u `desktopBottomBar` + `mobileBottomBar` |
| `lib/l10n/app_hr.arb` / `app_en.arb` | 2–3 ključa (`mediaPictureInPicture`, tooltip on/off) — ide kao dopuna T2, ne dira ih se izvan i18n taska |
| `test/pip_test.dart` | VM strana gatea, kao `test/screen_orientation_test.dart` |

### 5.3 Procjena

- **Mehanika: S, ~0,5–1 dan.** Uzorci već postoje u repou — `screen_orientation*.dart`
  iz T4 je gotovo isti oblik problema (uvjetni import + feature detekcija +
  gumb u obje trake).
- **Provjera na uređaju: M, ~0,5–1 dan.** Svaki krug traži deploy na
  `domovina.ai` (siguran kontekst) i ručnu provjeru na iPhoneu; nema
  automatiziranog testa koji ovo pokriva.
- **Ukupno realno ~1,5–2 dana**, uz tri rizika koja mogu to udvostručiti.

### 5.4 Rizici i ograničenja (ovo je bitniji dio procjene od brojki)

1. **PiP ne pokriva audio-only epizode.** PiP traži video track. Audio-only
   putanja (`hasMedia` + `AudioPoster`, `episode_simple_screen.dart:998`) ide
   kroz `audio.mp3` i uopće nema `EpisodeVideo`. Za dio kataloga rješenje ne
   postoji — a upravo je taj dio onaj gdje je pozadinski zvuk najvažniji.
2. **U PiP-u nestaju svi naši overlayi.** Titlove rendamo sami kroz
   `controls:` builder (Flutter sloj), ne kroz `<track>` — vidi zamku #4 u
   `CLAUDE.md`. U PiP prozoru ostaje goli video s nativnim kontrolama: bez
   titlova, bez speaker badgea, bez Undo pilule i bez gumba za brzinu.
3. **PiP je ručna radnja, svaki put.** Ne može se pozvati bez korisnikove
   geste i ne pamti se između epizoda. Kao „zamjena za pozadinski zvuk" to je
   bitno lošiji ugovor nego u native aplikaciji — korisnik mora znati da mora.
4. **Platform-view re-parent.** Ulazak u PiP mijenja gdje se element renderira.
   Ako se ponaša kao remove+insert, browser pauzira (`CLAUDE.md`, media_kit
   zamka #1). Lijek postoji i ne treba ga pisati iznova —
   `_resumeAfterTransition(wasPlaying)` u `episode_video.dart` — ali je to
   pretpostavka koju treba provjeriti, ne činjenica.
5. **PWA u standalone modu** je zaseban slučaj i ne smije se izvesti iz
   Safarijevog rezultata.

### 5.5 Preporuka

Ne krenuti u PiP prije §2. Ako matrica pokaže da Safari i PWA drže zvuk u
pozadini (što je za očekivati, jer zato Media Session i SW postoje), PiP je
rješenje za jedan browser — iOS Chrome — i to lošije od već isporučive
alternative iz hipoteze 1 („instaliraj aplikaciju"). Redoslijed ulaganja bi
tada bio: popravak N1/N3 → traka za iOS Chrome → PiP tek ako se pokaže da
promašujemo mjerljiv broj korisnika.

---

## 6. Otvoreno

Uređaj je spojen i build je na njemu (§1.2), pa je „traži uređaj" prestalo biti
prepreka. Ostalo je ovo:

- **Matrica §2, native stupac** — traži **promatrača**: Blok A (§2.1). Zvuk,
  Dynamic Island i lock screen se ne daju pročitati s kabela.
- **Matrica §2, web stupci, redovi 1–2** — Blokovi B/C/D na produkciji.
- **Matrica §2, red brzine za web** — 🚫 **blokirano do prvog deploya.** Traži
  T3 kod na sigurnom origin-u; danas ni produkcija (nema T3) ni LAN (nije
  siguran) to ne daju. Ovo nije propust mjerenja nego stvarno ograničenje.
- **Gate Media Sessiona u WebKitu na nesigurnom origin-u** — jedina nepoznanica
  koja odlučuje je li LAN server uopće upotrebljiv za web mjerenja. Razrješava
  ga Blok F, 30 s po browseru.
- **P1/P2/P3 iz §2.3** — Blok E; najvažniji, jer jedini pada na naš teren.
- **Popravak §4.3** — napisan, **namjerno neprimijenjen** (nalog: mjeriti na
  zatečenom buildu). Ide odmah nakon što Blok E vrati opažanja.
- **N5 (redoslijed pri prijelazu epizoda)** — Blok E5, usput.
- **Dug iz T4** (rotacijski fullscreen na stvarnom iPhoneu) — Blok G.
- **Zapis u `CLAUDE.md`** — tek kad ima što zapisati; sada bi to bila
  pretpostavka.
- **Crni ekran nakon duže suspenzije (§7.1)** — uzrok nepoznat, jednokratno.
  Razlikovni test (pokretanje tapom na ikonu umjesto preko `devicectl`) je
  prvi sljedeći korak.

### 6.1 Što je od ovoga bilo moguće izmjeriti bez čovjeka — i je izmjereno

Da se ne traži dvaput: sve dolje je gotovo i **ne treba** korisnika.

| Pitanje | Odgovor | Kako |
|---|---|---|
| Prolazi li iOS release build i instalacija? | da | §1.2 |
| Radi li aplikacija na uređaju? | da, v2.0.117, `main() start` u logu | §1.3 |
| Postoje li preduvjeti za pozadinski zvuk na nativeu? | da (`UIBackgroundModes`, `audio_service`) | §1.2 |
| Da li se device log da hvatati tijekom testa? | da, `idevicesyslog` | §1.3 |
| Ima li produkcija T1–T4? | **ne** (string T2 nedostaje u bundleu) | §1.4 |
| Ima li LAN server Service Worker? | **ne** (nesiguran kontekst) | §1.5 |
| Postoje li testne epizode (video + audio-only)? | da, `nOCD7LosCxc` / `0475c583ce5` | §2.1 |

---

## 7. Zabilježena opažanja tijekom mjerenja

Stvari viđene usput koje nisu dio matrice, ali ne smiju propasti. Ovdje se ne
zaključuje — samo bilježi što je viđeno i što je provjereno da **nije** uzrok.

### 7.1 Crni ekran u native aplikaciji nakon duže suspenzije (2026-07-27)

**Status: UZROK NEPOZNAT. Jednokratno, nije ponovljeno.** Zapisano jer je
riječ o ponašanju pri povratku iz pozadine — dakle istom području koje T5
istražuje — pa bi gubitak ovog traga bio šteta.

**Što se dogodilo.** Korisnik je prijavio da aplikacija pokazuje crni ekran.
Iz zahvaćenog syslog-a (23 MB, filtar iz §1.3):

| Vrijeme | Događaj |
|---|---|
| 14:59:49 | launch preko `devicectl`, PID **6668**, scene `ready`, Foreground |
| 14:59:52 | zadnja naša linija: `ChannelCache: done, 48/48 cached` |
| 15:05:12 | `App transitioned to background`, razlog deaktivacije **`appSwitcher`** (korisnikov swipe) |
| 15:13:18 / 15:13:39 | `App transitioned to foreground`, scene ponovno `ready`, `Front display did change: ai.domovina` |
| 15:15:39 | `process terminate --kill` + `launch` → novi PID **6693**, čist startup u 2 s |

**PID 6668 je isti kroz cijeli period.** Proces nije umro niti je bio ponovno
pokrenut — bio je živ i u prvom planu, ali nije crtao. To je profil
zaglavljenog rendera nakon ~8 minuta suspenzije, **ne pad**.

**Što je provjereno da NIJE uzrok:**

- **Crash** — nula Flutter iznimaka, nula watchdog terminacija, nula jetsam
  kill-ova za `ai.domovina` u cijelom zahvatu.
- **Zamka u vlastitoj pretrazi (dvaput):** prvi grep na `assertion` dao je
  lažne pogotke — `audiomxd` linije sadrže `PowerAssertion`. I filtar
  `-m DOMOVINA` iz §1.3 **promašuje Flutter iznimke**, jer one nemaju naš
  prefiks; zato ih treba tražiti u širokom zahvatu (`flutter:` linije bez
  `DOMOVINA` — bilo ih je **0**).
- **Šutnja Fluttera nije dokaz.** Između 14:59:52 i 15:13:39 nema naših linija,
  ali aplikacija loga samo pri startu i na određene događaje — mirna početna
  stranica ne proizvodi ništa. Odsutnost logova ovdje ne znači mrtav engine.
- **Tri `Runner` procesa** na uređaju (6287, 6673, 6693) — **nisu** duple
  instance naše aplikacije. Samo 6693 ima naš bundle kontejner
  (`B186B820…`, iz instalacije u §1.2); druga se dva u cijelom logu ni jednom
  ne pojavljuju uz `ai.domovina`. `Runner.app` je generičko ime **svake**
  Flutter aplikacije, pa su to drugi Flutter buildovi na uređaju.
- **`ai.domovina.companion`** (15:00:18) — sistemski **DAS prewarm** posao,
  odmah suspendiran. U repou ne postoji takav target ni ekstenzija. Nije
  sudjelovao, ali je zabilježen jer je u našem bundle prostoru.

**Otvorena razlikovna hipoteza.** Sva pokretanja do incidenta išla su kroz
`xcrun devicectl device process launch`, što proces parenta drukčije nego
SpringBoard. Prvi sljedeći korak je **pokrenuti aplikaciju tapom na ikonu**: ako
se crni ekran vraća samo nakon `devicectl` launcha, uzrok je alat za pokretanje
a ne aplikacija — i onda mjerenja iz §2.1 ne smiju ići preko `devicectl`.

**Ograničenje instrumenta (vrijedi i šire).** `idevicescreenshot` **ne radi na
iOS-u 26** — CoreDevice je maknuo `screenshotr` s lockdownd-a, pa javlja
„Could not start screenshotr service". Stanje ekrana se zato **ne da** provjeriti
programatski; svaka tvrdnja o tome što se vidi traži ljudsko oko. To vrijedi i
za cijeli protokol §2.1, ne samo za ovaj incident.
