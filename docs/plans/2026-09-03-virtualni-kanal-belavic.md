# Virtualni kanal za Tomislava Belavića — delta plan

> 3.9.2026. Nastavak `docs/plans/virtualni-kanali.md` (28.7.2026.).
> Putanje bez prefiksa repoa su u ovom repou; sve `services/…`,
> `infra/…` i `docs/plans/2026-07-29-…` su u `domovina-rag`.
> Sve brojke ispod su **izmjerene danas**, uz naredbu kojom se ponavljaju.
> Ovaj dokument NE ponavlja odluke O1–O10 iz izvornog plana — one stoje.

## Zaključak u jednoj rečenici

Cijeli frontend virtualnih kanala je **isporučen i živ od v2.0.122**, iza
`PersonChannelFlag` (default OFF); nedostaje **samo backend** u `domovina-rag`,
i to manje nego što izvorni plan traži — za Belavića **F1 uopće nije potreban**,
dovoljan je **reducirani F2** od tri polja i jednog novog endpointa.

## 1. Što je gotovo (mjereno u ovom repou)

Svih 7 taskova T1–T7 iz izvornog plana je landano (PR `fb56f95`, release
`0bfb3be` = v2.0.122) i deployano; danas je repo na v2.0.145.

| Task | Artefakt | Stanje |
|---|---|---|
| T1 i18n | `lib/l10n/app_{hr,en}.arb` | ✅ ključevi `person*`, `channelsFilter*`, `tvRailPersons` |
| T2 model/servis | `person_hub.dart`, `person_index_cache.dart`, `person_channel_flag.dart` | ✅ |
| T3 kanal-forma | `person_screen.dart`, `person_monogram.dart` | ✅ |
| T4 katalog | `all_channels_screen.dart`, `person_card.dart`, `persons_rail.dart`, `search_overlay.dart` | ✅ |
| T5 praćenje | `follow_service.dart`, `follow_button.dart`, `followed_rail.dart` | ✅ (remote sync no-op, `domovina_ai.follows` ne postoji) |
| T6 Android TV | `tv_person_screen.dart` (586 redaka), lane u `tv_home_screen.dart` | ✅ |
| T7 SEO | `/sitemap.xml` grana u `web/_worker.js` (redak 252), `web/robots.txt` (redak 9) | ✅ (dvoslojni Cache API build) |

```bash
flutter test test/person_hub_test.dart test/person_index_test.dart \
             test/follow_service_test.dart
# → All tests passed! (51 testova, 3.9.2026.)
```

**Graceful degradacija je bolja nego što plan obećava** i to mijenja opseg
backenda. `PersonHub.fromJson` sam izvodi ono što backend ne pošalje:

- `tier` izostane → klijentska klasifikacija iz `speaking_seconds`/`duration_seconds`,
  fallback `primary` (`person_hub.dart:201`)
- `total_duration_seconds` izostane → zbroj `duration_seconds` primary epizoda (`:374`)
- `first_year`/`last_year` izostanu → izvedeni iz `upload_date` (`:392`)

Znači: backend **ne mora** izračunati tier, ukupno trajanje ni godine.

## 2. Što je blokada (mjereno na produkciji)

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://mcp.domovina.ai/api/persons
# → 404   (endpoint iz §4.1 izvornog plana ne postoji)

