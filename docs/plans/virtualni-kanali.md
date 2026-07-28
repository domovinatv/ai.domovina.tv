# Virtualni kanali — osoba postaje kanal

> Plan, 28.07.2026. Predan timu kroz `/delegiraj`.
> Odjeljci 1–8 su feature dokument; odjeljci **Taskovi / Ovisnosti / Rizik /
> Verifikacija / Van opsega** na dnu su ugovor za orkestratora.

## Cilj

Gost koji nema svoj YouTube kanal danas u DOMOVINA.ai ne postoji kao entitet koji
se može pratiti. Kad je ovo gotovo, **osoba je kanal**: `/p/:slug` izgleda i
ponaša se kao kanalska stranica, osoba se pojavljuje u `/channels`, na home railu,
u pretrazi i u Android TV laneu, može ju se pratiti, i njezini nastupi kroz tuđe
kanale su javno dostupni i indeksirani. Prvi stanovnik je Marijana Šarolić Robić —
17 nastupa, 17 različitih izvornih kanala, 13 h 39 min.

---

## 1. Sažetak stanja

**Person Hub već radi end-to-end.** Ruta `/p/:slug`
(`lib/router/app_router.dart:72`) → `PersonService.fetch`
(`lib/services/person_service.dart:25`) → `GET mcp.domovina.ai/api/person/{slug}`
(`domovina-rag/services/mcp/src/tools/get-person.ts`) → `PersonScreen`
(`lib/screens/person/person_screen.dart`). Model već nosi obje facete —
`PersonHub.episodes` (govori) i `PersonHub.mentions` (spominje se),
`lib/models/person_hub.dart:128` — te `mentionChannels`/`mentionTimeline` za
profil koji postoji samo iz spomena. Share sloj je gotov: worker injecta
`og:type=profile` + JSON-LD `ProfilePage`/`Person` (`web/_worker.js:344`,
`injectPersonTags` na `:692`).

**Ono što featureu stvarno nedostaje nije profil, nego sadržaj i kanal-forma.**

Živa provjera 28.07.2026.:

| Slug | HTTP | `episode_count` | Stvarno obrađeno |
|---|---|---|---|
| `marijana-sarolic-robic` | 200 | **1** (`dDDwWZPVS0s`, kanal `slijedi_svoj_poziv_2`) | 17 |
| `tomislav-belavic` | 200 | 6 (svi iz praćenih kanala) | 6 + ad-hoc |

Uzrok je dvostruk i oba su izvan ovog repoa:

1. `fetch.domovina.tv/generate_channel_index.js:307` preskače sve direktorije s
   `_` prefiksom, pa `_unlisted` nikad ne uđe u `channels/data/index.json`. To je
   namjerni mehanizam neindeksiranosti (`pipeline.domovina.ai/README.md:115`).
2. ETL bi `_unlisted` **pročitao** — `domovina-rag/services/etl/etl/sources.py:111`
   filtrira samo `.`-prefiks — ali nad njim očito nije pušten. To je jedina prava
   blokada; ne treba mijenjati filter, nego pustiti run uz mapiranje kanala.

**Identitet izvornog kanala nije izgubljen.** `info.json` na CDN-u za ad-hoc
epizode nosi pravi `channel` i `channel_id`:

```
bkp-0X4aG9E → "Lider",           UCboxxQjTe6vkiny3mkIo_BQ
AVsBPQ7iLSQ → "N1",              UCpglal7d5mhV4lA1b3-DsCw
dDDwWZPVS0s → "Centar Ignacije", UCuk9D5H9mx7birJ1-S22nyQ
```

Virtualni kanal se, dakle, može složiti bez ijednog YouTube poziva.

**Kanalska strana je čista CDN prezentacija.** `channels/data/index.json`
(danas **48** kanala) → `ChannelIndex`/`ChannelSummary`
(`lib/models/channel_index.dart`) → `ChannelCard`
(`lib/screens/home/channel_card.dart`), `AllChannelsScreen` (lazy `SliverList`,
komentar o scroll-perfu na `lib/screens/channels/all_channels_screen.dart:14`) i
`TvChannelScreen`.

Ostali nalazi koji su oblikovali odluke:

- **Slug konvencije se sudaraju**: `/c/:slug` radi `-`→`_` (`app_router.dart:58`),
  `/p/:slug` slug koristi doslovno. Worker ima istu podjelu u regexima
  (`_worker.js:344` i `:365`).
- **Nema `sitemap.xml`**, a `web/robots.txt` dopušta sve. „Neindeksirano" danas
  znači isključivo „nije ni u jednom katalogu" — ne robots zabranu.
- **Praćenje ne postoji** ni za kanale ni za osobe. `FavoritesService`
  (`lib/services/favorites_service.dart`) prati samo epizode, dual-write
  localStorage + `domovina_ai.favorites`.
- **AASA koristi wildcard** `{'/': '*'}` (`_worker.js:167`) i Android manifest već
  ima `pathPrefix="/p/"` (`AndroidManifest.xml:74`) — zadržavanje `/p/` rute znači
  **nula izmjena deep-link allowlisti**.
- **Katalog MSR-a** (`certilia-esign/podcast/MSR-OBRADENI-VIDEI.md`): 17 epizoda,
  zbroj trajanja točno **49 151 s = 13 h 39 min 11 s**, na **17 različitih**
  izvornih kanala — jedan više nego u prvotnom popisu od 16, jer katalog ima i
  „Borna Kos / Kuća Europe" (`glG9kVRGivQ`).

**Odluke vlasnika repoa donesene prije pisanja plana (28.07.2026.)**, koje plan
izvodi bez preispitivanja:

- **Vidljivost**: epizoda uvrštena u virtualni kanal postaje **odmah public**.
- **Vlasništvo/monetizacija**: **ništa** u ovom krugu — čista prezentacija.
- **Pristanak**: **opt-out** model (profil je javan, uklanjanje na zahtjev).
- **Izvor podataka**: **prvo popraviti ETL**, sve se čita iz `/api/person`.

---

## 2. Odluke

### O1 — Definicija virtualnog kanala

**Odluka:** virtualni kanal je **zaseban indeks koji živi u `domovina-rag` API-ju**
(`GET /api/persons`), a u UI-ju se spaja s kanalima. Nije novi zapis u
`channels/data/index.json` i nije samo vizualna promocija `/p/`.

