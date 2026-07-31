# Pošten Plus paywall — zaključak kruga (2026-07-31)

Plan: [`2026-07-31-plus-posteni-paywall.md`](2026-07-31-plus-posteni-paywall.md).
Izveo AI tim (`tim-domovina-ai`): T1+T2 dev1 serijski, T4 dev2 paralelno,
T3 bez izmjene koda. Dva kruga pregleda (reviewer na Opusu, rizik visok).

**Isporučeno**: commit `d8f2171` + bump `70e1725`, deploy **v2.0.127+149**,
pushano na `origin/main`.

## Što je promijenjeno

| | Prije | Poslije |
|---|---|---|
| Pogodnosti na paywallu | 7 nabrojanih, 2 stvarne | 3 (pretraga 12→30, bedž, podrška) — sve istinite |
| `UpgradeTrigger` | 8 vrijednosti (`sync`/`offline`/`export`/`enFirst`/`magisterium`) | 3 (`generic`, `search`, `badge`); stari `?from=…` linkovi padaju na `generic` |
| Sinkronizacija | reklamirana kao Plus | maknuta — besplatna je svim prijavljenima |
| Roadmap | nije postojao | „U planu" sekcija **ispod cijena**, disclaimer bez rokova |
| Store listing | nepisan | `docs/payments/store-listing-copy.md` (HR+EN, obje trgovine, checklista) |

Obrisani ARB ključevi: `channelBenefitSync/Offline/Export/EnglishFirst/Magisterium`
+ pripadni `channelTrigger*`. Novi: `channelBenefitSupport`, `plusRoadmapTitle`,
`plusRoadmapDisclaimer`, `plusRoadmapOffline`, `plusRoadmapExport`.

## Dvije stvari koje je pregled uhvatio, a plan nije predvidio

1. **„Bedž uz tvoje ime" je bio isti razred greške zbog kojeg je krug i pokrenut.**
   `PlusBadge` se renderira na točno jednom mjestu — `account_screen.dart:262`,
   unutar Plus kartice, **ne** uz ime (ime je u `_profileCard` iznad) — i nije
   javno vidljiv nikome osim samom pretplatniku. Copy je ispravljen u „Bedž
   podupiratelja **na tvom računu**" u oba ARB-a i na sva tri mjesta u store
   listingu. `PlusBadgeIfActive` (`plus_badge.dart:38`) ostaje mrtav kod — to je
   mjesto na koje bedž ide ako se ikad poželi uz ime; tada se mijenja i ovaj tekst.

2. **„U planu: semantička pretraga" bila je netočnost u suprotnom smjeru.**
   Semantička pretraga **postoji i besplatna je** (`search_overlay.dart:204`
   `_runSemantic()` → `/api/search` za sve); Plus mijenja samo `limit` nad tom
   istom pretragom. Stavka bi na istom ekranu proturječila
   `channelBenefitSearch`. Obrisana; roadmap ima dvije stavke (offline, izvoz).

**Pravilo koje iz ovoga slijedi** (zapisano i kao doc komentar na
`paywall_screen.dart:71-76`): stavka smije u „U planu" **samo ako danas doista
ne postoji ni u kojem obliku**. Roadmap koji krivo prikazuje isporučenu značajku
kao budući rad ruši vjerodostojnost cijele sekcije — a sekcija postoji baš zato
da bude vjerodostojna.

## Apple 2.1 granica — potvrđeno u oba kruga

`_roadmap()` (`paywall_screen.dart:552-592`) je u cijelosti
`Padding > Column > [Divider, Text, Row(Icon+Text)×2, Text]`. Nijedan
`GestureDetector`, `InkWell`, `*Button`, `ListTile`, `onTap`, `Link`,
`SelectableText` ni `TextSpan.recognizer`. Ikone `Icons.circle_outlined` 10 px,
sve `cs.onSurfaceVariant`. Poziv je **izvan** `if (isPlus)` grane — sekcija
stoji ispod `_planSection`+`_legal` kad korisnik nije Plus, odnosno ispod
`_alreadyPlus` kartice kad jest.

**Rule**: svaka buduća izmjena te sekcije mora ponoviti ovu provjeru. Klikabilan
element ondje pretvara dopušten roadmap u „nefunkcionalnu značajku u appu" =
Apple 2.1 reject.

## Verifikacija

`flutter analyze` čist. `flutter test` — padaju samo dva poznata
(`widget_test.dart` HttpClient smoke, `home_feed_test.dart` datum-ovisan),
identično čistom mainu. `test/payments_test.dart` 7/7, uključujući „every
trigger has non-empty headline + subtitle (HR + EN)" nad suženim enumom.
Generirani l10n u sinkronizaciji s ARB-om (0 referenci na obrisane ključeve u
`lib/` i `test/`). Cijene netaknute. `EntitlementService`, RevenueCat
konfiguracija, `web/_worker.js` i deploy putanja nisu dirani.

## Ostaje otvoreno

- **Apple 3.1.2 („trajna vrijednost")** — Plus danas nudi širu pretragu i bedž.
  Svjesna odluka vlasnika. Ako review padne na tom osnovu, sljedeći korak je
  izvoz sažetka/transkripta (Markdown pa PDF) kao prva prava Plus značajka.
- `channelTriggerGenericSubtitle` — „otključaj **sve pogodnosti**" / „unlock
  **every** benefit". Nije neistina, ali zvuči krupnije nego što jest, a to je
  naslov koji fallbackom vidi svatko tko dođe na `/subscribe?from=offline`.
  Nije prepreka submissionu.
- `docs/payments/pricing-and-tiers.md` nosi lipanjsku tablicu pogodnosti koja
  više ne odgovara stvarnosti; `store-listing-copy.md:330` to označava kao
  neaktualno i preusmjerava na §1. Zaslužuje isti prolaz.
- **Store submission** — ručno, nije dio ovog kruga. Preostali provisioning
  koraci: `docs/payments/provisioning-state.md` §6.