curl -s https://mcp.domovina.ai/api/person/tomislav-belavic | jq 'keys'
# → nema is_virtual_channel, tier, duration_seconds, channel_name,
#   channel_tracked, cameo_episode_count, optout
```

`PersonHub.isVirtualChannel` je `_isVirtualChannel && !ambiguous && !optout`
(`person_hub.dart:306`), a `_isVirtualChannel` dolazi isključivo iz
`is_virtual_channel`. Bez tog jednog boola kanal-forma se **ne može upaliti ni
s `?vk=1`** — ekran izgleda točno kao danas. To je jedina prava blokada.

U `domovina-rag`: migracije su na `005_person_mentions_name.sql` (nema
`006_person_channel.sql`), `get-person.ts` ne poznaje ni jedno novo polje,
`public-api.ts` ima samo `/api/search` i `/api/person/:slug`. F1 je isplaniran
<!-- doc-refs:ignore-start --> (`domovina-rag` →
`docs/plans/2026-07-29-f1-adhoc-epizode-s-cdn.md`, T1–T5 — drugi repo)
<!-- doc-refs:ignore-end -->
ali **nije izveden** —
nema koda koji dira CDN ni `speaking_seconds`.

## 3. Ključni nalaz: Belavić ne treba F1

F1 postoji zato što je Marijani Šarolić Robić 16 od 17 epizoda bilo **izvan
korpusa** (`_unlisted`, producer output ne postoji ni na jednom disku).
Belavićev slučaj je drukčiji — sve njegove epizode su **već u ClickHouseu**, s
ispravnim praćenim kanalom:

```bash
docker exec domovina-rag-infra-clickhouse-1 clickhouse-client -d rag --query "
WITH r AS (SELECT youtube_id, channel, end_ts, start_ts, speaker FROM rag_chunks)
SELECT youtube_id, any(channel) AS ch, toString(any(upload_date)) AS d,
       round(max(end_ts)) AS trajanje,
       round(sum((end_ts-start_ts)/length(splitByChar(',', speaker)))) AS govor
FROM rag_chunks
WHERE arrayExists(x -> x = 'Tomislav Belavić',
      arrayMap(t -> trim(BOTH ' ' FROM t), splitByChar(',', speaker)))
GROUP BY youtube_id ORDER BY d DESC"
```

| youtube_id | kanal | datum | trajanje (s) | govor (s) | udio |
|---|---|---|---|---|---|
| `uixJ3kMd0XA` | zeljka_markic_i_narod_hr | 2026-06-18 | 2865 | 1629 | 57 % |
| `JV1vYeN5Hus` | muzevni_budite | 2026-02-28 | 2924 | 2912 | 100 % |
| `KvIhy5SESYs` | domovina_tv | 2026-02-24 | 6220 | 3634 | 58 % |
| `O4EjSWPuI64` | mladi_za_domovinu | 2025-12-21 | 5224 | 3370 | 65 % |
| `W869S5xB0jo` | 40_dana_za_zivot | 2024-07-31 | 4612 | 2515 | 55 % |
| `s1acPycl61I` | podcast_bitno_net | 2023-02-07 | 2636 | 1331 | 50 % |

6 epizoda, **6 različitih kanala**, ukupno **24 481 s = 6 h 48 min**. Svih 6 je
`primary` (najniži udio 50 % ≫ prag 15 %) — kanal-forma mu ne treba tier logiku.

Dvije stvari koje ovo rješava bez ijednog novog ingesta:

- **`duration_seconds` ima izvor**: `max(end_ts)` po epizodi. Izvorni plan je
  tvrdio da izvora nema (`episodes.duration_sec` je 0/2960, cloud PG nema
  `episodes`). Ima ga — u samim chunkovima.
- **mjerna zamka iz §F2 je zaobiđena**: `sum((end_ts-start_ts)/broj_govornika_u_chunku)`
  ne napuhuje udio u panelima, jer chunk s dva govornika dijeli trajanje na dva.
  Nije egzaktno kao per-cue SRT iz F1-T3, ali za prag od 15 % je više nego dosta.

Također provjereno: **nema fragmentacije sluga** (`/api/person/belavic` → 404,
samo `tomislav-belavic` → 200), pa rizik iz §5 izvornog plana ovdje ne postoji.
Spomena ima 1, izvan kanala po odluci O3.

## 4. Novi nalaz koji mijenja O3 i T4: pravilo uvrštavanja pušta domaćine

Izvorni O3 kaže „automatski sve epizode gdje je osoba diariziran govornik" uz
prag ≥ 3 `primary` epizode za katalog. Mjerenje pokazuje da to pravilo daje
katalog od **311 osoba** (uz 49 kanala), a §5 izvornog plana sam kaže da preko
~50 osoba filter chip mora pasti na default „Kanali". Gore od brojke je **kakve**
osobe pušta:

```bash
# reprodukcija: PG aliases × CH tokeni, skripta u §6 ovog dokumenta
```

| Pravilo | Osoba u katalogu |
|---|---|
| ≥ 3 epizode (izvorni O3) | **311** |
| ≥ 3 epizode I ≥ 2 kanala | 178 |
| ≥ 3 epizode I ≥ 3 kanala | 110 |
| ≥ 3 ep I ≥ 3 kanala I ≤ 60 % epizoda na najvećem kanalu | 90 |
| isto, minus jednočlana i rolna imena | **76** |

Tko ulazi po izvornom pravilu, a **ne smije**:

| Osoba | ep | kanala | % na najvećem | zašto ne |
|---|---|---|---|---|
| fra Stjepan Brčina | 178 | 5 | 97 % | domaćin praćenog kanala — već ima `/c/` |
| Željka Markić | 160 | 4 | 97 % | domaćin |
| Vinko Mihaljević | 109 | 1 | 100 % | domaćin |
| Charlie Chapman | 110 | 2 | 96 % | ASR artefakt / domaćin |
| David Bernard 84 + David Barnard 68 | | 1 | 100 % | **ista osoba, dva sluga** (gaps §1, živo) |
| Pjevač, Svećenik, Ana, Marija, Ante… | 3–15 | 3–9 | | rolne oznake i jednočlana imena, nisu osobe |

Belavić u istom mjerenju: **6 ep / 6 kanala / 17 % na najvećem** — točno profil
koji feature cilja (gost, ne domaćin).

**Predložena dopuna O3** (`is_virtual_channel` u §4.1 postaje):

```
episode_count >= 3
  AND channel_count >= 3
  AND max_channel_share <= 0.6      -- nije domaćin
  AND slug ima >= 2 tokena          -- nije „Ana" / „Pjevač"
  AND slug nije rolna oznaka        -- crna lista: voditelj, gost, sugovornik,
  AND NOT optout                    --   pjevač, svećenik, propovjednik, …