**Obrazloženje:** izvor istine je RAG (odluka vlasnika), a `/api/person/:slug` je
lookup po ključu — ne može se enumerirati. Discoverability (katalog, home rail,
TV lane, pretraga) zahtijeva popis, pa on ide ondje gdje su podaci. Frontend ga
troši kao **drugi** index paralelno s `ChannelIndex`; ugovor kanala ostaje netaknut.

**Odbačeno (a) — `type: virtual` u `channels/data/index.json`:** taj fajl generira
`generate_channel_index.js` iz lokalnog `storage/output` u drugom repou i ne može
izračunati cross-channel agregat po govorniku bez dupliciranja RAG logike. Uz to bi
`ChannelService.loadChannel(id)` očekivao `channels/data/<id>.json` koji ne postoji,
a svaki potrošač `ChannelSummary` (sort modovi, ownership, pinka refs vezani na
`UC…` id) trebao bi null-guardove.

**Odbačeno (c) — samo vizualna promocija `/p/`:** bez enumerabilnog indeksa osoba
se ne može pojaviti u `/channels`, na home railu ni u TV laneu — a to je smisao
featurea.

**Posljedice:** cache je HTTP-level (`Cache-Control` na endpointu) umjesto CDN
immutable + `?v=` bucketa; app drži `PersonIndexCache` singleton po uzoru na
`channelCache`.

### O2 — Ruta i identitet

**Odluka:** **`/p/:slug` ostaje kanonska i jedina ruta.** Virtualni kanal je novi
*izgled* iste rute, ne nova ruta. Nema `/vk/:slug`, nema `/c/p-<slug>`, nema
redirecta.

**Obrazloženje:** `/p/` već ima OG inject, JSON-LD i `PersonScreen`, i pokriven je
AASA wildcardom i Android `pathPrefix="/p/"`. Kolizija slug pravila nestaje jer se
person slug nikad ne provlači kroz `-`→`_`. Već podijeljeni linkovi ostaju važeći.

**Odbačeno — `/c/p-<slug>`:** `/c/` grana bi `p-marijana-sarolic-robic` pretvorila
u `p_marijana_sarolic_robic` i pokušala dohvatiti nepostojeći
`channels/data/p_….json` → worker bi ionako trebao special-case, a dobili bismo
dvostruki URL za isti sadržaj (SEO duplikat).

**Odbačeno — `/vk/:slug`:** treći namespace slugova, nova OG grana, i po pravilu iz
CLAUDE.md nova javna content ruta mora u **oba** deep-link popisa. Trošak bez koristi.

### O3 — Pravilo uključivanja sadržaja

**Odluka:** automatski **sve epizode gdje je osoba diariziran govornik**, ali
podijeljene u dva tiera umjesto tvrdog praga:

- `primary` — `speaking_seconds / duration >= 0.15` **ILI** `speaking_seconds >= 300`
- `cameo` — sve ostalo

`episode_count` u herou i na kartici broji **samo `primary`**; `cameo` epizode žive
u zasebnoj sekciji „Kratki nastupi" na profilu. Faceta **„spominje se" NE ulazi u
kanal** — ostaje kao zasebna sekcija na hubu, nepromijenjena.

**Obrazloženje:** panel od 2 h s 3 minute govora ne smije izgledati kao njezina
epizoda, ali ni ne treba nestati. Dvorazinski prikaz čini hero brojku poštenom bez
skrivanja sadržaja. Spomeni ostaju izvan kanala jer je kanal „sadržaj **od** osobe",
a spomen je sadržaj **o** osobi; miješanje bi `video_count` pretvorilo u laž i
razbilo razliku govori-vs-spominje
(`docs/person-hub-feature-and-competitive-landscape.md` §3).

**Odbačeno — tvrdi prag koji izbacuje epizodu:** granica je arbitrarna, a
diarizacijski šum znači da bi se legitimni kratki samostalni nastupi (TEDx 9:53,
COTRUGLI 4:52 — oboje MSR) tiho gubili.

**Ručna kuracija:** nova PG tablica u `domovina-rag`:
`person_channel_overrides (slug, youtube_id, action ENUM('exclude','force_primary'), reason, created_at)`,
koju čita `get-person.ts`. Živi uz izvor istine — override u Flutteru ili u fetch
repou morao bi se ručno sinkronizirati s agregacijom i tiho bi se raspao.

### O4 — Unlisted epizode

**Odluka (vlasnikova):** uvrštavanje u virtualni kanal **promovira epizodu u
public**. Nema treće razine vidljivosti. Epizoda ulazi u pretragu, u sitemap i u
virtualni kanal; `_unlisted` prestaje značiti „skriveno" i znači samo „nema
praćeni matični kanal".

**Obrazloženje:** jedno stanje vidljivosti; svaka epizoda je snimka javno
objavljenog YouTube videa.

**Odbačeno — opt-in gate (unlisted dok osoba ne pristane):** odbačeno odlukom
vlasnika; posljedica je da pravna zaštita pada isključivo na tok iz O8.

**Ograda koju plan zadržava:** ad-hoc epizode **ne ulaze u
`channels/data/index.json`** — njihov izvorni kanal (N1, Lider, TEDxZagreb…) nije
praćen kanal i nema svoju `/c/` stranicu. Dostupne su kroz `/v/{id}`, kroz
virtualni kanal, kroz pretragu i kroz sitemap. `generate_channel_index.js:307`
ostaje nedirnut.

### O5 — Metapodaci kanala

**Odluka:**

| Polje | Izvor za osobu |
|---|---|
| `avatar_url` | ručno postavljena slika ako postoji; inače **monogram** (inicijali na navy gradijentu) |
| cover | **namjerno nema** — `hasBannerCover == false` |
| opis | deterministički iz agregata: „Gost u 17 epizoda na 17 kanala, 2020.–2026." |
| `follower_count` | **null i ne prikazuje se** |
| `avg_magisterium_score` | prosjek `magisterium_score` epizoda koje ga imaju; null ako nijedna |
| `total_duration_seconds` | zbroj trajanja `primary` epizoda |

**Obrazloženje:** izostanak cover-a je značajka, ne rupa — `ChannelCard` već ima
SQUARE layout za kanale bez banner cover-a (`channel_card.dart:145`), pa je to nula
novog layout koda i konzistentno s 14 postojećih kanala bez cover-a. Monogram
koristi isti gradijent kao `_avatarPlaceholder` (`channel_card.dart:175`), pa
kartica nikad ne izgleda prazno. Prazna Magisterium pilula se već graciozno ne
crta (`channel_card.dart:231`).

