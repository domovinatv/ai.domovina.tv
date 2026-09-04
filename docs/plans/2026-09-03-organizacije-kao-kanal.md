# Organizacija kao kanal — plan za kasnije

> 3.9.2026. **Nije za izvedbu.** Ovo je zapis odluke da se odgodi i skica
> najjeftinijeg puta, da se za pola godine ne kreće ispočetka.
> Nastavak `virtualni-kanali.md` (O1–O10) i `2026-09-03-virtualni-kanal-belavic.md`.
> Putanje bez prefiksa repoa su u ovom repou; `services/…` i `infra/…` u `domovina-rag`.

## Povod

Zahtjev je bio virtualni kanal za **udrugu „Prilika za susret"**, čiji
predsjednik Tomislav Belavić gostuje po tuđim kanalima. Isporučeno je ono što
sustav zna: **osoba** kao kanal (`/p/tomislav-belavic`, 6 epizoda / 6 kanala /
6 h 48 min). Udruga kao entitet ne postoji nigdje — ni u shemi, ni u modelu, ni
u rutama.

To je namjerna granica, ne previd. Zapisana je jer se isti zahtjev vraća čim
druga organizacija (župa, institut, pokret) zatraži isto.

## Zašto osoba nije dovoljna

| Što organizacija ima, a osoba nema |
|---|
| **Više govornika** — udruga s tri člana koji gostuju danas ima tri nesuvisla profila; njihovi nastupi se nigdje ne zbrajaju. |
| **Ime koje nije ime osobe** — „Prilika za susret" ≠ „Tomislav Belavić". Danas `PersonHub.name` dolazi iz `speakers.canonical_name`, a to je ime koje diarizacija koristi za matchanje; ne smije se preimenovati. |
| **Trajanje dulje od člana** — osoba ode, organizacija ostane. Kanal vezan uz osobu se raspada pri smjeni predsjednika. |
| **Vlasništvo** — organizacija može claimati svoj kanal i primati donacije; osoba u modelu O7 ne može ni jedno ni drugo. |

## Tri puta, po cijeni

### Put 1 — `display_name` na osobi *(najjeftinije, ~pola dana)*

Jedna kolona `speakers.display_name`; `get-person.ts` je preferira nad
`canonical_name`. Kanal se zove „Prilika za susret — Tomislav Belavić".
Diarizacijsko matchanje ostaje na `canonical_name` pa se ništa ne lomi;
**frontend ne treba nikakvu izmjenu** jer čita `name`.

Što ovo NE rješava: i dalje je jedan govornik, a kanal je vezan uz njega.
Drugi član udruge ne može ući.

**Ovo je jedini put koji je vrijedan prije nego postoji druga organizacija.**

### Put 2 — kolekcija govornika *(~3 dana)*

Nova PG tablica koja veže N osoba pod jedan javni slug:

```sql
CREATE TABLE person_groups (
  slug        TEXT PRIMARY KEY,     -- 'prilika-za-susret'
  name        TEXT NOT NULL,
  description TEXT,
  avatar_url  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE person_group_members (
  group_slug   TEXT NOT NULL REFERENCES person_groups(slug) ON DELETE CASCADE,
  person_slug  TEXT NOT NULL,       -- speakers.slug
  role         TEXT,                -- 'predsjednik', 'član'
  PRIMARY KEY (group_slug, person_slug)
);
```

`GET /api/group/:slug` vraća **isti oblik kao `/api/person/:slug`** — unija
epizoda svih članova, deduplicirana po `youtube_id`, ista `is_virtual_channel`
presuda iz `person-channel.ts`. Time frontend dobiva postojeći `PersonHub`
model i `PersonScreen` bez ijedne izmjene modela; treba mu samo ruta.

**Zamke koje plan mora poštovati:**

- **Nova javna content ruta ide u OBA deep-link popisa** (AASA `components` u
  `web/_worker.js` + Android intent filter u `AndroidManifest.xml`) — pravilo iz
  `CLAUDE.md`. `/p/` je pokriven; `/g/` nije.
- **Prag se NE primjenjuje po članu nego po grupi.** Udruga s tri člana od kojih
  svaki ima 2 epizode ima 6 epizoda i mora ući, iako nijedan član sam ne prolazi.
- **Dedup je obavezan**: dva člana u istoj epizodi = jedna epizoda, ne dvije.
  Isti `seen` obrazac kao u `services/mcp/src/tools/list-persons.ts`.
- **`max_channel_share` mjeri se nad unijom.** Udruga koja gostuje samo na
  vlastitom kanalu i dalje je domaćin.

### Put 3 — organizacija kao prvorazredni entitet *(tjedni)*

Vlasništvo (claim), pinka kampanja, više administratora, vlastiti opis i
avatar koji netko uređuje. To znači migraciju `channel_claims` na
`subject_type: person|organization|youtube_channel` i isto na `PinkaCampaign` —
dug koji je O7 svjesno prihvatio.

**Ne prije nego postoji organizacija koja to plaća ili traži.**

## Odluka

**Put 1 kad zatreba, Put 2 kad se pojavi DRUGA organizacija, Put 3 ne planirati.**

Okidač za Put 2 je brojiv: druga organizacija koja traži isto, ili prva udruga
s dva člana koji oba gostuju. Dotle je jedna osoba ispravan model i jeftinije ga
je držati nego generalizirati unaprijed.

## Ograda koja vrijedi u svim putovima

Iz O8, granica (b): kartica i hero **ne smiju tvrditi „službeni kanal udruge"**.
Ovo je agregat gostovanja na tuđim kanalima, a ne kanal koji organizacija
uređuje. Ako naslov nosi ime organizacije (Put 1 nadalje), podnaslov to mora
reći izrijekom — inače je to tvrdnja o suradnji koju nemamo.

Pristanak: Belavić je predsjednik udruge pa je njegov lako dobiti, ali
**obavijest prije objave (O8 §1) se šalje svejedno**, i pravo na uklanjanje
(`person_optouts`, migracija 006) vrijedi jednako za grupu kao za osobu.