```

Rezultat: **76 virtualnih kanala**, katalog od 125 zapisa umjesto 360, i filter
chip smije ostati na „Sve".

## 5. Taskovi (svi u `domovina-rag`) — **IZVEDENO 3.9.2026.**

> Status: B1–B4 su napisani i **izmjereni lokalno** (docker CH + PG); još
> **nisu deployani** na `mcp.domovina.ai`. Deploy je `services/mcp/deploy.sh`
> uz ručnu migraciju 006 — runbook je u `domovina-rag`, u datoteci person-hub.md pod `docs/`.
>
> Pravilo uvrštavanja iz §4 živi na jednom mjestu:
> `services/mcp/src/tools/person-channel.ts`. Izmjereno NAKON izvedbe:
> **74 virtualna kanala** (predviđeno 76 — razlika je tier filtar koji
> predviđanje nije primjenjivalo), nula domaćina, nula jednočlanih slugova,
> svih 74 nosi naslov zadnje epizode. Belavić: 6 ep / 6 kanala / 24 481 s,
> svih 6 izvornih kanala praćeno.

> Nijedan task nije u ovom repou. Frontend se **ne dira** — ako se dira, znači
> da backend ne poštuje ugovor iz §4 izvornog plana.

### B1 — `is_virtual_channel` + kanal-metapodaci na `/api/person/:slug` ✅

- **Fajlovi**: `services/mcp/src/tools/get-person.ts`
- **Opis**: CH upit iz `getPerson` (`get-person.ts:~300`) dobiva tri agregata po
  epizodi: `max(end_ts) AS duration_seconds`,
  `sum((end_ts-start_ts)/length(splitByChar(',', speaker))) AS speaking_seconds`,
  i `speaking_share`. Na korijenu odgovora: `is_virtual_channel` po pravilu iz §4,
  `optout: false`, `ambiguous` (true kad jedan slug pokriva > 1 `canonical_name`).
  `channel_name` + `channel_youtube_id` + `channel_tracked` iz
  `channels/data/index.json` s CDN-a (49 kanala, cache u memoriji) — slug koji je
  u indeksu → `channel_tracked: true`, inače false.
  `total_duration_seconds`, `first_year`, `last_year`, `tier`, `cameo_episodes[]`
  **NE treba** računati — frontend ih izvodi sam (§1).
- **Definicija gotovog**:
  `curl .../api/person/tomislav-belavic | jq '.is_virtual_channel, (.episodes|length), (.episodes[0].duration_seconds)'`
  → `true, 6, 2865`; svih 6 epizoda ima `channel_tracked: true`; **stari
  frontend ne primjećuje razliku** (sva su polja aditivna).

### B2 — `GET /api/persons` (enumerabilan indeks) ✅

- **Fajlovi**: `services/mcp/src/public-api.ts`, novi `services/mcp/src/tools/list-persons.ts`
- **Opis**: shema iz §4.1 izvornog plana, `Cache-Control: public, max-age=900`.
  **Enumeracija ide kroz PG `speakers` (2698 redaka sa slugom), NE kroz sirove CH
  tokene** — sirovi tokeni sadrže `UNKNOWN` (1534 epizode), `Voditelj` (885),
  `SPEAKER_00` (137), `Gost 1` (63)…, a `speakers` ih ne sadrži. Jedan CH upit
  grupiran po epizodi+kanalu, pa mapiranje alias → slug u Nodeu.
  `needs_review` **nije** filtar — postavljen je na svih 2698 redaka.
  Vraćaju se samo osobe s `is_virtual_channel: true` (očekivano 76).
- **Definicija gotovog**: `curl .../api/persons | jq '.person_count'` → ~76;
  `jq '.persons[].slug' | grep -c '^"[a-z]*"$'` → 0 (nema jednočlanih);
  ni jedan slug nije rolna oznaka; `tomislav-belavic` je u popisu.

### B3 — Tombstone tablice (override + opt-out) ✅

- **Fajlovi**: nova `infra/postgres/migrations/006_person_channel.sql`
- **Opis**: `person_channel_overrides` i `person_optouts` točno kako su u §4.3
  izvornog plana; `get-person.ts` i `list-persons.ts` ih primjenjuju.
  Ovo je jedina obrana od lažne atribucije govornika (§5) i jedini način da
  „David Bernard/Barnard" tip greške ne uđe u nečiji kanal.
- **Definicija gotovog**: `INSERT` u `person_optouts('tomislav-belavic')` →
  osoba ispada iz `/api/persons`, a `/api/person/tomislav-belavic` vraća
  `optout: true` (frontend to već crta kao minimalni profil, **nije** iza flaga).

### B4 — Odredište za „Prijavi grešku" ✅

- **Opis**: gumb u `person_screen.dart:1324` danas završava u `log()` + snackbar.
  Dok nema odredišta, mitigacija iz §5 izvornog plana je neaktivna, a to je
  uvjet iz otvorenog pitanja 5. Najmanji izlaz: `POST /api/person-report` u
  `public-api.ts` koji piše u `person_channel_overrides` s
  `action='exclude'` i `reason` = korisnikov tekst, **ali `needs_review` flagom**
  da ga čovjek potvrdi — inače je to javni brisač epizoda.
- **Definicija gotovog**: prijava iz UI-ja stigne u tablicu; epizoda ne ispada
  dok je ne potvrdi čovjek.

### B5 — Ručni avatar za Belavića (opcionalno, 1 UPDATE) — nije rađeno

`speakers.avatar_url` već postoji i `PersonHub` ga već čita. Bez njega se crta
monogram „TB" na navy gradijentu — što je po O5 namjerno ponašanje, ne rupa.

## 5b. Zamka koju je izvedba otkrila — B1 je htio pokvariti ŽIVI profil

`get-person.ts` sada iz `episodes[]` izdvaja `cameo` nastupe u
`cameo_episodes[]`. To je točno ono što ugovor traži i što frontend očekuje **u
kanal-formi** — ali profil **bez** feature flaga crtao je `hub.episodes`
doslovno.

Izmjereno 3.9.2026.: `cameo` je **31,7 %** svih parova govornik-epizoda
(2984 od 9425). Deploy B1-a bez ovog popravka tiho bi maknuo gotovo trećinu
nastupa sa svake javne person stranice — bez iznimke, bez greške u logu i bez
ijednog crvenog testa, jer `fromJson` novi ključ uredno pročita.

```bash
docker exec domovina-rag-infra-clickhouse-1 clickhouse-client -d rag --query "
WITH po_epizodi AS (
  SELECT youtube_id, round(max(end_ts)) AS trajanje FROM rag_chunks GROUP BY youtube_id
), po_govorniku AS (
  SELECT tok, youtube_id, round(sum(share)) AS govor FROM (
    SELECT youtube_id, (end_ts-start_ts)/length(splitByChar(',', speaker)) AS share,
           arrayJoin(arrayMap(t -> trim(BOTH ' ' FROM t), splitByChar(',', speaker))) AS tok
    FROM rag_chunks WHERE speaker != '') GROUP BY tok, youtube_id
)
SELECT count(), countIf(govor < 300 AND govor / nullIf(trajanje,0) < 0.15)
FROM po_govorniku JOIN po_epizodi USING (youtube_id)"
# → 9425  2984
```

**Popravak**: `PersonHub.allAppearances` (`lib/models/person_hub.dart`) spaja i
presortira oba popisa; `person_screen.dart` ga koristi na obje pozivne točke kad
`channelForm == false`. Presortiranje nije kozmetika — backend sortira svaki
popis zasebno, pa bi bez njega noviji cameo nastup pao ispod starijeg primary.

**Pravilo koje iz ovoga slijedi**: aditivno polje na backendu nije automatski
sigurno. Sigurno je tek kad se provjeri i **što je iz starog polja izašlo**, ne
samo što je u novo ušlo. Čuva ga grupa „regresija" u
`test/person_backend_contract_test.dart`.

## 6. Reprodukcija mjerenja iz §4

```bash
cd ~/git/domovinatv/domovina-rag
docker exec domovina-rag-infra-postgres-1 psql -U rag_user -d rag -tAF$'\t' -c \
  "SELECT slug, canonical_name, a FROM speakers, jsonb_array_elements_text(aliases) AS a" \
  > /tmp/aliases.tsv