**Odbačeno — scrapeati YouTube avatar izvornog kanala:** to je avatar N1-a, ne
osobe; lažno bi sugerirao vezu s tim kanalom.

**Odbačeno — izmisliti `follower_count` iz broja pratitelja u appu:** brojka bez
značenja koju bi korisnik čitao kao YouTube pretplatnike.

### O6 — Pretraga, dijeljenje i SEO

**Odluka:**

- **Pretraga**: nova sekcija „Osobe" **iznad** rezultata u command palette,
  lokalni dijakritik-neosjetljiv prefix-match nad `PersonIndexCache` (isti
  `localMatchScore` iz `lib/utils/text_search.dart` koji `AllChannelsView` već
  koristi). `/api/search` se **ne dira**.
- **Share/OG**: `/p/` grana u workeru već postoji i radi; dopuna je samo da
  `og:image` prestane padati na generički `/og-image.png` kad postoji
  `persons/images/<slug>/avatar_square.png` na CDN-u. JSON-LD ostaje
  `ProfilePage`+`Person` (osoba nije `PodcastSeries`).
- **Sitemap**: uvodi se **dinamički `/sitemap.xml` u workeru**, generiran iz
  `channels/data/index.json` + `/api/persons` + epizoda, plus `Sitemap:` linija u
  `web/robots.txt`.

