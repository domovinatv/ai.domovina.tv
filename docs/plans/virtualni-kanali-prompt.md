Isplaniraj feature **„virtualni kanali"** za DOMOVINA.ai. **Ne implementiraj ništa** — ovaj zadatak završava planom, bez ijedne promjene koda. Radi u plan modu.

## Problem

Gost poput odvjetnice Marijane Šarolić Robić nema svoj kanal. Ona gostuje po tuđim YouTube kanalima — N1, Lider (Fintech Talks), LeaderSHE, HDS ZAMP, IUS-INFO, MBA Croatia, TEDxZagreb, Poslovni dnevnik, SLO-CRO komora, COTRUGLI, Poduzetnički Mindset, Biznis World, MTG ZIP, Global Thinkers Forum, KnowING IPR, Centar Ignacije. Za nju smo 27.–28.07.2026. kroz `pipeline.domovina.ai` ad-hoc obradili **17 snimki (13 h 39 min)**; sve su prošle puni pipeline, ali stoje kao **unlisted** stranice `domovina.ai/v/{id}` i **ne pripadaju nijednom kanalu** — nisu u katalogu, nisu u indeksu kanala, nema ih na Android TV-u, ne mogu se pratiti.

Cilj featurea: **osoba postaje kanal**. Virtualni kanal je kanal-oblika površina čiji je izvor sadržaja osoba (njezini nastupi kroz sve kanale), a ne YouTube kanal.

## Prvo pročitaj postojeće stanje (i u planu se referiraj na konkretne datoteke)

Već postoji **Person Hub** i plan mora krenuti od njega, ne ispočetka:

- `docs/person-hub-feature-and-competitive-landscape.md` — izvor istine za feature; dvije facete („govori u" iz diariziranih govornika vs „spominje se u" iz `mentioned_people` u `summary.json`), tok podataka, pravilo ASCII-folda za slugove (`č/ć→c`, `š→s`, `ž→z`, `đ→d`).
- `lib/router/app_router.dart` — rute: `/c/:slug` (kanal; slug se pretvara `-`→`_` u channel id), `/p/:slug` (person hub; slug se koristi **doslovno**, bez pretvorbe), `/channels`, pinka kampanje.
- `lib/services/person_service.dart` — `GET https://mcp.domovina.ai/api/person/{slug}`, bez autha, `Cache-Control: max-age=300`, graceful null na 404/timeout.
- `lib/models/person_hub.dart`, `lib/screens/person/person_screen.dart`, `lib/widgets/person_needle_highlight.dart`.
- Kanalska strana: `lib/models/channel_index.dart` (`/channels/data/index.json`: id, name, avatar_square, avatar_cover, youtube_channel_id, follower_count, video_count, total_duration_seconds, avg_magisterium_score, latest_video), `lib/models/channel_detail.dart`, `lib/services/channel_cache.dart`, `lib/screens/channel/channel_screen.dart`, `lib/screens/channels/all_channels_screen.dart`, `lib/screens/home/channel_card.dart`.
- Android TV: `lib/screens/tv/tv_channel_screen.dart`, `lib/screens/tv/widgets/tv_channel_card.dart`.
- Vlasništvo i monetizacija kanala: `lib/screens/ownership/*`, `lib/models/channel_claim.dart`, `lib/services/channel_ownership_service.dart`, `docs/channel-ownership-and-safe-payout-plan.md`, pinka SDK u `lib/pinka_sdk/`.
- `CLAUDE.md` — zamke koje plan mora poštovati: nikad `SharedPreferences` na webu (localStorage preko `package:web`), `docs/web-delivery-and-rendering.md` (service worker staleness, cache-busting, **scroll-perf liste kanala** — zato je popis svih kanala i izdvojen na zaseban ekran), `docs/e2e-testing.md` i pravilo oko `ensureSemantics`/`?a11y=1`, deploy kroz `./scripts/deploy.sh` uz CDN purge.

Granice repozitorija (plan mora eksplicitno reći **što ide u koji repo**):

- `domovina.ai` (ovaj repo) — **samo prezentacija**; sve se učitava s `cdn.domovina.ai` i s `mcp.domovina.ai`.
- `domovina-rag` — ETL i person API (`/api/person/:slug`), speakers + person_mentions.
- `fetch.domovina.tv` — pipeline koji proizvodi artefakte (`summary.json`, `article.json`, `article.magisterium.json`) i generira `channels/data/index.json`; `_`-prefiks kanala = neindeksirano.
- `pipeline.domovina.ai` — ad-hoc queue za pojedinačne videe (`/v/{id}`, `visibility=unlisted`), Magisterium korak 8.5.

## Što plan mora riješiti

Za svaku točku traži **odluku s obrazloženjem i alternativom koja je odbačena**, ne popis opcija:

1. **Definicija virtualnog kanala.** Je li to (a) nova vrsta zapisa u `channels/data/index.json` uz `type: virtual|youtube`, (b) zaseban indeks (`persons/data/index.json`) koji se u UI-ju spaja s kanalima, ili (c) samo „promocija" postojeće `/p/:slug` stranice u kanalsku vizualnu formu bez novog indeksa? Posljedice po cache, scroll-perf liste, TV i pretragu.
2. **Ruta i identitet.** Ostaje li `/p/:slug` kanonska ruta, dolazi li `/c/p-<slug>`, ili nova `/vk/:slug`? Riješi koliziju pravila slugova (`/c/` radi `-`→`_`, `/p/` ne radi ništa) i redirecte za već podijeljene linkove.
3. **Pravilo uključivanja sadržaja.** Automatski svi nastupi gdje je osoba diariziran govornik? Prag (npr. minimalno trajanje govora ili udio u epizodi) da panel od 2 h u kojem ima 3 minute ne izgleda kao njezina epizoda? Ulazi li faceta „spominje se" u kanal ili ostaje samo na hubu? Postoji li ručna kuracija (uključi/isključi epizodu) i gdje živi taj popis.
4. **Unlisted epizode.** 17 Marijaninih snimki je `visibility=unlisted` (dostupne samo preko linka, izvan kataloga). Virtualni kanal ih po definiciji izlaže. Odluči: promovira li se video u `public` pri uvrštavanju, ostaje li kanal sam neindeksiran, ili se uvodi treća razina vidljivosti. Ovo je istovremeno pravna i proizvodna odluka — poveži je s točkom 8.
5. **Metapodaci kanala.** Odakle avatar, cover, opis, broj pratitelja i `avg_magisterium_score` za osobu koja nema YouTube kanal? Što se prikazuje na `channel_card` i TV kartici da ne izgleda prazno.
6. **Pretraga, dijeljenje i SEO.** Kako virtualni kanal ulazi u `/api/search`, u OG injection Workera (share preview) i u sitemap; što se događa s epizodama koje su neindeksirane.
7. **Vlasništvo i monetizacija.** Može li osoba **claimati** svoj virtualni kanal (postojeći `channel_claim` tok je vezan uz dokaz vlasništva YouTube kanala — za osobu tog dokaza nema)? Smije li imati pinka kampanju? Ako da, tko je primatelj sredstava. Ako ne sada — koji je minimalni hook da se kasnije doda bez migracije.
8. **Pristanak osobe i pravo na uklanjanje.** Profil se gradi od tuđih snimki. Definiraj tok: obavijest osobi, opt-out cijelog kanala, uklanjanje pojedine epizode, i što ostaje na `/p/:slug` nakon opt-outa. Navedi na koje se osnove oslanjamo (javno dostupan sadržaj, YouTube ToS) i gdje je granica.
9. **Nastup na svim površinama.** Home, `/channels`, pretraga, Android TV lane, mobitel — gdje se virtualni kanali pojavljuju i jesu li vizualno razlikovani od pravih kanala (i zašto tako).
10. **Praćenje i notifikacije.** Kako se „prati" osoba, gdje se stanje sprema (web: localStorage, ne SharedPreferences), i što se događa kad se pojavi nova epizoda u kojoj gostuje.

## Format isporuke

Napiši **`docs/plans/virtualni-kanali.md`** (novi direktorij `docs/plans/` je prazan — ovo mu je prvi stanovnik) sa sljedećim:

1. **Sažetak stanja** — što već postoji (Person Hub) i što featureu stvarno nedostaje, s referencama na datoteke/linije.
2. **Odluke** — točke 1–10 gore, svaka: odluka, obrazloženje, odbačena alternativa.
3. **Faze**, svaka izvediva u jednom danu i samostalno deployabilna: cilj faze, dodirnute datoteke po repozitoriju, ulazni/izlazni artefakti (JSON sheme s primjerom), kriterij prihvaćanja.
4. **Ugovor podataka** — konkretna JSON shema za sve novo (indeks, detalj, API odgovor), s primjerom popunjenim **stvarnim podacima za Marijanu** (17 epizoda, 16 kanala, 13 h 39 min; primjeri: `domovina.ai/v/bkp-0X4aG9E`, `/v/AVsBPQ7iLSQ`, `/v/dDDwWZPVS0s`).
5. **Rizici i zamke** — barem: scroll-perf liste kanala, service worker/cache purge, kolizija slugova, ASCII-fold mismatch (ASR piše „Mić" umjesto „Mič"), lažno pripisivanje govornika kod loše diarizacije, i pravni rizik iz točke 8.
6. **Testiranje** — što ide u unit, što u `e2e/` (Playwright), koja `Semantics(identifier:)` sidra treba dodati.
7. **Rollout** — feature flag, redoslijed deploya po repozitorijima, kako se radi rollback.
8. **Otvorena pitanja za čovjeka** — najviše 5, poredana po tome koliko blokiraju.

## Način rada

- Prvo pročitaj navedene datoteke i **sažmi mi stanje u 10 rečenica** prije nego napišeš plan.
- Ako ti neka odluka bitno mijenja opseg (posebno točke 4, 7 i 8), pitaj **prije** pisanja plana, u jednom potezu, s preporukom.
- Ne piši kod, ne diraj `lib/`, ne otvaraj branch. Jedini artefakt je `docs/plans/virtualni-kanali.md`.
- Sve na hrvatskom, kao i ostatak repoa.
