# Zid podrške — krug 1 (predaja timu)

> Izvorni dizajn: `docs/plans/2026-08-08-zid-podrske-redizajn.md` (commit `22f4527`).
> **Ovaj dokument ne donosi nijednu novu dizajnersku odluku** — samo reže §4 tog
> plana na taskove. Ako nešto ovdje proturječi izvorniku, izvornik je jači.

## Cilj

Obrazac za podršku prestaje biti dva anonimna dense polja: dobiva tri **označena**
polja (Ime / Poveznica / Poruka) i **živi pregled kartice** tako da donator vidi
točan ishod prije plaćanja. Zid podrške prestaje imati rupe: `Wrap` se zamjenjuje
staggered mrežom s **točno dvije dopuštene visine** kartice, puni tekst i preview
sele u **detaljni sheet na tap**, a duplirani URL (jednom kao linkificirani tekst,
odmah ispod isti u preview kartici) nestaje. Uz to se izvornik pixel-grid algoritma
(`pixel-grid-v1`, lokalni git bez remotea) trajno spašava na GitHub.

Krug je namjerno uzak: iz §4 idu samo **A**, **C** i **F0**. B, D, E, F1–F3 i G
čekaju odgovore na otvorena pitanja iz §3 izvornog plana i **ne smiju se dirati**.

## Kontekst

Zatečeno stanje, provjereno u kodu 8.8.2026.:

- `pinka_contribute_panel.dart:604` i `:630` — oba `TextField` imaju samo
  `hintText` (`l.pinkaNameHint`, `l.pinkaMessageHint`), nijedan `labelText`.
  Hint nestaje na prvi utipkani znak → ostaju dva vizualno identična `isDense`
  polja bez ijedne oznake. Polja za poveznicu **nema**.
- `pinka_client.dart:186` `contribute(...)` šalje `display_name` i `message` samo
  kad `!anonymous`. Edge funkcija `domovina-api/supabase/functions/pinka-contribute/index.ts:61`
  čita **samo imenovane ključeve** iz `body` (`campaign_id`, `amount_cents`,
  `slot_keys`, `tier_id`, `display_name`, `message`, `anonymous`, `quantity`,
  `label`) — **nepoznati ključ se tiho ignorira, ne ruši zahtjev**. Provjereno,
  nije pretpostavka.
- `pinka-webhook` OG preview vadi **isključivo iz `message`** (`index.ts:110`).
  Zato u ovom krugu poveznica MORA i dalje završiti u `message` (vidi T2, korak 4)
  — inače bi A bio **regresija**: danas ljudi zalijepe URL u poruku i dobiju
  preview, a nakon A bi im poveznica nestala u polju koje backend još ne čita.
- `pinka_wall_list.dart:32` — `Wrap` s `maxWidth: 340`; redovi se poravnavaju po
  najvišoj kartici → rupe. `:97–108` renderira poruku (linkificiranu) **i** preview
  karticu s istim URL-om.
- `PinkaWallList` ima **tri pozivna mjesta**: `pinka_campaign_screen.dart:539`
  (desktop stupac), `:687` (mobile) i `campaign_manage_screen.dart:363` (vlasnički
  pregled). Javni API (`contributions`, `flashIds`) i ugovor „widget **nema**
  vlastiti scroll, host scrolla" moraju ostati nepromijenjeni.
- `lib/l10n/app_localizations*.dart` su **praćeni u gitu** (`synthetic-package: false`),
  pa i18n task mijenja 5 fajlova, ne 2.
- Ruta: `app_router.dart:94` montira isti ekran na `/c/:slug/support` i
  `/c/:slug/doniraj` (HR/EN par), `:207` isto za `/v/:videoId/...`.
- U `test/` **nema nijednog pinka testa** — nema što pokvariti, ali ni mreže koja hvata.

Zamke koje vrijede za cijeli krug:

- **Poznato padajući testovi**: `test/widget_test.dart` i `test/home_feed_test.dart`
  padaju i na čistom `mainu`. Nisu regresija — ne „popravljati" ih.