**Obrazloženje:** worker je ispravno mjesto po pravilu iz CLAUDE.md („čita CDN i
javni API, ne piše našu bazu"); statički sitemap bi zastario između deployeva.

**Odbačeno — dodati osobe u `/api/search` kao poseban tip rezultata:** search je
vektorski nad chunkovima; osobe su egzaktan lookup po imenu i lokalni match je
brži, jeftiniji i radi offline.

### O7 — Vlasništvo i monetizacija

**Odluka (vlasnikova):** **ništa u ovom krugu.** Nema person claima, nema pinka
kampanje za osobu, nema hooka u shemi. Virtualni kanal je čista prezentacija.

**Obrazloženje:** postojeći `channel_claim` tok dokazuje vlasništvo YouTube kanala
(`canonicalUcId` + `channels.list?mine=true`,
`lib/services/channel_ownership_service.dart`) — za osobu bez kanala tog dokaza
nema, a alternativa (Certilia eID/KYC) dodaje auth i plaćanja u prvi krug.

**Odbačeno — hook u shemi (`subject_type: person|youtube_channel`):** odbačeno
odlukom vlasnika. **Posljedica koju plan bilježi izrijekom:** kad se person claim
jednom poželi, tražit će migraciju `channel_claims` tablice i `PinkaCampaign`
subject modela. To je svjesno prihvaćen dug, ne previd.

### O8 — Pristanak osobe i pravo na uklanjanje

**Odluka (vlasnikova):** **opt-out.** Profil i virtualni kanal su javni po
defaultu; osoba dobiva obavijest i može tražiti uklanjanje.

**Tok:**

1. **Obavijest** — prije nego kanal postane javan, osobi se šalje poruka s punim
   popisom uvrštenih epizoda. Nacrt za MSR već postoji
   (`certilia-esign/podcast/MSR-OBRADENI-VIDEI.md`, sekcija „Nacrt poruke").
   Obavijest ne mijenja odluku o vidljivosti — samo je izvodi pristojno.
2. **Opt-out cijelog kanala** — `person_optouts (slug, scope='channel', created_at)`.
   Efekt: osoba nestaje iz `/api/persons`, s kartica, iz TV lanea i iz sitemapa.
   `/p/:slug` ostaje kao **minimalni profil** (ime + poruka o uklanjanju), ne 404 —
   404 bi razbio već podijeljene linkove.
3. **Uklanjanje pojedine epizode** — `person_channel_overrides.action='exclude'`.
   Epizoda nestaje iz kanala, `/v/{id}` ostaje (to je javni YouTube video).
4. **Tombstone** — opt-out zapis mora preživjeti ETL rerun; inače sljedeći ingest
   vraća osobu. Zato tablica, a ne ručno brisanje redova.
5. **Rok** — zahtjev se izvršava u ≤ 7 dana, uz CDN purge.

**Na što se oslanjamo:** svi izvori su javno objavljeni YouTube videi; ne
zaobilazimo nikakvu zaštitu pristupa, ne skidamo private/YT-unlisted snimke, ne
tvrdimo suradnju ni odobrenje osobe, i ne monetiziramo osobu (O7).

**Gdje je granica:** (a) nikad privatne ili YouTube-unlisted snimke bez pristanka
nositelja prava; (b) nikad tvrdnja tipa „službeni kanal osobe" — kartica i hero
moraju reći da je riječ o agregatu tuđih snimki; (c) zahtjev za uklanjanjem se ne
preispituje.

### O9 — Nastup na svim površinama

**Odluka:**

| Površina | Ponašanje |
|---|---|
| `/channels` | U istoj lazy listi, s filter chipovima **Sve / Kanali / Osobe**. Ulaze samo osobe s ≥ 3 `primary` epizode. |
| Home | **Novi horizontalni rail „Osobe"**, ne miješa se u postojeći kanalski prikaz. |
| Pretraga | Sekcija „Osobe" iznad rezultata (O6). |
| Android TV | Novi `TvPersonScreen` (tanak wrapper nad `TvChannelScreen` layoutom) + lane na TV home-u. |
| Mobitel | Ista `/p/` stranica u kanal-formi. |

**Vizualna razlika:** da, i to jednim potezom — **eyebrow tekst**. Kanal danas
prikazuje „KANAL · 12 EP · 8H" (`homeChannelCardMeta`); osoba prikazuje
„OSOBA · 17 EP · 13H 39M". Novi ARB ključ, ista tipografija, ista kartica.

**Obrazloženje:** razlika mora postojati jer virtualni kanal **nije** kanal koji
netko uređuje — ali mora biti tiha, jer feature je upravo u tome da osoba izgleda
ravnopravno s kanalom. Home dobiva rail, a ne uklapanje u kanalsku listu, jer je
home namjerno olakšan (`all_channels_screen.dart:14`).

### O10 — Praćenje i notifikacije

**Odluka:** novi `FollowService` s **jednim namespaceom** za kanale i osobe
(`person:<slug>`, `channel:<id>`), po uzoru na `FavoritesService`: localStorage
(`follows_v1`) na webu preko `lib/services/local_prefs.dart`, `SharedPreferences`
na nativeu, dual-write u `domovina_ai.follows` za prijavljene korisnike.

**Notifikacije: u prvom krugu nema pusha.** „Pratim" je izvor za home rail
**„Novo od praćenih"** — klijentski diff `latest_episode.date` iz person indeksa
naspram zadnje viđenog datuma u localStorage.

**Obrazloženje:** push traži server-side scheduler + APNs/FCM i pristanak na
notifikacije; rail daje 80 % vrijednosti isti dan. Shema `follows` push ne blokira.

**Odbačeno — proširiti `FavoritesService` na osobe:** favoriti su epizode s
vlastitom Supabase tablicom i migracijskim flagom; miješanje entiteta razbilo bi
`domovina_ai.favorites` ugovor i postojeći `migrateToSupabase` tok.

---

## 3. Faze

Svaka faza je jednodnevna i samostalno deployabilna. **F1–F2 su `domovina-rag`
(van opsega ovog tima).** F3–F7 su ovaj repo i razbijeni su u taskove T1–T7 niže.

### F1 — ETL: ad-hoc epizode u domovina-rag  *(drugi repo)*

**Cilj:** `/api/person/marijana-sarolic-robic` vraća 17 epizoda s ispravnim
izvornim kanalima.
**Dodirnute datoteke:** `domovina-rag/services/etl/etl/sources.py`,
`services/etl/etl/load.py`, `services/etl/tests/`.

**Ključni zahtjev:** kanal se **NE smije** zapisati kao `_unlisted`. Za svaku
epizodu iz `_unlisted` mapira se iz `info.json`: `channel_name = info.channel`,
`channel_youtube_id = info.channel_id`, `channel = slug(info.channel)` (ASCII-fold
+ razmak→`_`, kao postojeći channel id-evi: „Lider" → `lider`, „Centar Ignacije" →
`centar_ignacije`). Ako slug već postoji među praćenim kanalima → koristi postojeći
(`channel_tracked = true`), inače novi netracked zapis.

**Kriterij prihvaćanja:** `episode_count == 17`; 17 različitih `channel` vrijednosti;
nijedan nije `_unlisted`; `dDDwWZPVS0s` se **ne duplicira** (reuse kroz
`slijedi_svoj_poziv_2` ima prednost); `tomislav-belavic` također poraste
(regresijska provjera da mapiranje nije MSR-specifično).

### F2 — Backend: person index + kanal-metapodaci + override/optout  *(drugi repo)*

**Dodirnute datoteke:** `domovina-rag/services/mcp/src/public-api.ts`,
`services/mcp/src/tools/get-person.ts`, nova
`infra/postgres/migrations/006_person_channel.sql`.

Novo: `GET /api/persons` (shema §4.1, `Cache-Control: public, max-age=900`);
`/api/person/:slug` proširen aditivnim poljima (§4.2); `speaking_seconds` po
epizodi iz ClickHouse `rag_chunks`; tablice `person_channel_overrides` i
`person_optouts` (§4.3) primijenjene u agregaciji.

**Deploy:** `services/mcp/deploy.sh` (Coolify REST — nema push-webhooka).

### F3–F7 (ovaj repo)

F3 kanal-forma na `/p/` → **T2 + T3**; F4 katalog/pretraga → **T4**;
F5 Android TV → **T6**; F6 praćenje → **T5**; F7 SEO → **T7**.
i18n za sve njih je izdvojen u **T1**.

---

## 4. Ugovor podataka

### 4.1 `GET https://mcp.domovina.ai/api/persons`

```json
{
  "version": "1.0",
  "person_count": 2,
  "persons": [
    {
      "slug": "marijana-sarolic-robic",
      "name": "Marijana Šarolić Robić",
      "avatar_url": null,
      "episode_count": 17,
      "channel_count": 17,
      "total_duration_seconds": 49151,
      "avg_magisterium_score": null,
      "first_year": 2020,
      "last_year": 2026,
      "is_virtual_channel": true,
      "latest_episode": {
        "youtube_id": "bkp-0X4aG9E",
        "date": "2026-06-24",
        "title": "AI revolucija: Tko će biti građani drugog reda? | Marijana Šarolić Robić x Fintech Talks14"
      }
    },
    {
      "slug": "tomislav-belavic",
      "name": "Tomislav Belavić",
      "avatar_url": null,
      "episode_count": 6,
      "channel_count": 6,
      "total_duration_seconds": 0,
      "avg_magisterium_score": null,
      "first_year": 2024,
      "last_year": 2026,
      "is_virtual_channel": true,
      "latest_episode": {
        "youtube_id": "uixJ3kMd0XA",
        "date": "2026-06-18",
        "title": "Željka Markić & Narod.hr #156 - Tomislav Belavić"
      }
    }
  ]
}
```

`is_virtual_channel` je `episode_count(primary) >= 3 && !optout`. Osoba s manje
epizoda ostaje u `/api/person/:slug`, ali nije u ovom indeksu.

### 4.2 `GET /api/person/{slug}` — aditivna proširenja

Postojeća polja ostaju nepromijenjena (`name`, `slug`, `avatar_url`,
`channel_count`, `episode_count`, `channels[]`, `episodes[]`, `timeline[]`,
`mentions[]`, `mention_episode_count`, `mention_channels[]`, `mention_timeline[]`).

Novo na korijenu:

```json
{
  "is_virtual_channel": true,
  "total_duration_seconds": 49151,
  "avg_magisterium_score": null,
  "first_year": 2020,
  "last_year": 2026,
  "cameo_episode_count": 0,
  "optout": false
}
```

Novo po zapisu u `episodes[]` (i u novom `cameo_episodes[]`, iste sheme):

```json
{
  "youtube_id": "bkp-0X4aG9E",
  "title": "AI revolucija: Tko će biti građani drugog reda? | Marijana Šarolić Robić x Fintech Talks14",
  "channel": "lider",
  "channel_name": "Lider",
  "channel_youtube_id": "UCboxxQjTe6vkiny3mkIo_BQ",
  "channel_tracked": false,
  "upload_date": "2026-06-24",
  "duration_seconds": 1667,
  "speaking_seconds": 612,
  "speaking_share": 0.367,
  "tier": "primary",
  "magisterium_score": null,
  "first_ts": 42,
  "deep_link": "https://domovina.ai/v/bkp-0X4aG9E/t/42"
}
```

Još dva stvarna primjera (`speaking_seconds`/`first_ts` su **ilustrativni** —
mjeri ih F2; sve ostalo je provjereno s CDN-a i iz kataloga):

```json
{
  "youtube_id": "AVsBPQ7iLSQ",
  "title": "N1 podcast: Kritičko mišljenje i umjetna inteligencija",
  "channel": "n1", "channel_name": "N1",
  "channel_youtube_id": "UCpglal7d5mhV4lA1b3-DsCw",
  "channel_tracked": false,
  "upload_date": "2022-04-01", "duration_seconds": 3076,
  "tier": "primary", "deep_link": "https://domovina.ai/v/AVsBPQ7iLSQ"
}
```
```json
{
  "youtube_id": "dDDwWZPVS0s",
  "title": "Kako voditi u svijetu umjetne inteligencije? | Marijana Šarolić Robić | SSP",
  "channel": "slijedi_svoj_poziv_2",
  "channel_name": "Slijedi svoj poziv — 2. konferencija o liderstvu",
  "channel_youtube_id": "UCuk9D5H9mx7birJ1-S22nyQ",
  "channel_tracked": true,
  "upload_date": "2026-02-13", "duration_seconds": 1038,
  "tier": "primary", "first_ts": 3,
  "deep_link": "https://domovina.ai/v/dDDwWZPVS0s/t/3"
}
```

**Kontrolni zbroj za F1:** 17 epizoda, 17 različitih `channel` vrijednosti, zbroj
`duration_seconds` = **49 151** (13 h 39 min 11 s), točno jedan zapis s
`channel_tracked: true`.

### 4.3 PG sheme (F2, drugi repo)

```sql
CREATE TABLE person_channel_overrides (
  slug        TEXT NOT NULL,
  youtube_id  TEXT NOT NULL,
  action      TEXT NOT NULL CHECK (action IN ('exclude','force_primary')),
  reason      TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (slug, youtube_id)
);

CREATE TABLE person_optouts (
  slug         TEXT PRIMARY KEY,
  scope        TEXT NOT NULL DEFAULT 'channel' CHECK (scope IN ('channel')),
  requested_by TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Obje su **tombstone** tablice — moraju preživjeti ETL rerun.

---

## 5. Rizici i zamke

| Rizik | Zašto boli | Mitigacija |
|---|---|---|
| **Scroll-perf `/channels`** | 48 kanala + N osoba u istoj listi; home je već jednom morao izbaciti eager renderiranje zbog janka na skwasmu | Lista je već lazy `SliverList`; osobe ulaze tek s ≥ 3 epizode; ako broj osoba prijeđe ~50, filter chip postaje default „Kanali". **Izmjeriti** na web buildu prije mergea T4. |
| **Service worker / cache** | SW je aktivan (iOS PWA background audio); novi bundle + nove rute | `./scripts/deploy.sh` radi purge; `/api/persons` ide preko `mcp.domovina.ai` (izvan SW scopea). Nakon ETL reruna profil se ne osvježi do **900 s** — za demo hard refresh. |
| **Kolizija slugova** | Dvije osobe s istim ASCII-folded imenom danas tiho dijele profil | F2 vraća `ambiguous: true` kad jedan slug pokriva > 1 `canonical_name`; tada se kanal-forma **ne** aktivira. Frontend to mora poštovati (T2). |
| **ASCII-fold mismatch** | ASR piše „Mić" umjesto „Mič" → epizoda ne uđe ili uđe kriva | Postojeći `speakers.aliases[]` mehanizam se nasljeđuje; greška sad ima veću cijenu (tuđa epizoda u nečijem kanalu) → `exclude` override + vidljiv „Prijavi grešku" na svakoj epizodi u kanalu (T3). |
| **Lažno pripisivanje govornika** | Loša diarizacija stavi tuđu epizodu u nečiji kanal — reputacijski problem | Tier prag ne pomaže kod krive atribucije; obrana je `exclude` override + ručni pregled prvih virtualnih kanala prije javne objave. |
| **Pravni (O8, opt-out)** | Profil se gradi od tuđih snimki, javno po defaultu | Obavijest prije objave; tombstone opt-out; nikad tvrdnja „službeni kanal"; nikad private/YT-unlisted izvori; izvršenje zahtjeva ≤ 7 dana. |
| **`web/_worker.js` kao usko grlo** | Sve rute na jednom mjestu | T7 se **ne** paralelizira ni s jednim drugim taskom. |
| **`app_hr.arb` / `app_en.arb`** | Diralo bi ih T3, T4, T5, T6 | Zato je **T1** jedini task koji dira ARB i ide prvi. |
| **`is_virtual_channel` prag mijenja katalog tiho** | Osoba uđe/izađe iz kataloga kad joj se doda 3. epizoda | Prihvatljivo; F2 logira koje su osobe prešle prag. |

---

## 6. Testiranje

**Unit (`test/`)** — postoji `person_hub_test.dart`, proširiti:
- `personSlug()` fold nad rubnim slučajevima („Šarolić Robić", „Mič"/„Mić")
- tier klasifikacija (`primary`/`cameo`) na graničnim vrijednostima 0,15 i 300 s
- `PersonIndex.fromJson` + graceful parse kad polja nedostaju (stari backend)
- `FollowService` key namespace (`person:` vs `channel:`); web putanja koristi
  `local_prefs`, ne `SharedPreferences`
- sitemap XML escape (imena kanala sadrže `&` i dijakritike)

**E2E (`e2e/flutter-web.spec.mjs`, Playwright)**:
- `/p/marijana-sarolic-robic` → hero prikazuje 17 epizoda
- `/channels` → chip „Osobe" filtrira listu; klik na karticu vodi na `/p/`
- praćenje preživi reload
- `/sitemap.xml` sadrži `/p/marijana-sarolic-robic`

**Nova `Semantics(identifier:)` sidra** (uz `?a11y=1`, `docs/e2e-testing.md`):
`person-hero`, `person-episode-count`, `person-episodes-primary`,
`person-episodes-cameo`, `person-follow-button`, `person-card-<slug>`,
`channels-filter-persons`, `home-persons-rail`.

---

## 7. Rollout

**Feature flag:** `PersonChannelFlag` — čita `?vk=1` iz URL-a i pamti u
localStorage (web) / `SharedPreferences` (native). **Runtime**, ne compile-time,
jer je web jedan bundle za sve. Default **OFF** dok T4 ne prođe review; T2/T3 se
do tada testiraju samo s `?vk=1`.

**Redoslijed deploya:**

1. `domovina-rag` F1 (ETL run) → provjeri kontrolni zbroj iz §4.2
2. `domovina-rag` F2 (`services/mcp/deploy.sh`) → aditivno, stari app ne primjećuje
3. `domovina.ai` T1–T3 (`./scripts/deploy.sh`) → flag OFF, verifikacija s `?vk=1`
4. `domovina.ai` T4 → flag ON
5. T5, T6, T7 nezavisno

**Rollback:**
- T2–T7: **flag OFF bez redeploya** (localStorage/URL), pa `./scripts/deploy.sh` s
  prethodnim commitom ako treba trajno
- F2: revert MCP servisa preko `services/mcp/deploy.sh`; nova su polja aditivna pa
  stari frontend radi s novim backendom i obratno
- F1: opt-out/override tablice su tombstone i **ne** brišu se pri rollbacku

---

## 8. Otvorena pitanja za čovjeka

1. **Prag „glavnog nastupa"** — 15 % trajanja ILI 300 s. Blokira F2 i time izgled
   svakog kanala. *Preporuka: krenuti s tim, pa kalibrirati na MSR-ovih 17 epizoda
   gdje je raspon 4:52 – 2:02:59.*
2. **Minimalni broj epizoda za katalog** — predlažem **3** `primary` epizode.
   Blokira T4 i određuje koliko osoba odmah osvane u `/channels`.
3. **Prije nego MSR kanal ode javno** — šalje li se nacrt poruke iz
   `MSR-OBRADENI-VIDEI.md` i čeka odgovor, ili kanal ide javno odmah po F1?
   Blokira javnu vidljivost, ne sam ETL run.
   **Dopuna iz reviewa r3:** prije nego F2 počne isporučivati `avatar_url`,
   TV putanja `PersonMonogram`-a mora prijeći na `CachedThumbnail` (danas
   `Image.network`, mrtva putanja dok je avatar null). Uz to, rubni slučaj:
   gašenje flaga dok je aktivan filter „Osobe" u `/channels` ostavlja praznu
   listu do reloada — reset `_filter` na `all` u `_onFlagChanged`.
4. **Avatar** — smijemo li koristiti kadar iz videa (postojeći screenshot s CDN-a)
   kao avatar osobe, ili samo monogram dok osoba ne pošalje sliku? Blokira T3/T7
   vizualno, ne funkcionalno.
5. **Tko piše `person_channel_overrides`** — admin UI u `pipeline.domovina.ai`
   (već ima Basic Auth admin) ili ručni SQL zasad? Ne blokira F2, blokira
   operativno korištenje. **Dopuna iz reviewa r2 (28.07.2026.):** „Prijavi
   grešku" u T3 trenutno završava samo u `log()` + snackbar — dojava ne stiže
   do nas. Mora dobiti odredište **prije nego flag ode ON** (vezano uz ovo
   pitanje); do tada je mitigacija iz tablice rizika neaktivna.

---

# Taskovi

> Svi taskovi rade **protiv ugovora iz §4** koji backend (F1/F2) tek isporučuje.
> Zato je **graceful degradacija obavezna**: sva nova polja parsiraju se kao
> nullable s fallbackom na današnje ponašanje, po uzoru na
> `PersonHub.fromJson` (`lib/models/person_hub.dart:158`). Dev NE čeka backend i
> NE mijenja ništa u `domovina-rag`.
>
> **PROVJERITI (prvi korak svakog UI taska):** vraća li `/api/persons` već 200.
> Ako ne (očekivano dok F2 ne ode), radi protiv fixture JSON-a u `test/fixtures/`
> i drži UI iza `PersonChannelFlag`.

### T1 — i18n: svi novi ključevi odjednom

- **Fajlovi**: `lib/l10n/app_hr.arb`, `lib/l10n/app_en.arb`
- **Opis**: dodaj SVE nove stringove koje traže T2–T7, u jednom potezu, pa
  `flutter gen-l10n`. Minimalni popis (imenovanje `person*` / `channel*` / `common*`):
  - `personCardMeta(episodeCount, duration)` → „OSOBA · {n} EP · {duration}" (ICU
    plural za „epizoda"), pandan postojećem `homeChannelCardMeta`
  - `personVirtualChannelSubtitle(episodes, channels, fromYear, toYear)` →
    „Gost u {e} epizoda na {c} kanala, {from}.–{to}."
  - `personSectionEpisodes` („Epizode"), `personSectionCameo` („Kratki nastupi"),
    `personSectionCameoHint` (jedna rečenica što je kratki nastup)
  - `personSourceChannelUntracked` (tooltip: kanal nije praćen, nema stranicu)
  - `personReportError` („Prijavi grešku"), `personOptedOut` (tekst minimalnog
    profila nakon opt-outa)
  - `personFollow` / `personFollowing`, `channelFollow` / `channelFollowing`
  - `channelsFilterAll` / `channelsFilterChannels` / `channelsFilterPersons`
  - `homePersonsRailTitle` („Osobe"), `homeFollowedRailTitle` („Novo od praćenih")
  - `searchSectionPeople` („Osobe")
- **Definicija gotovog**: `flutter gen-l10n` prolazi, `flutter analyze` čist,
  nula ALL-CAPS vrijednosti u ARB-u (caps se radi u kodu preko `.toUpperCase()`),
  ispravni dijakritici i registar „ti".
- **Izvedeno (28.07.2026., odstupanja od popisa)**: `personCardMeta` prati oblik
  `homeChannelCardMeta` („Osoba · {count} ep · {duration}"; puni plural postoji
  kao `personEpisodesCount`); podnaslov rodno neutralan („Gostuje u…"); godine su
  String placeholderi (protiv `NumberFormat` „2.026"). Dodatni ključevi:
  `personVirtualChannelSubtitleOneYear`, `personReportErrorThanks`,
  `tvRailPersons`, te `personSectionEpisodes` uz zadržani
  `personEpisodesHeading` za prikaz bez flaga.

### T2 — Model, servis i index cache

- **Fajlovi**: `lib/models/person_hub.dart`, `lib/services/person_service.dart`,
  `lib/services/person_index_cache.dart` (novi),
  `lib/services/person_channel_flag.dart` (novi),
  `test/person_hub_test.dart`, `test/person_index_test.dart` (novi),
  `test/fixtures/person_marijana.json` (novi),
  `test/fixtures/persons_index.json` (novi)
- **Opis**: proširi `PersonEpisode` i `PersonHub` aditivnim poljima iz §4.2
  (`channelName`, `channelYoutubeId`, `channelTracked`, `durationSeconds`,
  `speakingSeconds`, `speakingShare`, `tier`, `magisteriumScore`,
  `isVirtualChannel`, `totalDurationSeconds`, `avgMagisteriumScore`, `firstYear`,
  `lastYear`, `cameoEpisodes`, `cameoEpisodeCount`, `optout`, `ambiguous`).
  Dodaj `PersonIndex`/`PersonSummary` model za §4.1, `PersonService.loadIndex()`
  i `PersonIndexCache` singleton po uzoru na `channelCache`
  (`lib/services/channel_cache.dart`). `PersonChannelFlag`: `?vk=1` → localStorage
  na webu / `SharedPreferences` na nativeu, default OFF.
- **Definicija gotovog**: fixture iz §4 parsira se bez gubitka; **stari** odgovor
  (bez ijednog novog polja) parsira se u današnje ponašanje bez iznimke;
  `durationDisplay` za 49151 s daje „13h 39m"; `ambiguous: true` gasi
  `isVirtualChannel`; novi testovi prolaze; `flutter analyze` čist.

### T3 — Kanal-forma na `/p/:slug`

- **Fajlovi**: `lib/screens/person/person_screen.dart`,
  `lib/widgets/person_monogram.dart` (novi)
- **Opis**: kad je `isVirtualChannel && PersonChannelFlag.on`, hero postaje
  kanal-oblika: monogram avatar (isti gradijent kao `_avatarPlaceholder` u
  `lib/screens/home/channel_card.dart:175`), ime, `personCardMeta` eyebrow,
  deterministički podnaslov. Popis epizoda se dijeli na „Epizode" (`primary`) i
  „Kratki nastupi" (`cameo`); sekcija „Spominje se u" ostaje **nepromijenjena**.
  Chip izvornog kanala linka na `/c/<slug>` **samo kad je `channelTracked == true`**
  — inače neklikabilan tekst s tooltipom. Uz svaku epizodu „Prijavi grešku".
  Kad je `optout == true` → minimalni profil (ime + poruka), ne 404.
  Dodaj `Semantics(identifier:)`: `person-hero`, `person-episode-count`,
  `person-episodes-primary`, `person-episodes-cameo`.
- **Definicija gotovog**: `/p/marijana-sarolic-robic?vk=1` prikazuje kanal-hero;
  bez `?vk=1` ekran izgleda točno kao danas; N1/Lider chipovi nisu klikabilni;
  `flutter analyze` čist. Padding scrollabilnih sekcija ide `padding:` parametrom
  na listu, ne wrapperom.

### T4 — Katalog: `/channels` filter, home rail, pretraga

- **Fajlovi**: `lib/screens/channels/all_channels_screen.dart`,
  `lib/screens/home/person_card.dart` (novi),
  `lib/screens/home/persons_rail.dart` (novi),
  `lib/screens/home/home_screen.dart`,
  `lib/screens/home/search_overlay.dart` *(ispravak iz reviewa r3: plan je
  krivo naveo `meili_search_screen.dart` — to je lokalni Meilisearch PoC;
  command palette iz O6 živi u `search_overlay.dart`)*
- **Opis**: filter chipovi Sve/Kanali/Osobe u `AllChannelsView` (lista ostaje lazy
  `SliverList`, osobe ulaze samo s `isVirtualChannel`). `PersonCard` je **novi**
  fajl koji reproducira SQUARE layout `ChannelCard`-a — `channel_card.dart` se
  **NE dira** (izolacija od T3/T6). Home dobiva horizontalni rail „Osobe" (rail
  padding UNUTAR liste; `ScrollConfiguration` s `dragDevices` za miša). Pretraga
  dobiva sekciju „Osobe" iznad rezultata, `localMatchScore` iz
  `lib/utils/text_search.dart` nad `PersonIndexCache`. Sve iza `PersonChannelFlag`.
  Sidra: `channels-filter-persons`, `home-persons-rail`, `person-card-<slug>`.
- **Definicija gotovog**: s `?vk=1` filter „Osobe" prikazuje samo osobe, „Kanali"
  nijednu; klik vodi na `/p/:slug`; upit „sarolic" i „šarolić" oba vraćaju osobu;
  bez flaga sve izgleda kao danas; `flutter analyze` čist.
  **Izmjeriti scroll `/channels` na web buildu** i zapisati nalaz u sažetak.

### T5 — Praćenje (`FollowService` + gumbi)

- **Fajlovi**: `lib/services/follow_service.dart` (novi),
  `test/follow_service_test.dart` (novi),
  `lib/screens/person/person_screen.dart`,
  `lib/screens/channel/channel_screen.dart`,
  `lib/screens/home/followed_rail.dart` (novi),
  `lib/screens/home/home_screen.dart`
- **Opis**: `FollowService` po uzoru na `lib/services/favorites_service.dart`
  (localStorage `follows_v1` na webu preko `local_prefs.dart`, `SharedPreferences`
  na nativeu, fire-and-forget remote sync za prijavljene). Jedan namespace:
  `person:<slug>` i `channel:<id>`. Gumb „Prati" na oba ekrana. Rail „Novo od
  praćenih" na home-u: klijentski diff `latest_episode.date` naspram zadnje
  viđenog datuma u localStorage. Sidro `person-follow-button`.
  **RIJEŠENO (28.07.2026., vlasnik provjerio u `domovina-api` shemi):** tablica
  `domovina_ai.follows` **NE postoji** — remote sync ostaje no-op, lokalno
  praćenje mora raditi bez nje. Migracija je zaseban issue
  `domovinatv/domovina-api#3`; dev je **NE radi**.
- **Definicija gotovog**: praćenje preživi reload na webu bez ijednog poziva
  `SharedPreferences`; anonimni korisnik ostaje lokalno; testovi prolaze;
  `flutter analyze` čist.

### T6 — Android TV

- **Fajlovi**: `lib/screens/tv/tv_person_screen.dart` (novi),
  `lib/screens/tv/tv_home_screen.dart`, `lib/router/app_router.dart`
- **Opis**: TV grana za `/p/:slug` (danas je nema — ruta na TV-u renderira
  desktop `PersonScreen`). `TvPersonScreen` posuđuje layout iz
  `lib/screens/tv/tv_channel_screen.dart`, thumbnaili kroz `CachedThumbnail`.
  Lane „Osobe" na TV home-u iza `PersonChannelFlag`.
- **Definicija gotovog**: s `FORCE_TV` na Chromeu `/p/<slug>?vk=1` daje 10-foot
  layout, D-pad prolazi kroz epizode i lane; `flutter analyze` čist.
  `Focus.onKeyEvent` handleri imaju `hasPrimaryFocus` guard.

### T7 — SEO: `sitemap.xml` + OG avatar

- **Fajlovi**: `web/_worker.js`, `web/robots.txt`
- **Opis**: nova `/sitemap.xml` grana u workeru — `/`, `/channels`, sve `/c/<slug>`
  iz `channels/data/index.json`, sve `/p/<slug>` iz `/api/persons`, i `/v/<id>`
  epizode. XML escape obavezan (imena sadrže `&` i dijakritike). `Cache-Control`
  kao ostale worker HTML rute (`s-maxage=3600`). U `robots.txt` dodaj
  `Sitemap: https://domovina.ai/sitemap.xml`. U `injectPersonTags` (`:692`):
  `og:image` koristi `persons/images/<slug>/avatar_square.png` s CDN-a kad postoji
  (`headOk` helper već postoji u fajlu), inače današnji fallback.
- **Definicija gotovog**: `curl https://domovina.ai/sitemap.xml` (nakon deploya)
  vraća validan XML; `node scripts/test-social-tags.mjs` prolazi; grana ne mijenja
  nijednu postojeću rutu.

---

## Ovisnosti

```
Krug 1:  T1 ‖ T2          (ARB vs modeli/servisi — disjunktno)
Krug 2:  T3 ‖ T7          (person_screen vs worker — disjunktno)
Krug 3:  T4 ‖ T6          (katalog/home/search vs TV/router — disjunktno)
Krug 4:  T5               (dira person_screen.dart i home_screen.dart — serijski)
```

- `T1 → T3, T4, T5, T6` — svi UI taskovi troše ARB ključeve iz T1.
- `T2 → T3, T4, T6` — svi troše proširen model i `PersonIndexCache`.
- **`T3 → T5`**: oba diraju `lib/screens/person/person_screen.dart` — **NE smiju
  ići istovremeno**.
- **`T4 → T5`**: oba diraju `lib/screens/home/home_screen.dart` — **NE smiju ići
  istovremeno**.
- **T7 je jedini task koji dira `web/_worker.js`** — ne paralelizirati ga ni s
  čim što dira taj fajl (u ovom krugu nema drugoga, ali pravilo vrijedi za dopune).
- `T1` je jedini task koji smije dirati `lib/l10n/*.arb`.

## Rizik

**Ukupno: srednji.**

- `T7` je **visok** — dira `web/_worker.js` (sve rute na jednom mjestu, izričito na
  listi visokog rizika). Orkestrator neka reviewera digne na Opus za T7.
- `T5` je **srednji** — dodiruje Supabase pisanje (`domovina_ai.follows`) i
  perzistenciju na webu (klasična zamka `SharedPreferences`).
- `T1`–`T4`, `T6` su **niski** — prezentacija iza feature flaga, bez auth,
  plaćanja, sheme i deploy putanje.

Feature je cijelim opsegom iza `PersonChannelFlag` (default OFF), pa je i najgori
ishod jednog kruga nevidljiv korisniku dok se flag ne upali.

## Verifikacija

- `flutter analyze` mora biti **čist** nakon svakog taska.
- Ciljani testovi: `flutter test test/person_hub_test.dart test/person_index_test.dart
  test/follow_service_test.dart`.
- **Napomena za reviewera:** `test/widget_test.dart` (HttpClient smoke) i
  `test/home_feed_test.dart` (datum-ovisan) padaju i na čistom mainu — to **nisu**
  regresije. Provjeri stash-om prije nego proglasiš regresiju.
- Ručna provjera u appu (`flutter run -d chrome` s `--dart-define` iz `.env`,
  port 5173):
  - `/p/marijana-sarolic-robic?vk=1` — kanal-hero, dvije sekcije epizoda, chip
    „N1" nije klikabilan
  - `/p/marijana-sarolic-robic` (bez flaga) — izgleda točno kao prije
  - `/channels?vk=1` — filter chipovi rade, klik na osobu vodi na `/p/`
  - `/?vk=1` — rail „Osobe" scrolla do ruba ekrana (padding unutar liste)
  - TV: `FORCE_TV=1` + `/p/<slug>?vk=1` — D-pad navigacija
- Do isporuke F1/F2 backend vraća stari oblik; **svaki task mora raditi i tada**
  (graceful degradacija je dio definicije gotovog, ne nice-to-have).

## Van opsega

- **F1 i F2 (`domovina-rag`)** — ETL run nad `_unlisted`, `/api/persons` endpoint,
  `speaking_seconds`, PG migracije. Drugi repo, drugi deploy (`services/mcp/deploy.sh`,
  Coolify REST). Tim iz ovog repoa ih **ne** dira. Praćenje:
  `domovinatv/domovina-rag#4` (sub-issue na #2).
- **`domovina_ai.follows` migracija** — `domovinatv/domovina-api#3` (sub-issue
  na #2); T5 radi s no-op remote syncom.
- **`fetch.domovina.tv`** — `generate_channel_index.js:307` (`_` prefiks) ostaje
  nedirnut; ad-hoc epizode namjerno ne ulaze u `channels/data/index.json`.
- **Vlasništvo i monetizacija** (O7) — nema person claima, nema pinka kampanje za
  osobu, nema hooka u shemi.
- **Push notifikacije** (O10) — samo home rail, bez APNs/FCM.
- **Generiranje avatara/OG slika za osobe** — T7 samo *koristi*
  `persons/images/<slug>/avatar_square.png` ako postoji; produkcija te slike je
  posao `fetch.domovina.tv`.
- **Deploy i commit** — orkestratorov posao, ne devov.
