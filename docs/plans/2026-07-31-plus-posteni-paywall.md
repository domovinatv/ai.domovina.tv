# DOMOVINA Plus — pošten paywall (obećanja = stvarnost + odvojena „U planu" sekcija)

## Cilj

Korisnik na paywallu vidi **točno ono što danas dobiva** kupnjom, a planirane
funkcionalnosti stoje u vizualno odvojenoj sekciji „U planu" s jasnim
disclaimerom da nisu dio kupnje i da nemaju rok. Time app postaje spreman za
App Store / Play submission s uključenim IAP-om, bez rizika odbijanja zbog
netočnih tvrdnji.

## Kontekst

Revizija 2026-07-31 (zapis: `docs/payments/provisioning-state.md`) utvrdila je
da paywall nabraja **sedam** pogodnosti, a u cijelom appu postoje **samo dva**
mjesta koja čitaju `EntitlementService.isPlus`:

- `lib/screens/home/search_overlay.dart:207` — limit rezultata 12 → 30
- `lib/widgets/plus_badge.dart:46` — vizualni bedž

Ne postoji ništa od: offline preuzimanja, izvoza (PDF/Markdown/DOCX — nula
koda), gatea na Magisterium, gatea na „engleski prvi", imena na zidu zahvale
(pinka zid je vezan na donacije, ne na Plus). **Sinkronizacija se reklamira kao
Plus, a besplatna je svim prijavljenima** — dakle ne smije ostati na popisu.

`UpgradeTrigger` (`lib/screens/subscribe/upgrade_trigger.dart`) ima osam
vrijednosti s vlastitim naslovima/podnaslovima, ali `openPaywall` se u cijelom
kodu zove **samo s `generic`**, i to isključivo iz `account_screen.dart`
(linije 160, 272, 293). Copy za `offline`/`export`/`magisterium`/`enFirst`
ipak je dohvatljiv ručno složenim URL-om `/subscribe?from=offline`, pa su te
tvrdnje tehnički još uvijek u produktu.

**Odluka vlasnika (2026-07-31):** ovaj krug NE gradi nove funkcionalnosti, nego
usklađuje komunikaciju. Model je „founder / early access": kupuje se ono što
radi danas, a roadmap je zaseban i neobvezujući.

Zašto baš tako (za slučaj da netko kasnije predloži drukčije): Apple 2.1 (App
Completeness) odbija „coming soon" *funkcionalnosti* u appu, ali tekstualna
roadmap sekcija to nije; 2.3.2 traži da bude jasno što se kupnjom dobiva; 3.1.2
traži da pretplata daje trajnu vrijednost — zato roadmap NE smije biti glavni
argument za kupnju. Google Play: Deceptive Behavior + pravila za pretplate.

Cijene u `_indicativePlans` (4,99 / 39,99 / 99,99 €) **odgovaraju**
`docs/payments/pricing-and-tiers.md` — ne dirati ih u ovom krugu.

## Taskovi

### T1 — i18n: pošten copy + roadmap ključevi + trim triggera

- **Fajlovi**: `lib/l10n/app_hr.arb`, `lib/l10n/app_en.arb`,
  `lib/l10n/app_localizations*.dart` (generirano),
  `lib/screens/subscribe/upgrade_trigger.dart`