- Nema deploya. `scripts/deploy.sh` se u ovom krugu **ne pokreće** (izričit nalog
  vlasnika). Zid podrške na produkciji ostaje na v2.0.130+152.
- **Migracije**: ovaj krug ne dira bazu. Za budući B/D/E vrijedi pravilo iz
  `2026-08-08-glasanje-predaja.md` §2 — svaka izmjena migracije ide kao NOVI fajl
  s novim timestampom, nikad in-place (povijest je već na produkciji).

## Taskovi

### T1 — i18n za cijeli krug (i samo i18n)

- **Fajlovi**: `lib/l10n/app_hr.arb`, `lib/l10n/app_en.arb`,
  `lib/l10n/app_localizations.dart`, `lib/l10n/app_localizations_hr.dart`,
  `lib/l10n/app_localizations_en.dart`
- **Opis**: dodaj **sve** ključeve koje trebaju T2 i T3, odjednom, pa
  `flutter gen-l10n`. Ovo je jedini task kruga koji smije dirati ARB — zato ide
  prvi i sam. Ključevi (HR je template, `@key` metapodatak dodaj gdje treba):

  | Ključ | HR | EN | Za |
  |---|---|---|---|
  | `pinkaNameLabel` | Ime ili nadimak | Name or nickname | T2 |
  | `pinkaNameHelper` | Ovako ćeš biti potpisan na zidu | This is how you'll be credited on the wall | T2 |
  | `pinkaLinkLabel` | Poveznica (neobavezno) | Link (optional) | T2 |
  | `pinkaLinkHelper` | Tvoja stranica, projekt ili firma | Your site, project or company | T2 |
  | `pinkaLinkInvalid` | Provjeri poveznicu — mora počinjati s https:// | Check the link — it must start with https:// | T2 |
  | `pinkaMessageLabel` | Poruka (neobavezno) | Message (optional) | T2 |
  | `pinkaPreviewHeading` | Ovako će izgledati tvoja kartica | This is how your card will look | T2 |
  | `pinkaPreviewNamePlaceholder` | Tvoje ime ili nadimak | Your name or nickname | T2 |
  | `pinkaPreviewMessagePlaceholder` | Tvoja poruka | Your message | T2 |
  | `pinkaWallOpenLink` | Otvori poveznicu | Open link | T3 |
  | `pinkaWallCardDetails` | Prikaži cijelu poruku | Show full message | T3 |

- **Definicija gotovog**: `flutter gen-l10n` prošao, `flutter analyze` čist,
  svih 11 ključeva postoji u oba jezika i u generiranim klasama. **Ništa osim
  ovih 5 fajlova nije dirano** — nijedan widget, jer njihovi pozivi tek dolaze
  u T2/T3.
- **Ne diraj**: `pinkaNameHint` i `pinkaMessageHint` ostaju u ARB-u iako nakon
  T2 postaju neiskorišteni. Brisanje bi razbilo `flutter analyze` u prozoru dok
  T2 još nije integriran; čišćenje ide u sljedeći krug.
- Registar je **neformalno „ti"** (vidi CLAUDE.md); helper tekstovi gore su
  već pisani tako.

### T2 — [A] Tri polja s `labelText` + živi pregled kartice

- **Fajlovi**: `lib/pinka_sdk/src/widgets/pinka_contribute_panel.dart`,
  `lib/pinka_sdk/src/pinka_client.dart`
