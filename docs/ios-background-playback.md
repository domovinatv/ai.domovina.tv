# iOS pozadinska reprodukcija i Dynamic Island — istraga

**Status: NEDOVRŠENO.** Analiza koda je gotova, mjerenja nisu. Matrica je
prazna jer traži fizički iPhone uz stroj (signing + „Trust" na uređaju).
Nijedna ćelija nije popunjena pretpostavkom — ako piše „čeka uređaj", to
znači da nitko to nije izmjerio.

Task: T5 iz `docs/plans/2026-07-27-playback-overhaul.md`.
Datum analize koda: 2026-07-27 (nakon T1–T4).

---

## 1. Okruženje

`flutter devices` na dev stroju (2026-07-27):

| Uređaj | ID | Platforma |
|---|---|---|
| iPhone MS 15 Pro | `00008130-00184D0111FA001C` | iOS 26.5.2 (23F84) |
| moto g86 5G | `ZY32M4Q2GJ` | Android 16 (API 36) |
| macOS | `macos` | darwin-arm64 26.5.1 |
| Chrome | `chrome` | 150.0.7871.184 |

iPhone je vidljiv preko kabela, ali `flutter run` na njega traži korisnika uz
stroj: signing tim u Xcodeu i „Trust This Computer" na samom uređaju. iPad
(10th Yellow) se javio samo kao neuspješan wireless probe — nije spojen.

Build putanje (redom po cijeni):

```bash
flutter run --release -d 00008130-00184D0111FA001C
# ili, kad treba instalirati bez žive sesije:
flutter build ipa && xcrun devicectl device install app --device <udid> <ipa>
# vanjski disk nije montiran → derived data lokalno:
xcodebuild -derivedDataPath build/ios_dd …
```

Web putanje se testiraju na produkcijskom `https://domovina.ai` (Media Session
i SW traže siguran kontekst; `flutter run -d chrome` na localhostu ne
reproducira iOS ponašanje jer nije riječ o iOS-u).

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
| **zaključan zaslon** | ⏳ čeka uređaj | ⏳ čeka uređaj | ⏳ čeka uređaj | ⏳ čeka uređaj |
| **druga aplikacija u prvom planu** | ⏳ čeka uređaj | ⏳ čeka uređaj | ⏳ čeka uređaj | ⏳ čeka uređaj |
| **brzina 1,5× u pozadini** | ⏳ čeka uređaj | ⏳ čeka uređaj | ⏳ čeka uređaj | ⏳ čeka uređaj |

### 2.1 Protokol (da mjerenje bude ponovljivo)

Prije svake ćelije: force-quit aplikacije/browsera, pa svježe otvaranje
epizode. Uvijek ista epizoda s videom (ne audio-only) osim gdje je izrijekom
drukčije.

1. Otvori `/m/<id>`, pusti reprodukciju, sačekaj da prijeđe 10 s.
2. Za red „brzina 1,5×" prije koraka 3 postavi brzinu gumbom na 1,5×.
3. Prebaci u pozadinu na traženi način (Power tipka = zaključan zaslon;
   swipe up + otvori Poruke = druga aplikacija u prvom planu).
4. Štoperica 60 s. Zabilježi **A**.
5. Bez otključavanja: fotografiraj/opiši Dynamic Island i lock screen (**DI**,
   **LS**). Provjeri rade li play/pause i ±10 s s lock screena.
6. Za red brzine dodatno: usporedi koliko je sadržaja stvarno prošlo s onim
   što scrub bar na lock screenu tvrdi (drift = `setPositionState` ne dobiva
   pravu brzinu; T3 to je trebao riješiti, ovo je provjera).
7. Vrati se u prvi plan i zabilježi je li reprodukcija nastavila ondje gdje je
   stala ili je skočila/pauzirala.

### 2.2 Zasebna provjera „mrtve stavke" (hipoteza 2)

Ovo nije u matrici jer nije o pozadini, nego o čišćenju sesije. Tri koraka,
svaki na Safariju i u PWA:

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
  registrirana s metadatom → stavka preživi playback. Kandidat za P1 iz §2.2.
- **Pref „u pozadini" isključen + odlazak u pozadinu.**
  `didChangeAppLifecycleState` (`episode_screen.dart:708-714`,
  `episode_simple_screen.dart:293-296`) pozove `_player?.pause()` i vrati se.
  Sesija ostaje. Korisnik je izričito rekao „ne sviraj u pozadini", a i dalje
  dobije stavku u Dynamic Islandu. Kandidat za P3.
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
i handlera dok je se ne pozove. Vidi P1 u §2.2 — testni protokol to izrijekom
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

- Cijela matrica §2 — traži fizički iPhone i korisnika uz stroj.
- P1/P2/P3 iz §2.2 — isto.
- Popravak §4.3 — napisan, namjerno neprimijenjen do mjerenja.
- N5 (redoslijed pri prijelazu epizoda) — provjeriti usput.
- Zapis u `CLAUDE.md` — tek kad ima što zapisati; sada bi to bila pretpostavka.