- **Opis**:
  1. Prepiši `channelBenefit*` ključeve tako da ostanu SAMO stvarne pogodnosti.
     Predložak (HR → EN), slobodno dotjeraj stil ali ne i značenje:
     - `channelBenefitSearch`: „Šira pretraga — do 30 rezultata umjesto 12" /
       „Broader search — up to 30 results instead of 12"
     - `channelBenefitBadge`: „Bedž podupiratelja uz tvoje ime" /
       „Supporter badge next to your name"
     - **novi** `channelBenefitSupport`: „Podržavaš razvoj i troškove arhive" /
       „You support the archive's development and running costs"
  2. **Obriši** (ili ostavi neiskorištene? NE — obriši) ključeve
     `channelBenefitSync`, `channelBenefitOffline`, `channelBenefitExport`,
     `channelBenefitEnglishFirst`, `channelBenefitMagisterium`.
  3. Prepiši `authPlusBenefits` (podnaslov na ekranu računa) u:
     „Šira pretraga, bedž podupiratelja i podrška arhivi." /
     „Broader search, a supporter badge, and support for the archive."
  4. **Novi ključevi za „U planu" sekciju**:
     - `plusRoadmapTitle`: „U planu" / „On the roadmap"
     - `plusRoadmapDisclaimer`: „Ovo su smjerovi razvoja, a ne dio onoga što
       danas kupuješ. Bez rokova — ako i kad stignu, bit će uključeni u Plus
       bez doplate." / „These are directions we're exploring, not part of what
       you're buying today. No timelines — if and when they arrive, they'll be
       included in Plus at no extra cost."
     - `plusRoadmapOffline`: „Preuzimanje epizoda za slušanje bez interneta" /
       „Downloading episodes for offline listening"
     - `plusRoadmapExport`: „Izvoz transkripata i sažetaka" /
       „Exporting transcripts and summaries"
     - ~~`plusRoadmapSemanticSearch`: „Semantička pretraga kroz cijelu arhivu"~~
       **OBRISANO u doradi r1 (2026-07-31)**: semantička pretraga već postoji i
       besplatna je za sve (`search_overlay.dart` → `/api/search`); Plus mijenja
       samo limit 12→30. Stavka bi na istom ekranu proturječila
       `channelBenefitSearch`. Roadmap ima dvije stavke: offline i izvoz.
  5. `upgrade_trigger.dart`: svedi `enum UpgradeTrigger` na ono što postoji —
     `generic`, `search`, `badge`. Obriši `sync`, `offline`, `export`,
     `enFirst`, `magisterium` iz enuma, iz `headline()`/`subtitle()` switcheva
     i njihove `channelTrigger*` ključeve iz OBA ARB fajla. `fromSlug` već ima
     fallback na `generic`, pa stari `?from=offline` linkovi i dalje rade —
     samo pokažu generički naslov. To je namjerno: uklanja tvrdnje o
     nepostojećim funkcionalnostima s javno dohvatljive rute.
  6. `flutter gen-l10n`.
- **Definicija gotovog**: `flutter gen-l10n` prolazi; `flutter analyze` čist
  (uključujući `paywall_screen.dart`, koji do T2 još referencira obrisane
  ključeve — zato T2 ide POSLIJE i ovaj task smije privremeno ostaviti
  analyze crven SAMO ako to izrijekom javi u SAŽETKU; preferirano je da T1 i T2
  idu istom devu serijski).
- **Registar**: neformalno „ti", dijakritike, IHJJ pravopis, bez ALL-CAPS u ARB
  vrijednostima.

### T2 — Paywall: benefits + „U planu" sekcija

- **Fajlovi**: `lib/screens/subscribe/paywall_screen.dart`
- **Ovisi o**: T1 (treba nove ključeve)
- **Opis**:
  1. `_plusBenefits` svedi na tri stavke iz T1: pretraga (`Icons.search`),
     bedž (`Icons.favorite`), podrška (`Icons.volunteer_activism`).
  2. Dodaj `_roadmap(ColorScheme)` widget i ubaci ga u `ListView` **ispod**
     `_planSection` i `_legal`, dakle ispod cijena — nikad iznad, jer ne smije
     izgledati kao dio ponude.
  3. Vizualno jasno odvojeno od pogodnosti: `Divider` iznad, prigušena boja
     (`cs.onSurfaceVariant`), ikone koje NE izgledaju kao značajke (npr.
     `Icons.circle_outlined` ili obična točka), **bez gumba i bez tapa**.
     Naslov `plusRoadmapTitle`, ispod njega tri stavke, pa
     `plusRoadmapDisclaimer` sitnim slovima.
  4. Sekcija se prikazuje i kad je korisnik već Plus (`isPlus == true`) —
     tada stoji ispod `_alreadyPlus` kartice.
  5. NE diraj cijene ni `_indicativePlans` — poklapaju se s
     `docs/payments/pricing-and-tiers.md`.
- **Definicija gotovog**: `flutter analyze` čist; na `/subscribe` se vidi
  točno tri pogodnosti, a „U planu" sekcija stoji ispod cijena, bez ijednog
  interaktivnog elementa; ponašanje kupnje nepromijenjeno.