docker exec domovina-rag-infra-clickhouse-1 clickhouse-client -d rag --query "
  WITH r AS (SELECT youtube_id, channel,
             trim(BOTH ' ' FROM arrayJoin(splitByChar(',', speaker))) AS tok
             FROM rag_chunks WHERE speaker != '')
  SELECT tok, channel, uniqExact(youtube_id) FROM r GROUP BY tok, channel" \
  --format TSV > /tmp/tokch.tsv
# pa spoj alias→slug i primijeni pravilo iz §4 (ep>=3, kanala>=3, top<=0.6,
# >=2 tokena u slugu)
```

Lokalni CH je imao 150 085 chunkova / 3157 epizoda u trenutku mjerenja; cloud
može biti svježiji, pa brojku 76 treba ponovno izmjeriti nad cloud instancom
prije nego flag ode ON.

## 7. Redoslijed i verifikacija

```
B1  →  provjeri /p/tomislav-belavic?vk=1 u pregledniku (kanal-forma, 6 epizoda,
       eyebrow „Osoba · 6 ep · 6h 48m", svi chipovi kanala KLIKABILNI jer su
       svi praćeni)
B2  →  /channels?vk=1 filter „Osobe", home rail, pretraga „belavic"/„Belavić",
       TV lane; izmjeri scroll na web buildu (§5 izvornog plana)
