# Playback overhaul — zaključak kruga (2026-07-28)

Zatvaranje plana `2026-07-27-playback-overhaul.md`. Ovdje je samo ono što nije
trajno zapisano drugdje u repou: **stanje po tasku, otvoreni dug, i naučeno**.
Sve mjerne podatke i analizu iOS-a nosi `docs/ios-background-playback.md`.

## Stanje

| Task | Ishod | Commit | Verdikt |
|---|---|---|---|
| T1+T2 servisi, widgeti, i18n | ✅ | `02e09f3` | r1 DORADA → r2 OK |
| T3 ožičenje u oba playera | ✅ | `4bf058a` | r3 OK |
| T4 rotacijski fullscreen | ✅ | `4efb8a6` | r4 OK |
| T5 iOS istraga | ⚠️ djelomično | `01e2d2e`, `fa0135d` + zadnji | r5 OK |

Deployano kao **v2.0.118** (`a490767`). T5 je prekinut na korisnikov zahtjev —
matrica je popunjena samo dijelom (Blok A na produkciji: zvuk svira 60 s,
lock screen i Dynamic Island rade), ostatak ćelija je označen NEIZMJERENO.

## Otvoreni dug — što ostaje za sljedeći krug

1. **Mrtva stavka u Dynamic Islandu.** `clearImpl()` u `media_session_web.dart`
   ne postavlja `playbackState = 'none'`, `player.stream.completed` se ne sluša
   nigdje, a isključen pref „u pozadini" pauzira bez čišćenja sesije. Popravak
   je **dizajniran i provjeren u kodu, ali NIJE primijenjen** — namjerno, da se
   matrica izmjeri na zatečenom buildu. Diff i zamke: `docs/ios-background-playback.md` §4.3.
   Netrivijalan dio je re-registracija sesije na `AppLifecycleState.resumed`:
   dva ekrana nisu simetrična (`episode_simple_screen` nema `resumed` granu,
   `episode_screen` je ima ali s `_endDrawerWasOpenBeforeBg` guardom).
2. **Crni video nakon izlaska iz fullscreena** — nalaz iz T4: to je
   **pre-postojeći** web bug (jedan `<video>` element po playeru), ne regresija
   rotacijskog fullscreena. Zaslužuje vlastiti task.
3. **Ostatak T5 matrice** — Blokovi B–G (iOS Chrome, PWA, brzina 1,5× u
   pozadini, mrtva stavka nakon kraja epizode). Protokol je napisan i spreman.
4. **PiP za iOS web** — procijenjen, **ne preporučuje se** započeti prije nego
   matrica pokaže da Safari/PWA stvarno padaju.
5. **iOS Chrome „instaliraj aplikaciju" traka** — samo ako se hipoteza 1
   potvrdi. Traka, ne modal.

## Naučeno

- **Prag detekcije skoka mora poštovati brzinu reprodukcije.** `position`
  stream fira ~5×/s, pa je pri 2,0× prirodni pomak ~0,4 s. Prag od 2 s je
  siguran; ispod 1 s bi brzina generirala lažne „skokove". Ista zamka čeka svaku
  buduću heuristiku nad pozicijom.
- **Formatiranje brojeva ide kroz `NumberFormat`, sufiks kroz ARB — ali ne oba.**
  r1 DORADA je bila dupli „ד: `formatPlaybackRate` je već vraćao `1,25×`, a ARB
  predložak `mediaPlaybackSpeedSet` dodavao još jedan → screen reader je čitao
  „1,25××". Vizualni label i semantics label ne smiju dijeliti isti helper ako
  jedan od njih ide kroz predložak s vlastitim sufiksom.
- **Fullscreen nije jedna značajka nego tri putanje.** Pravi landscape na
  nativeu, `screen.orientation.lock` na Android Chromeu, vizualna rotacija
  ondje gdje oboje padne. Pokušaj jednog rješenja za sve platforme bio bi
  potrošeni krug.
- **„PROVJERITI PRVO" u planu je zaradilo svoj prostor.** T4 je imao izričit
  nalog da dokaže `RotatedBox` hit-testing prije gradnje ostatka — dokazano je
  testom i živo u Chromeu, pa ostatak taska nije bio kockanje.
- **Popravak se ne primjenjuje prije mjerenja koje ga opravdava.** T5 je našao
  konkretan defekt analizom koda i **svjesno ga ostavio neprimijenjenim** —
  inače se više ne bi moglo utvrditi je li taj defekt uzrok onoga što je
  korisnik prijavio.
- **Web zaostaje za nativeom, ne obrnuto.** `audio_service` je sesiju uredno
  raspuštao cijelo vrijeme; nedostatak je bio samo na web putanji. Kod dvojnih
  implementacija prvo provjeri radi li jedna strana već ispravno — popravak je
  onda poravnavanje, ne novi mehanizam.

## Procesno (AI tim)

- Testovi koje dev napiše izvan popisa fajlova iz plana (`playback_speed_test`,
  `playback_controls_test`) reviewer je propustio kao „čisti dobitak" umjesto
  da ih tretira kao odstupanje od ugovora. To je dobra kalibracija: popis
  fajlova štiti od sudara među devovima, ne zabranjuje testove.
- Pet krugova pregleda, jedan DORADA — a ta jedna dorada je bila a11y detalj
  koji nijedan test nije hvatao. Widget testovi koji ne asertaju semantics
  label ne pokrivaju ono zbog čega label postoji.
