# Review: sponzorski trenuci, gost bez sesije, špica (8.10.2026.)

Pregled frontenda koji je u produkciji od v2.0.172: `4603170`, `c8784f6`,
`b372c69`, `7ecc640`, `c3da1fc`, `4504ffd`. Backendni dio istog reviewa (i
jedini kritičan nalaz) je u `domovina-api`:
`docs/review-2026-10-08-sponzorski-trenuci.md`.

Ponovna provjera 8.10.2026. pokazala je da nijedan nalaz još nije popravljen.
Do tada se ništa nije prodalo.

## Najvažnije s backenda (utječe na ovaj klijent)

**KRITIČNO, živo na produkciji:** prijava novog uređaja kodom („handoff") ne
radi bez sesije. Od v2.0.172 klijent sesiju ne diže (`b372c69`), a
`handoff-consume` bez nje vraća 401. Pogođeni su svježa instalacija, novi
preglednik, TV i svatko nakon odjave. Popravak je na backendu, a klijent ne
smije vratiti `signInAnonymously` (CLAUDE.md, „Bez anonimnih prijava").

## Sponzorski checkout

### VISOKO: reload tijekom plaćanja izgubi upute za plaćanje

- `lib/screens/sponsor/sponsor_episode_screen.dart:199-204` u adresnu traku
  stavi samo `?narudzba=<id>`. IBAN, opis plaćanja i QR žive samo u memoriji.
- Nakon reloada (`:562-575`) stanje `pending` pokaže samo „Čekamo uplatu".
- Na iOS-u Safari često izbaci tab dok je korisnik u aplikaciji banke. Po
  povratku nema po čemu platiti, a trenutak ostaje držan do isteka holda (do 24 h).
- Popravak: intent (IBAN, memo, iznos, istek) spremiti u `localStorage` pod id
  narudžbe i obnoviti ga uz `?narudzba=`. Alternativa je da
  `sponsor_order_status` vraća upute za plaćanje (promjena ugovora).

### SREDNJE

- **Polling staje na `expired`.** `SponsorOrderState.isFinal`
  (`lib/models/sponsor_offer.dart:160`) uključuje `expired`, a ugovor dopušta
  prijelaz `expired → paid` (kasna uplata, `payment.late`). Kupac koji plati
  kasno ne vidi da je oglas uživo dok ne osvježi stranicu.
- **Mrežna greška se broji kao „narudžba ne postoji".** `orderStatus` vraća
  `null` i za grešku i za praznu narudžbu, pa nakon reloada polling stane već
  nakon 3 neuspjela poziva (oko 15 s offline) s porukom da narudžba ne postoji
  (`sponsor_episode_screen.dart:309-313`).
- **App Store 3.1.1.** Prodaja oglasa unutar iOS aplikacije s vanjskom SEPA
  naplatom rizik je za review. Prijedlog: na iOS-u izlog i checkout otvoriti u
  pregledniku (`domovina.ai/c/…/oglasi`). **Odluka vlasnika.**

### NISKO

- Pollovi se mogu preklopiti: `Timer.periodic` svakih 5 s ne čeka da prethodni
  `tick()` završi (`:299-334`).
- Browserov Back na webu zaobilazi potvrdni dijalog (`PopScope`, `:380`). To je
  ista zamka kao kod modala (CLAUDE.md, „modal na webu ne zna za browserov Back").
- Logo ostaje u bucketu kad narudžba ne prođe (nema čišćenja).
- Oznaka „Sponzorirano" ne prikazuje se na TV-u (`lib/screens/tv/`) ni na
  `/yt/:id`.

## Auth i epizoda

- **SREDNJE: nema potvrde „Prijavljen si kao…" nakon prijave gosta.**
  `lib/services/auth_service.dart:209-216` snackbar pokazuje samo kad je
  prethodni korisnik bio anonimni korisnik (`_user?.isAnonymous`). Gost sada
  nema korisnika (`_user == null`), pa uvjet nikad nije ispunjen. Treba
  `(_user == null || _user!.isAnonymous)`. OAuth redirect ima vlastitu potvrdu
  u `AuthCallbackScreen`.
- **SREDNJE: svaki tap u članku gasi špicu na 20 s.**
  `lib/screens/episode_screen.dart:1849-1856` (`Listener.onPointerDown`) gasi
  špicu i na tap po timestampu ili rezultatu „Pronađi u epizodi", dakle i kad
  je korisnik upravo zatražio reprodukciju. Trebalo bi gasiti samo na scroll ili
  drag, ne na tap.
- NISKO: pomak headera u landscapeu, generička greška kod donacije s isteklom
  sesijom, legacy panel u `lib/services/pinka_service.dart`.
- „Pronađi u epizodi" je čisto.

## Provjereno i ispravno

- Pravila playera iz CLAUDE.md su poštovana: `SponsoredMoment` je na tri
  mjesta, ima jedan kontroler, panel ostaje montiran i nema emojija.
- Nema `signInAnonymously` (`test/no_anonymous_sign_in_test.dart`).
- Prijava se traži prije forme i forma preživi 409.

## Predloženi redoslijed

1. Backend handoff (vidi gore). Ovdje nema ništa za napraviti.
2. Prije prve prodaje: reload tijekom plaćanja, polling na `expired` i polling
   na mrežnu grešku.
3. Brzi popravci: „Prijavljen si kao…" i špica na tap.
4. Odluka vlasnika: iOS izlog (App Store 3.1.1).