B3  →  prije nego flag ode ON
B4  →  prije nego flag ode ON
zatim  PersonChannelFlag default ON (jedan commit u domovina.ai)
```

Rollback je nepromijenjen: flag OFF bez redeploya (`?vk=0`), B1/B2 su aditivni
pa stari frontend radi s novim backendom i obratno.

## 8. Odluka o identitetu — **donesena 3.9.2026.**

Zahtjev je bio kanal za **udrugu**, a isporučen je kanal za **osobu**
(`/p/tomislav-belavic`). Organizacija kao entitet ne postoji ni u shemi, ni u
modelu, ni u rutama, i njezino uvođenje je odgođeno s napisanim planom:
`docs/plans/2026-09-03-organizacije-kao-kanal.md` (tri puta po cijeni, okidač za
svaki, i zamke koje se ne smiju zaboraviti — npr. da nova javna ruta mora u OBA
deep-link popisa).

Kratka verzija: **Put 1** (`speakers.display_name`, pola dana) kad zatreba ime
udruge u naslovu; **Put 2** (kolekcija govornika, `/api/group/:slug` istog
oblika kao `/api/person/:slug`) tek kad se pojavi DRUGA organizacija ili udruga
s dva člana koji oba gostuju; **Put 3** (organizacija s vlasništvom i pinka
kampanjom) se ne planira.

**Ograda koja vrijedi odmah** (O8, granica (b)): hero i kartica ne smiju tvrditi
„službeni kanal". Ovo je agregat Belavićevih gostovanja na tuđim kanalima.
Obavijest iz O8 §1 se šalje prije nego flag ode ON, iako je Belavić predsjednik
udruge i pristanak je lako dobiti.