- **Opis**:
  1. `_identityFields` (`:593`) dobiva **tri** polja umjesto dva. Svako dobiva
     `labelText` (`hintText` se miče — to je cijeli popravak dijagnoze 1.2) i,
     gdje tablica u T1 to predviđa, `helperText`. Redoslijed: Ime → Poveznica →
     Poruka. Novo polje poveznice: vlastiti `TextEditingController`
     (`_linkCtrl`, dispose u `dispose()`), `maxLength` 200, `enabled: !_anonymous`,
     `keyboardType: TextInputType.url`. Zadrži razmake između polja (danas su
     zalijepljena) i postojeći „Prijavi se" gumb uz polje imena.
  2. **Validacija poveznice u klijentu**: prazno je uredu; inače mora parsirati
     kao apsolutni URL sa shemom `https` (dopusti da korisnik utipka bez sheme →
     normaliziraj na `https://`), inače `_error = l.pinkaLinkInvalid` i **ne šalji
     zahtjev**. Ne izmišljaj drugu validaciju — worker već ima `safeUrl`.
  3. **Živi pregled kartice** ispod obrasca, iznad gumba: naslov
     `l.pinkaPreviewHeading`, pa kartica koja pokazuje **točno ono što će biti na
     zidu** — ime (ili `l.pinkaAnonymous` kad je kvačica „anonimno"), iznos
     (`fmtEur(_amountCents) €`), poruka, i (kad je poveznica upisana) redak s
     hostom poveznice. Prazna polja → prigušeni placeholderi
     (`pinkaPreviewNamePlaceholder` / `pinkaPreviewMessagePlaceholder`,
     `onSurfaceVariant`, bez lažnog sadržaja). Kartica se rebuilda na tipkanje
     (`onChanged` → `setState`), poštuje `_anonymous`.
     **Vlastiti privatni widget u ovom fajlu** — NE importaj i NE refaktoriraj
     `pinka_wall_list.dart` (paralelno ga prepisuje T3). Da, to je privremeni
     duplikat rendera; upisan je kao dug u „Van opsega".
  4. **Slanje poveznice** (ovo je najosjetljiviji dio):
     `PinkaClient.contribute` dobiva neobavezan `String? linkUrl` i, kad nije
     anonimno i vrijednost nije prazna, šalje ga kao `link_url` u body. To je
     **most prema B, ne oslanjanje na B** — edge funkcija ga danas ignorira
     (provjereno, vidi Kontekst). Da poveznica u ovom krugu ne bi nestala,
     panel uz to **doda URL na kraj `message`** ako ga poruka već ne sadrži i
     ako rezultat stane u `_msgMax` (280); ako ne stane, šalje se samo `link_url`.
     Napiši komentar u kodu da je append privremeni most dok `link_url` ne postane
     izvor istine u `pinka-webhook`.
  5. Anonimni doprinos i dalje ne šalje ni ime, ni poruku, ni poveznicu.
- **Definicija gotovog**:
  - `flutter analyze` čist.
  - Ručno na `/c/<slug>/doniraj` (ili `/v/<id>/support`): sve tri oznake ostaju
    vidljive **nakon** upisa teksta; pregled se mijenja u živo; kvačica
    „Doniraj anonimno" prebaci pregled na „Anoniman" i onemogući sva tri polja;
    neispravna poveznica blokira slanje s porukom.
  - Novi widget testovi u `test/pinka_contribute_panel_test.dart` (danas ne
    postoji nijedan pinka test): (a) sve tri `labelText` oznake vidljive nakon
    unosa teksta, (b) pregled prikazuje upisano ime i iznos, (c) kvačica
    anonimno pokaže `pinkaAnonymous`.
- **Ne diraj**: `pinka_wall_list.dart`, ARB fajlove, `pubspec.yaml`, ništa u
  `domovina-api`.

### T3 — [C] Staggered zid, dvije visine, detaljni sheet, bez duplog URL-a

- **Fajlovi**: `lib/pinka_sdk/src/widgets/pinka_wall_list.dart`, `pubspec.yaml`
  (+ `pubspec.lock` ako paket prođe spike)
- **Opis**:
  1. **PRVI KORAK — spike, prije ijedne izmjene UI-a**: dodaj
     `flutter_staggered_grid_view` u `pubspec.yaml`, `flutter pub get`, pa
     `flutter build web --wasm`. **PROVJERITI: prolazi li build.** Ako padne
     (ili paket ne podnosi wasm target), **makni paket** i idi na ručnu putanju
     iz točke 3b — nemoj gubiti vrijeme na zaobilaženja. Ishod spikea (prošlo/palo,
     verzija paketa) upiši kao komentar u sažetak za reviewera.
  2. `Wrap` → **staggered mreža s točno dvije dopuštene visine**:
     - **visoka** (2 jedinice) — doprinos **ima** `linkPreview` s sadržajem:
       ime + iznos, naslov preview kartice (do 2 retka), izvor/host;
     - **niska** (1 jedinica) — nema preview: ime + iznos + poruka (1 redak).
     Visine su **fiksne konstante u px** (npr. 96 / 190 — kalibriraj po sadržaju),
     a broj stupaca izračunaj iz `LayoutBuilder` (ciljna širina kartice ~340,
     `crossAxisCount = (maxWidth / 340).floor().clamp(1, 4)`).
     Kako su visine fiksne, **sav tekst mora biti clampan** (`maxLines` +
     `TextOverflow.ellipsis`) — ništa ne smije prelijevati.
  3. Implementacija:
     a. ako spike prođe: `StaggeredGrid.count` +
        `StaggeredGridTile.extent(crossAxisCellCount: 1, mainAxisExtent: <fiksna visina>)`;
     b. ako spike padne: **ručni shortest-column raspored** — kartice se redom
        dodjeljuju stupcu koji je trenutno najniži (visine su poznate konstante,
        pa je izračun determinističan i jeftin), render je `Row` od `Column`-a.
        Ovo je legitiman put upravo zato što su visine fiksne; izvorni plan je
        paket birao zbog *nepoznatih* visina.
  4. **Duplirani URL nestaje**: kartica prikazuje **ili** linkificiranu poruku
     **ili** preview karticu, nikad oboje. Kad preview postoji, iz teksta poruke
     ukloni URL koji je preview izvor (`preview.url`) prije prikaza i trimaj
     ostatak; ako od poruke ne ostane ništa, redak poruke se izostavlja.
  5. **Detaljni sheet na tap** (`showModalBottomSheet`): puni tekst poruke (bez
     clampa), preview kartica s opisom, ime, iznos, gumb `l.pinkaWallOpenLink`
     (samo kad ima poveznicu; otvara kroz postojeći `pinkaLaunch`) i `commonClose`.
     Cijela kartica je tap meta; `l.pinkaWallCardDetails` koristi se kao
     `Semantics.label`/tooltip da je jasno da ima nastavak.
  6. **Nepromijenjeno**: javni API widgeta (`contributions`, `flashIds`),
     `Semantics(identifier: 'pinka-wall-list')` sidro, „arrive" flash animacija
     za nove unose i činjenica da widget **nema vlastiti scroll** (host scrolla —
     tri pozivna mjesta ovise o tome).
- **Definicija gotovog**:
  - `flutter analyze` čist; `flutter build web --wasm` prolazi (i s paketom i bez).
  - Novi widget test `test/pinka_wall_list_test.dart`: (a) doprinos s preview-om
    dobiva visoku, bez preview-a nisku pločicu, (b) URL se u kartici pojavljuje
    **točno jednom**, (c) tap otvara sheet s punim tekstom poruke.
  - Ručno na `/c/<slug>/doniraj`: nema vidljivih rupa između kartica na širokom
    i uskom viewportu; zid se i dalje scrolla zajedno s hostom; vlasnički
    `campaign_manage_screen` se i dalje builda i prikazuje zid.
- **Ne diraj**: `pinka_contribute_panel.dart`, ARB fajlove, `pinka_campaign_screen.dart`
  (ako se pokaže da je izmjena ondje nužna — **stani i javi orkestratoru**, ne
  širi opseg sam).

### T4 — [F0] Spasi `pixel-grid-v1` (drugi repo, izvan domovina.ai)

- **Fajlovi**: ništa u ovom repou. Radi se u
  `/Users/ms/git/spremni/za-sponzorstvo/pixel-grid-v1/`.
- **Zašto**: 30 commita, **bez remotea**, postoji samo na ovom disku. Iz njega
  se u kasnijim krugovima (F2/F3) vadi algoritam širenja vektora — jedan
  `rm -rf` i posao je nemoguć.
- **Zatečeno stanje, provjereno**: 30 commita, jedina grana `main`, HEAD
  `4c50d49`, 74 praćena fajla (`build/` **nije** praćen). `git status` pokazuje
  74 „izmijenjena" fajla, ali `git diff --summary` kaže da su to **isključivo
  promjene moda** `100644 → 100755` (artefakt kopiranja s exFAT diska) — nema
  nijedne izmjene sadržaja, nema untracked fajlova. U `.git/objects` leži 216
  AppleDouble smeća (`._*`), radni direktorij je 876 MB (uglavnom `build/` i
  `.dart_tool/`), `.git` 108 MiB u loose objektima.
- **Opis**:
  1. Očisti AppleDouble smeće: `find . -name '._*' -delete` (nije praćeno, ne
     gubi se ništa).
  2. `git fsck --full` — **mora proći bez missing/broken objekata**. Ako ne
     prođe: STANI i javi, ne guraj oštećenu povijest.
  3. `git gc --prune=now` (sabija 108 MiB loose objekata u pack).
  4. `git config core.fileMode false` — ugasi fantomski diff modova.
  5. `gh repo create domovinatv/pixel-grid-v1 --private --source=. --remote=origin --push`.
     **MORA biti `--private`.** Ako nemaš pravo stvaranja u organizaciji
     `domovinatv`, napravi ga kao `stepanic/pixel-grid-v1 --private` i to
     izrijekom javi.
  6. Verificiraj klonom u scratch direktorij: `git clone <url> /tmp/pg-verify`
     → `git log --oneline | wc -l` = **30**, HEAD = **`4c50d49`**,
     `lib/main.dart` postoji i ima **2601 liniju**, `DREAMFLOW_PROMPT.md` postoji.
     Obriši scratch klon nakon provjere.
- **Definicija gotovog**: `git ls-remote origin` vraća `main`, klon-verifikacija
  iz koraka 6 prošla, URL repoa upisan u sažetak za reviewera. Ništa u
  `domovina.ai` radnom stablu nije promijenjeno.
- **Ne radi**: ne commitaj promjene modova, ne diraj `build/`, ne prepisuj
  povijest (`filter-branch`/`filter-repo`), ne diraj `domovina-storage`.

## Ovisnosti

```
T1 → (T2 ‖ T3)        T1 mora biti gotov i integriran PRIJE nego T2 i T3 krenu
T4 ‖ svemu            drugi repo, nula zajedničkih fajlova
```

- **T1 je jedini vlasnik i18n fajlova u ovom krugu.** T2 i T3 ne smiju dirati
  `lib/l10n/*` ni pokretati `flutter gen-l10n`. Ako T2 ili T3 otkrije da mu treba
  ključ kojeg nema u T1 tablici — **javi orkestratoru**, on ga daje natrag devu
  koji je radio T1, nikad drugom.
- T2 i T3 imaju **disjunktne** fajlove (`pinka_contribute_panel.dart` +
  `pinka_client.dart` vs `pinka_wall_list.dart` + `pubspec.yaml`) i smiju ići
  istovremeno na dva deva.
- T4 može krenuti odmah, paralelno s T1.

## Rizik

**nizak** za cijeli krug.

- T1/T2/T3 su čisti UI + jedan neobavezan parametar u klijentu; ne diraju se
  auth, plaćanja na backendu, Supabase shema, `web/_worker.js` ni deploy putanja.
- Jedina prava zamka je T2 korak 4 (poveznica mora završiti i u `message`, inače
  je krug regresija za OG preview) i T3 korak 1 (`--wasm` spike prije nego paket
  uđe u granu).
- T4 dira drugi repo, ali samo aditivno (novi remote, `gc`, čišćenje neparaćenog
  smeća) — povijest se ne prepisuje.

## Verifikacija

- `flutter analyze` — **čist**, obavezno nakon svakog taska.
- `flutter test` — očekivano padaju **samo** `test/widget_test.dart` i
  `test/home_feed_test.dart` (padaju i na čistom `mainu`, nisu regresija). Novi
  `pinka_contribute_panel_test.dart` i `pinka_wall_list_test.dart` moraju proći.
- `flutter build web --wasm` — mora proći u T3 (to je i spike i verifikacija).
- Ručno u appu: `/c/<slug>/doniraj` (isti ekran i na `/c/<slug>/support`,
  `app_router.dart:94`) — obrazac s tri označena polja i živim pregledom, zid
  bez rupa, tap na karticu otvara sheet. Provjeriti i uski (mobilni) viewport.
- T4: klon-verifikacija opisana u definiciji gotovog.

## Van opsega

Ne dirati u ovom krugu — svaka od ovih stavki čeka odgovor na otvoreno pitanje
iz §3 izvornog plana ili je izričito odgođena:

- **B** — `contributions.link_url` stupac + `coalesce` lanac u `pinka-webhook`
  (`domovina-api`). Klijent ga u T2 samo šalje; backend ga smije ignorirati.
- **D** — keširanje OG slike (`/api/og-image-cache`, R2, `image_cached`).
  Zid i dalje **ne renderira** tuđe slike — `Image.network` na tuđi host ostaje
  zabranjen (odavanje IP-a posjetitelja).
- **E** — spoj mape i zida (zajednički ključ u viewovima, highlight u oba smjera).
- **F1/F2/F3** — `flutter_svg` spike, `_expandSponsors` port, omjer kao parametar.
  `pinka_grid_wall.dart` se u ovom krugu **ne otvara**.
- **G** — sidrene kartice, ljepljiva traka, blok povjerenja, filtri zida
  („Svi / S poveznicom / Najnoviji"), preslagivanje trostupčane hijerarhije
  u `pinka_campaign_screen.dart`.
- Bilo kakva migracija ili izmjena `domovina-api` / `pay.domovina.ai`.
- **Deploy.** `scripts/deploy.sh` se ne pokreće bez izričitog naloga vlasnika.
- **Poznati dug koji ovaj krug svjesno stvara**: pregled kartice u T2 i kartica
  zida u T3 su dva odvojena rendera iste stvari. Objedinjavanje u jedan widget
  ide u sljedeći krug, kad oba budu integrirana — sada bi značilo da dva deva
  pišu isti fajl.

## Zapisnik izvedbe (8.8.2026.)

Krug izveden u dva vala: T1‖T4 (review r1: OK), pa T2‖T3 (review r2: OK).
Commitovi: plan `e58b707`, T1 `4377269`, T2/T3 vidi git log. T4 spašen na
privatni `github.com/domovinatv/pixel-grid-v1` (HEAD `4c50d49`, 30 commita,
klon-verifikacija prošla). Spike iz T3 koraka 1: `flutter_staggered_grid_view
^0.7.0` **podnosi** `--wasm` build — paket ostaje, ručna putanja 3b nije trebala.
Visine kalibrirane na 84/178 px (invarijanta `tall = 2*short + spacing`,
testirana).

Dvije svjesne devijacije od slova plana (reviewer ih u r2 ocijenio boljima;
planner ih može poništiti u sljedećem krugu ako se ne slaže):

1. Poruka u kartici zida je običan `Text`, ne linkificirana — inline linkovi bi
   otimali tap cijeloj kartici; linkovi žive u detaljnom sheetu.
2. Kartica bez poruke i bez previewa nije tap meta i ne nosi tooltip (sheet bi
   samo ponovio već vidljivo).

Neodrađeno iz DoD-a: vizualna provjera vlasničkog `campaign_manage_screen`
(traži prijavu vlasnika kanala) — pokrivena analyze-om, wasm buildom i time da
je javni API `PinkaWallList` nepromijenjen.