### T3 — Ekran računa: uskladi podnaslov

- **Fajlovi**: `lib/screens/account/account_screen.dart`
- **Ovisi o**: T1 (ključ `authPlusBenefits`)
- **Paralelno s**: T2 (različit fajl)
- **Opis**: provjeri da `_plusCard` koristi novi `authPlusBenefits` i da nigdje
  drugdje na ekranu ne stoji tvrdnja o nepostojećoj funkcionalnosti (proći
  cijeli fajl, uključujući `_favoritesCard` i „Moja knjižnica" sekciju).
- **Definicija gotovog**: `flutter analyze` čist; `/account` ne spominje
  sinkronizaciju, izvoz ni offline kao Plus pogodnost.

### T4 — Store listing copy (dokument, bez koda)

- **Fajlovi**: `docs/payments/store-listing-copy.md` (novi)
- **Paralelno s**: svime (ne dira kod)
- **Opis**: tekst opisa aplikacije za App Store i Play (HR + EN) koji NE
  spominje nepostojeće funkcionalnosti, plus kratka sekcija „što se smije, a
  što ne smije pisati o Plusu" da se greška ne ponovi. Napomeni izrijekom da
  se listing mijenja **ručno u konzolama** (nema API-ja za taj tekst) i da
  screenshotovi u `store-assets/` moraju proći istu provjeru.
- **Definicija gotovog**: dokument postoji, sadrži HR i EN varijantu opisa i
  checklistu; nijedna rečenica ne obećava offline, izvoz, „neograničenu
  semantičku pretragu", Magisterium gate ni sinkronizaciju kao Plus pogodnost.

## Ovisnosti

- `T1 → T2` (serijski; T2 treba ključeve iz T1) — **preferirano istom devu**
- `T1 → T3` (serijski)
- `T2 ‖ T3` (različiti fajlovi, oba nakon T1)
- `T4 ‖ sve` (samo dokumentacija)

`lib/l10n/app_hr.arb` i `app_en.arb` dira **isključivo T1** — to je poznata
zajednička točka koja ruši paralelizaciju.

## Rizik

**visok** — dira RevenueCat/paywall putanju i tekst koji ide pred store review.
Reviewer neka ide na Opus. Konkretno provjeriti: da kupnja i restore i dalje
rade nepromijenjeno, da roadmap sekcija nema nijedan klikabilan element (to je
razlika između „roadmap" i „nefunkcionalna značajka" po Apple 2.1), i da
nijedan preostali string ne obećava nešto što ne postoji.

## Verifikacija

1. `flutter analyze` — čisto.
2. `flutter test` — jedini dopušteni padovi su poznati:
   `test/widget_test.dart` (HttpClient smoke) i `test/home_feed_test.dart`
   (datum-ovisan). Sve ostalo mora proći.
3. Ručno: `/subscribe` — tri pogodnosti, cijene, pa „U planu" ispod; ništa u
   toj sekciji nije klikabilno.
4. Ručno: `/subscribe?from=offline` — prikazuje **generički** naslov (fallback),
   ne više „preuzmi offline".
5. Ručno: `/account` — podnaslov Plus kartice ne spominje sinkronizaciju/izvoz.
6. `grep -rn "offline\|izvoz\|export\|sinkronizacij" lib/l10n/app_hr.arb` —
   preostali pogoci smiju biti samo u `plusRoadmap*` ključevima.
7. EN paritet: prebaci UI jezik na engleski i ponovi korake 3–5.

## Van opsega

- **Izgradnja izvoza, offline preuzimanja i semantičke pretrage** — namjerno
  NE u ovom krugu. Otvoreni rizik: ako Plus danas nudi samo bedž i širu
  pretragu, recenzent može osporiti Apple 3.1.2 („trajna vrijednost"). Vlasnik
  je upoznat i svjesno bira ovaj redoslijed; ako review padne na tom osnovu,
  sljedeći korak je izvoz sažetka/transkripta (Markdown pa PDF) kao prva prava
  Plus značajka.
- Cijene i store proizvodi (vidi `docs/payments/provisioning-state.md` §6).
- Web Billing / Stripe.
- Bilo kakva promjena `EntitlementService` logike ili RevenueCat konfiguracije.
