# Izborni dan — glasanje o sljedećem kanalu (jedan građanin, jedan glas dnevno)

> Status: **plan**, 8.8.2026.
> Odluke donesene s korisnikom prije pisanja: slobodan izbor iz cijelog registra ·
> kola od 14 dana · streak samo za verificirane · bez podsjetnika u v1.

## 1. Što gradimo

Hrvatski građanin potvrđen e-Osobnom (Certilia) dobiva **jedan glas svakih 24 h**
(kalendarski dan, Europe/Zagreb). Glas troši na **jednog kandidata iz registra
hrvatskih podcasta** — 👍 („želim ovo na DOMOVINA.ai") ili 👎 („ne ovog").

Glasanje teče u **kolima od 14 dana**. Pobjednik kola stvarno se onboarda u
pipeline i pojavi se u `/channels`. Bazen kandidata se time smanjuje, rezultat
se resetira, kreće novo kolo.

Povratak svaki dan drži **streak** mehanika kopirana s Brilliant.org, s hrvatskim
prijevodom: niz dana 🔥 + do **dvije hrvatske zastavice** koje automatski spašavaju
propušteni dan. Svaki odglasani dan vraća jednu zastavicu (max 2).

**Zašto ovo, a ne obični „predloži kanal" gumb**: kuratorska odluka koja ionako
postoji (koga sljedeće obraditi) pretvara se u razlog za dnevni povratak, a
Certilia gate daje rezultatu težinu koju anonimno glasanje nikad nema — „181
kandidat, 2.400 verificiranih hrvatskih građana glasalo" je priča koja se može
ispričati javno i medijima.

---

## 2. Research: kako streak radi u drugim aplikacijama

### 2.1 Brilliant.org — izvor naše mehanike

Točna pravila ([Brilliant Help][b1], [Brilliant Help — Streak Charge][b2]):

| Pitanje | Brilliant |
|---|---|
| Što produžuje niz | 3 zadatka ili 1 cijela lekcija u danu |
| Naziv „freeze" | **Streak Charge** (ikona baterije) |
| Kako se zarađuje | **jedan charge po svakoj odrađenoj lekciji/vježbi** |
| Maksimum | **2 istovremeno** |
| Kad se troši | **automatski**, čim se dan propusti |
| Produžuje li charge niz | **NE** — niz ostaje na istom broju, samo ne pukne |
| Istječu li | ne |
| Gdje se vidi | homepage streak sekcija + iOS home screen widget |

**Uzimamo doslovno**: max 2, automatska primjena, ne produžuje niz.
**Mijenjamo jedno** (vidi §6.3): mi zastavice trošimo *sve-ili-ništa* — ako ih
nema dovoljno da spase niz, ne trošimo ih uopće. Brilliant ih pali dan po dan pa
korisnik koji nestane na tjedan dana izgubi **i** zastavice **i** niz. To je dvostruka
kazna za isti propust i loše se podnosi.

### 2.2 Duolingo — najistraženija implementacija

- **>600 eksperimenata samo na streak feature-u** — otprilike jedan svaka dva dana
  ([Medium teardown][d1]).
- Streak je izvorno tražio XP prag; prelazak na „jedna lekcija dnevno" (jednostavan,
  binaran uvjet) donio je **veliki skok u DAU** ([Apptitude teardown][d3]).
  → Naš uvjet je binaran po dizajnu: *jesi li potrošio današnji glas*. Ne „3 glasa",
  ne „X minuta". Jedan tap.
- **Streak Freeze smanjio churn 21 %** kod korisnika kojima niz visi
  ([StriveCloud][d4]).
- Pokretač nije ponos nego **loss aversion** (Core Drive 8 u Chouovom okviru) —
  ljudi ne guraju niz naprijed, nego ga **brane** ([Yu-kai Chou][d2]).
  → UI mora prikazivati *što se gubi*, ne samo trenutni broj.

### 2.3 Ostali presedani

- **TryHackMe** ([help centar][t1]) — freeze se *dodjeljuje* za milestone dane, ne
  za svaki dan. Sporije se puni; naša (Brilliantova) shema je velikodušnija i
  jednostavnija za objasniti.
- **Snapchat** — streak preživljava samo s reciprocitetom i ima „restore" za novac.
  Monetizaciju streaka **ne uzimamo**: naplaćena zastavica bi pretvorila građansko
  glasanje u pay-to-win i srušila legitimnost rezultata.
- **Apple Fitness (Perfect Month)** — kalendarski prsten, retroaktivno nepopravljiv.
  Uzimamo iz njega samo **vizualni kalendar mjeseca** kao sekundarni prikaz.

### 2.4 Zamke iz prakse (i naš odgovor)

| Zamka | Odgovor u ovom planu |
|---|---|
| Timezone / DST — najčešća kategorija support tiketa kod streak feature-a ([Trophy][tr1]) | Jedna nacionalna vremenska zona `Europe/Zagreb`, dan se računa **isključivo u Postgresu**, klijent nikad ne šalje datum. DST prijelaz u Hrvatskoj je u 03:00 → ne dira ponoćnu granicu. |
| „Grace hours" (6–8 h nakon ponoći) | **Ne implementiramo.** Rušio bi tvrdnju „jedan glas po kalendarskom danu", a zastavice već pokrivaju propust. |
| Streak anxiety — niz koji se ne može popraviti je bomba za loš dan | Dvije zastavice = do 2 propuštena dana; „Izgubljen niz" ekran nudi restart bez srama, uz „najduži niz: N" koji ostaje zauvijek. |
| Nightly cron koji lomi nizove | Nema crona. **Lijeno računanje** (§6.3): stanje se izvodi tek kad korisnik dođe. Isti čisti izraz koristi i prikaz i upis. |
| Streak kao jedina svrha (ljudi tapkaju bez čitanja) | Kolo od 14 dana daje ishod (onboardan kanal) → glas nešto proizvodi, ne samo broji. |

---

## 3. Kandidatski bazen — analiza registra

Izvor: `fetch.domovina.tv/data/podcasts_registry.json` (v1.2, 27.7.2026.), javno
objavljen na `https://podcast-registry.domovina.ai/registry.json`.

```
273  ukupno u registru
  2  umbrella zapisi (prate se kroz child playliste)
 69  već tracked → NISU kandidati
204  netracked
```

Filter kandidata: `tracking.enabled == false` **AND** ima `youtube.url` **AND**
`metadata.status ∈ {active, active-slowing, unknown}`:

```
181  KANDIDATA
177  ima youtube.channel_id   → avatar se može dohvatiti
146  ima broj pretplatnika
175  ima notes (jednorečenični opis)
133  ima candidate_phase (operaterska namjera)
 11  je playlist-only (ne kanal)
 34  ima popis voditelja
 32  ima procjenu broja epizoda
```

Raspodjela `quality_score` (0–100, rubrika je editorijalno neutralna — mjeri
aktivnost, katalog, doseg, format, supstancu, verificiranost, svježinu):
max **100**, medijan **64**, min **38**. Po tieru: T1 = 18, T2 = 13, T3 = 140, T4 = 9.

Top kandidati po kvaliteti (ovo je i prvi realan kolo-1 lider board):

| score | tier | slug | tagovi |
|---|---|---|---|
| 100 | T1 | `podcast-inkubator` | talk-show, society |
| 96 | T1 | `projekt-velebit` | political, history, domoljubni |
| 91 | T1 | `rebootcast` | gaming |
| 88 | T1 | `kriminalno-dobre-price` | true-crime |
| 88 | T1 | `moc-komunikacije` | communication, leadership |
| 84 | T1 | `mjesto-zlocina` | true-crime |
| 84 | T1 | `samo-bez-panike` | women, lifestyle, health |
| 83 | T1 | `human-lab-podcast` | health, fitness |
| 80 | T2 | `ana-radisic-podcast` | talk-show |
| 79 | T1 | `spica-s-macanom` | political, society, economics |

**Registrijski princip v1.2 je „free speech aggregator" — uključuje SVE hrvatske
podcaste bez obzira na političku ili vjersku orijentaciju.** To je i preduvjet za
legitimno glasanje: bazen ne smije biti prethodno ideološki filtriran, inače je
glasanje kazališna predstava. Jedini filteri su tehnički (ima YouTube, aktivan je,
duži od praga).

**Ograničenje po duljini**: pipeline uzima ≥ 901 s (`MIN_DURATION` u
`automatic/refresh_podcasts.sh`). Dva top kandidata (`podcast-inkubator`,
`projekt-velebit`) imaju `min_duration_override` jer režu puno klipova — to je
operaterska napomena, ne prepreka glasanju, ali winner-flow (§9) je mora poštovati.

### 3.1 Rizik koji odluka „slobodan izbor iz cijelog registra" nosi

Uz 181 kandidata i **jedan glas po osobi dnevno**, ukupni dnevni volumen jednak je
broju aktivnih glasača. Pri 200 glasača dnevno to je ~1 glas po kandidatu po danu —
rep liste dobiva šum, a vrh se cementira prvog tjedna („rich get richer": ljudi
glasaju za ono što vide na vrhu).

Nije blokada — zadržavamo tvoj izbor — ali kompenziramo unutar njega:

1. **Default sort = „Ljestvica kola"**, ali odmah do njega chipovi
   **„Nasumično"** i **„Najmanje glasova"** (bottom-N shuffle) da rep dobije izlaganje.
2. **Filter po tagovima** (12 najčešćih iz registra) — korisnik prirodno zaroni u
   svoju nišu umjesto da gleda globalni vrh.
3. **Kolo od 14 dana resetira ljestvicu** — cementiranje traje najviše dva tjedna.
4. **Kvorum za pobjedu** (§7.2) — bez njega pobjeđuje kandidat s 3 glasa.
5. Mjeri se **Gini koeficijent raspodjele glasova po kandidatu** po kolu. Ako
   prvih 10 kandidata pokupi > 80 % glasova kroz dva kola, vraćamo na stol
   „trojku dana" kao *default* ekran s „vidi sve" ispod.

---

## 4. Integritet: zašto je Certilia gate stvarno jedan-čovjek-jedan-glas

Postojeća infrastruktura (`domovina-api`) već rješava 90 % posla:

- `supabase/functions/certilia/index.ts` — verificira Certilia `idToken` protiv
  JWKS (issuer iz discovery dokumenta, audience = client id), čita trusted claimove,
  bridgea na Supabase sesiju kroz `email_otp`.
- `public.identity_verifications` (migracija `20260529120000`) — OIB enkriptiran
  pgcrypto-om, **`oib_hash` (HMAC-SHA256) s UNIQUE constraintom**, RLS bez ijedne
  client policy (service_role-only).
- `AuthService` na klijentu već izlaže `currentUser.isVerified`
  (`app_metadata.kyc_verified`).

`unique (oib_hash)` znači: **jedan OIB = jedan račun, na razini baze.** Drugi račun
s istim OIB-om ne može se ni upisati.

### 4.1 Rupa koju moramo zatvoriti prije prvog glasa

`identity_verifications.user_id` ima `on delete cascade`. Dakle:

```
glasaj → obriši račun (cascade briše KYC red → oib_hash oslobođen)
       → registriraj se ponovno → verificiraj isti OIB → glasaj opet (isti dan)
```

**Rješenje: glas se ne veže na `user_id` nego na trajni pseudonim `voter_id`**
(§5, tablica `domovina_ai.voters`), koji preživljava brisanje računa jer nosi
`oib_hash`, a `user_id` mu je `on delete set null`. Nusprodukt je lijep: korisnik
koji obriše i ponovno napravi račun **vraća svoj streak**.

Retencija (GDPR čl. 5(1)(e)): `voters` ne sadrži ime, e-mail ni OIB u čitljivom
obliku — samo izvedeni HMAC. Redovi bez aktivnosti 24 mjeseca brišu se rutinski.
Obrazloženje čuvanja nakon brisanja računa: **integritet glasanja** (legitimni
interes, čl. 6(1)(f)), dokumentirati u `/privacy`.

### 4.2 Model prijetnji

| Prijetnja | Status |
|---|---|
| Više računa iste osobe | Blokirano `unique(oib_hash)` |
| Brisanje + ponovna registracija | Blokirano trajnim `voters.oib_hash` (§4.1) |
| Skriptirano glasanje nakon verifikacije | Bezopasno — strop je 1 glas/dan po osobi |
| Više glasova u istom danu (race, dupli tap) | `unique (voter_id, vote_day)` + `RETURNING` u jednoj transakciji |
| Klijent laže o datumu | Datum se **nikad** ne prima od klijenta; `(now() at time zone 'Europe/Zagreb')::date` u SECURITY DEFINER funkciji |
| Brigading (fanbase podcasta mobilizira publiku) | **Legitimno**, ne blokiramo. Certilia friktcija je prirodni prigušivač. Transparentnost: dnevni total i broj glasača javni |
| Kupovina glasova | Ne možemo tehnički spriječiti; ublažava se time što nagrada nije novčana |
| Tuđa e-Osobna (npr. roditelj glasa dječjom) | Izvan dosega; Certilia LoA je ono što imamo |

### 4.3 Ovo NIJE tajno glasovanje — i to se mora reći naglas

`voter_id → oib_hash` postoji u bazi, dakle netko s pristupom bazi može povezati
glas s osobom. Za „koji podcast sljedeći" to je prihvatljivo, ali:

- Registar nosi tagove `political`, `political-conservative`, `religious-catholic`.
  Glas za takav kanal **može posredno otkriti političko ili vjersko uvjerenje** —
  to je posebna kategorija podataka (GDPR čl. 9).
- Zato: (a) pri **prvom** glasu jednokratni ekran privole s izričitom rečenicom
  „Ovo nije tajno glasovanje", (b) **nikad** ne objavljujemo pojedinačne glasove
  ni tko je za što glasao — samo agregate, (c) dopunjujemo `/privacy`.
- Ako se mehanika ikad proširi na politička pitanja, glasanje se mora razdvojiti
  (`ballots(voter_id, vote_day)` odvojeno od `choices(candidate, direction)` bez
  poveznice). Zapisano ovdje da se ne otkrije prekasno.

---

## 5. Model podataka (`domovina-api`)

Nova migracija `supabase/migrations/20260808120000_channel_voting.sql`
(+ `..._rls.sql`, `..._rpcs.sql` po uzoru na events/pinka trojku).

Shema: **`domovina_ai`** — feature je specifičan za ovaj proizvod, ne za platformu
(vidi `db_schema_split`).

```sql
-- ── kandidati (snapshot registra) ────────────────────────────────────────────
create table domovina_ai.vote_candidates (
  slug              text primary key,          -- registry slug, DOSLOVNO
  display_name      text not null,
  youtube_url       text not null,
  youtube_channel_id text,
  avatar_url        text,                       -- CDN, vidi §8.4
  tags              text[] not null default '{}',
  voditelji         text[] not null default '{}',
  subscribers       int,
  episodes_estimate int,
  quality_score     int,
  tier              int,
  notes             text,
  source_type       text,                       -- 'channel' | 'playlist' | 'audio-primary'
  status            text not null default 'candidate',
                    -- candidate | winner | onboarding | onboarded | withdrawn
  onboarded_channel_id text,                    -- id u channels index.json kad završi
  registry_synced_at timestamptz not null default now(),
  created_at        timestamptz not null default now()
);
create index on domovina_ai.vote_candidates (status);
create index on domovina_ai.vote_candidates using gin (tags);

-- ── kola ─────────────────────────────────────────────────────────────────────
create table domovina_ai.vote_rounds (
  id            int generated always as identity primary key,
  starts_on     date not null,                  -- Europe/Zagreb kalendarski dan
  ends_on       date not null,                  -- uključivo
  status        text not null default 'open',   -- open | closed
  winner_slug   text references domovina_ai.vote_candidates(slug),
  closed_at     timestamptz,
  no_winner_reason text,                        -- 'quorum_not_met'
  unique (starts_on)
);
create unique index one_open_round on domovina_ai.vote_rounds (status)
  where status = 'open';

-- ── glasači (trajni pseudonim; preživljava brisanje računa) ──────────────────
create table domovina_ai.voters (
  id             uuid primary key default gen_random_uuid(),
  oib_hash       text not null unique,          -- iz identity_verifications
  user_id        uuid references auth.users(id) on delete set null,
  current_streak int  not null default 0,
  longest_streak int  not null default 0,
  flags          int  not null default 0 check (flags between 0 and 2),
  last_vote_day  date,
  total_votes    int  not null default 0,
  consented_at   timestamptz,                   -- §4.3 privola
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index on domovina_ai.voters (user_id);

-- ── glasovi ──────────────────────────────────────────────────────────────────
create table domovina_ai.votes (
  id         bigint generated always as identity primary key,
  voter_id   uuid not null references domovina_ai.voters(id) on delete cascade,
  round_id   int  not null references domovina_ai.vote_rounds(id),
  slug       text not null references domovina_ai.vote_candidates(slug),
  direction  smallint not null check (direction in (-1, 1)),
  vote_day   date not null,                     -- Europe/Zagreb, SERVER-SIDE
  created_at timestamptz not null default now(),
  unique (voter_id, vote_day)                   -- ← srce „jedan glas dnevno"
);
create index on domovina_ai.votes (round_id, slug);

-- ── agregat po kolu (materijaliziran; osvježava se u cast_vote) ──────────────
create table domovina_ai.vote_tallies (
  round_id int  not null references domovina_ai.vote_rounds(id),
  slug     text not null references domovina_ai.vote_candidates(slug),
  up       int  not null default 0,
  down     int  not null default 0,
  net      int  generated always as (up - down) stored,
  primary key (round_id, slug)
);
create index on domovina_ai.vote_tallies (round_id, net desc, up desc);

-- ── praćenje kandidata (BEZ verifikacije, za sve) ────────────────────────────
create table domovina_ai.candidate_follows (
  user_id    uuid not null references auth.users(id) on delete cascade,
  slug       text not null references domovina_ai.vote_candidates(slug),
  created_at timestamptz not null default now(),
  primary key (user_id, slug)
);
```

**Zašto materijalizirani `vote_tallies` a ne `count(*)` view**: ljestvica se čita
na svakom otvaranju ekrana, a piše se najviše jednom po glasaču dnevno. Inkrement
ide u istoj transakciji kao `insert into votes`.

### 5.1 RLS

- `vote_candidates`, `vote_rounds`, `vote_tallies` → `select` za `anon` i
  `authenticated` (rezultati su javni, §4.3), `insert/update` nitko osim
  `service_role`.
- `voters`, `votes` → **zero client policies**, kao `identity_verifications`.
  Klijent im pristupa isključivo kroz RPC-eve ispod.
- `candidate_follows` → `select/insert/delete` za vlastiti `user_id`.

### 5.2 RPC-evi (SECURITY DEFINER, `set search_path = ''`)

```
domovina_ai.my_voting_state()      → jsonb   (authenticated)
domovina_ai.cast_vote(slug, dir)   → jsonb   (authenticated)
domovina_ai.round_leaderboard(round_id, sort, tag, limit, offset) → setof (anon ok)
domovina_ai.current_round()        → jsonb   (anon ok; lijeno otvara/zatvara kolo)
domovina_ai.accept_voting_terms()  → void    (authenticated)
```

`my_voting_state()` vraća projekciju bez ikakvog upisa:

```json
{
  "verified": true,
  "consented": true,
  "voted_today": false,
  "today": "2026-08-08",
  "streak": 12,
  "longest_streak": 19,
  "flags": 2,
  "streak_at_risk": true,
  "flags_that_will_burn": 0,
  "last_vote_day": "2026-08-07",
  "today_vote": null,
  "round": { "id": 7, "ends_on": "2026-08-14", "days_left": 6 }
}
```

`cast_vote` u jednoj transakciji: razriješi `voter` iz `oib_hash` → izračunaj
današnji dan → `insert into votes` (unique constraint je čuvar) → upsert tally →
primijeni streak prijelaz (§6.3) → vrati novo stanje **plus** `flags_burned` i
`streak_saved` da UI može animirati što se dogodilo.

Greške: `not_verified`, `terms_not_accepted`, `already_voted_today`,
`candidate_not_available`, `round_closed`.

---

## 6. Streak mehanika — precizno

### 6.1 Pojmovnik (i hrvatski copy)

| Kod | UI (hr) | Napomena |
|---|---|---|
| streak | **niz** / „Niz od 12 dana" | ikona 🔥 |
| flag | **zastavica** 🇭🇷 | max 2 |
| vote_day | **izborni dan** | ponoć–ponoć, Europe/Zagreb |
| round | **kolo** | 14 dana |

Registar/ton po CLAUDE.md: neformalno „ti" („Danas još nisi glasao").

### 6.2 Granica dana

`(now() at time zone 'Europe/Zagreb')::date`, izračunato **isključivo** u
Postgresu. Nema grace sati. Dijaspora s hrvatskom e-Osobnom glasa po hrvatskom
satu — to je značajka, ne bug, i objašnjava se u UI-ju („Izborni dan traje od
ponoći do ponoći po hrvatskom vremenu").

DST: Hrvatska mijenja sat u 03:00, granica dana je 00:00 → nema preklapanja.

### 6.3 Prijelaz stanja (lijen, bez crona)

```
D          = današnji izborni dan
L          = voter.last_vote_day
missed     = (L is null) ? 0 : (D - L - 1)      -- broj propuštenih dana
```

**Pri glasanju** (`cast_vote`):

```
if L is null:                       streak = 1
elif missed == 0:                   streak = streak + 1          -- uzastopno
elif missed <= flags:               flags -= missed              -- SPAŠENO
                                    streak = streak + 1
else:                               streak = 1                   -- PUKNUO
                                    -- zastavice se NE troše (§2.1)

flags          = min(2, flags + 1)  -- nagrada za današnji dolazak
longest_streak = max(longest_streak, streak)
last_vote_day  = D
```

**Pri čitanju** (`my_voting_state`) — isti izraz, bez upisa:

```
voted_today      = (L == D)
streak_at_risk   = (not voted_today) and (missed == flags)   -- zadnji dan obrane
displayed_streak = voted_today ? streak
                 : (missed <= flags ? streak : 0)            -- već je pukao
```

**Zašto lijeno**: cron u ponoć nad svim glasačima je nepotreban posao i još jedna
stvar koja može pasti u 00:00 i pokvariti svima niz. Stanje ionako nikoga ne
zanima dok ne otvori aplikaciju.

**Namjerno odstupanje od Brilliant-a** — zastavice se troše sve-ili-ništa. Tko
nestane na 7 dana s 2 zastavice vraća se na niz 1 **ali sa 2 zastavice**
(pa +1 = strop 2). Brilliant bi mu spalio obje i svejedno slomio niz.

### 6.4 Rubni slučajevi koje testovi moraju pokriti

| Slučaj | Očekivano |
|---|---|
| Prvi glas ikad | niz 1, zastavice 1 |
| Glas u 23:59:59 pa u 00:00:01 | dva različita izborna dana, niz +2 |
| Dupli tap (dvije istovremene `cast_vote`) | druga pada na `already_voted_today`, tally se ne duplira |
| Propušten 1 dan, 1 zastavica | zastavica potrošena, niz nastavljen, na kraju zastavice = 1 |
| Propuštena 2 dana, 2 zastavice | obje potrošene, niz nastavljen, na kraju = 1 |
| Propuštena 3 dana, 2 zastavice | niz = 1, zastavice ostaju 2 (strop) |
| Zastavice na stropu, glasa se | ostaje 2, ne 3 |
| Brisanje računa → nova verifikacija istog OIB-a | isti `voter_id`, niz i zastavice sačuvani |
| Glas na dan kad kolo završava | ulazi u kolo koje se zatvara, ne u sljedeće |
| Kandidat proglašen pobjednikom usred kola | `candidate_not_available` |

Testovi: `test/voting_streak_test.dart` za čistu Dart projekciju (isti izraz
duplicirani na klijentu za optimistički prikaz) + pgTAP/SQL scenarij u
`domovina-api` po uzoru na `docs/events-ticketing-curl-scenario.md`.

---

## 7. Rangiranje i zatvaranje kola

### 7.1 Formula

**Neto = 👍 − 👎.** Bez Wilsona, bez Bayesa, bez težina.

Obrazloženje: rezultat mora biti objašnjiv u jednoj rečenici („najviše glasova
pobjeđuje"). Statistički sofisticiranije mjere (Wilsonova donja granica) favoriziraju
omjer nad volumenom i proizvele bi pobjednika kojeg nitko ne bi mogao obraniti
pred publikom. Legitimnost > preciznost.

Tie-break redom: `net desc` → `up desc` → `quality_score desc` → `slug asc`
(deterministički, bez `random()`).

### 7.2 Kvorum

Pobjednik kola mora zadovoljiti **oboje**:

- `net >= 10`
- `up + down >= 25` glasova na tom kandidatu

Ako nitko ne prođe → kolo se zatvara **bez pobjednika**
(`no_winner_reason = 'quorum_not_met'`), tally se **prenosi** u sljedeće kolo
(carry-over) umjesto resetiranja. Time rani, tanki dani ne proizvedu pobjednika
s tri glasa, a trud glasača se ne baca.

Brojevi su namjerno konzervativni za start i **konfigurabilni** u
`vote_rounds` (`quorum_net`, `quorum_total` kolone) da se mogu podignuti kad
volumen naraste, bez migracije.

### 7.3 Zatvaranje kola — također lijeno

`current_round()` pri svakom pozivu: ako postoji `open` kolo kojem je
`ends_on < today`, u jednoj transakciji sa `pg_advisory_xact_lock`:

1. izračunaj pobjednika iz `vote_tallies` + kvorum
2. `update vote_rounds set status='closed', winner_slug=…, closed_at=now()`
3. `update vote_candidates set status='winner' where slug = winner`
4. `insert into vote_rounds (starts_on = ends_on+1, ends_on = +13)`
5. carry-over tally ako nema pobjednika

Idempotentno, bez infrastrukture. Prvi korisnik koji otvori ekran nakon ponoći
plaća ~5 ms.

---

## 8. Flutter — UI i rute

### 8.1 Rute (GoRouter, `lib/router/app_router.dart`)

```
/glasanje              → VotingScreen        (javno; rezultati vidljivi svima)
/glasanje/:slug        → CandidateSheet      (detalj kandidata, deep-link/share)
/glasanje/kola         → RoundsHistoryScreen (arhiva pobjednika)
```

Ruta je javna i dijeljiva → mora u **OBA** popisa iz CLAUDE.md: AASA `components`
u `web/_worker.js` i Android intent filter u `AndroidManifest.xml`. OG injection u
workeru dobiva `/glasanje` (statični OG) i `/glasanje/:slug` (naslov kandidata).

### 8.2 Ekran `/glasanje`

```
┌─ IZBORNI DAN · petak, 8.8.2026. ─────────────────────┐
│  Niz 12 🔥   🇭🇷🇭🇷    Kolo 7 · još 6 dana            │
│  Imaš 1 glas. Potroši ga do ponoći.                   │
└───────────────────────────────────────────────────────┘
[ Ljestvica ] [ Nasumično ] [ Najmanje glasova ]  🔍
[ #katolicki ] [ #sport ] [ #politika ] [ #tech ] …

 1. ▮ Podcast Inkubator          +142   👍 👎
    talk-show · 400 tis. · Marko Petrak, Ratko Martinović
 2. ▮ Projekt Velebit             +98   👍 👎
 …
```

Nakon glasa, kartica kandidata se zaključa s „Tvoj glas danas" i cijela lista
prelazi u read-only stanje s odbrojavanjem do ponoći.

**Stanja koja UI mora imati** (svako je zaseban widget, ne if-ovi u buildu):

1. **Gost / neverificiran** — ljestvica potpuno vidljiva, umjesto 👍👎 stoji
   `⚑ Prati` (radi bez prijave, lokalno + `candidate_follows` kad je prijavljen)
   i trajna traka „Potvrdi se e-Osobnom i glasaj".
2. **Verificiran, nije glasao** — aktivni gumbi, header naglašava što se gubi
   (loss aversion, §2.2): „Niz 12 🔥 — glasaj danas da ne pukne".
3. **Verificiran, glasao** — sažetak + „Vrati se sutra u 00:00".
4. **Niz visi** (`streak_at_risk`) — crvenkasti header, „Zadnja zastavica brani
   tvoj niz od 12 dana".
5. **Niz je pukao** — jednokratni ekran bez srama: „Niz je stao na 12. Najduži
   ostaje 19. Kreni ispočetka." + gumb koji odmah otvara glasanje.

### 8.3 Zastavice — asset, ne emoji

🇭🇷 emoji se **ne renderira** na Windows Chromeu (nema regional-indicator glifa).
Zastavica ide kao `assets/voting/zastavica.png` + `zastavica_prazna.png` kroz
`Image.asset` — **ne SVG** (CLAUDE.md: `flutter_svg` puca na webu).

Animacija trošenja zastavice (zastavica se spusti na pola koplja pa nestane) —
Rive ili obični `AnimatedSwitcher`; Rive je ono čime Brilliant drži streak
animacije ([Rive case study][r1]), ali za v1 je `AnimatedSwitcher` dovoljan.

### 8.4 Avatari kandidata

177/181 kandidata ima `youtube.channel_id`. Sync skripta (§9.1) povlači avatar
kroz `yt-dlp --print thumbnail` i uploada na CDN kao
`cdn.domovina.ai/registry/avatars/<slug>.jpg`.

- **Nikad `Image.network` direktno na YouTube URL** — CORS puca (isto pravilo kao
  `CdnConfig.thumbnailUrl`).
- Koristi `CachedThumbnail` (disk-persistent), ne goli `Image.network`.
- Fallback za 4 kandidata bez avatara: monogram na `AppTheme.croBlue` + `brandRim()`.

### 8.5 Servis + model

- `lib/services/voting_service.dart` — **singleton `ChangeNotifier`** (isti razlog
  kao `PlaybackSpeed`/`PlayerMute`: stanje niza pojavljuje se na home headeru,
  ekranu glasanja i `/account`; prop drilling bi ga negdje ispustio).
- `lib/models/vote_candidate.dart`, `voting_state.dart`, `vote_round.dart`.
- Optimistički update nakon `cast_vote` uz rollback na grešku; `already_voted_today`
  se ne prikazuje kao greška nego kao tiho poravnanje stanja (druga kartica/tab).
- **Bez `SharedPreferences` na webu** — lokalni cache zadnjeg stanja ide kroz
  `local_prefs.dart`.

### 8.6 Ulazne točke

- `home_app_bar.dart`: chip s nizom i zastavicama; tap → `/glasanje`.
  Kad je glas neiskorišten — crvena točka.
- Home rail „Izborni dan" (iznad „Nastavi slušati") s top 3 kandidata kola.
- `/account`: „Tvoj niz", najduži niz, ukupno glasova, arhiva kola.
- `/channels`: traka na dnu — „Nema tvog podcasta? Glasaj koji ide sljedeći."
- **Nikad modal preko reprodukcije** (CLAUDE.md pravilo o nudge-evima): sve su
  trajne površine, nikad snackbar/dialog koji prekida.

### 8.7 i18n

Svi stringovi u `lib/l10n/app_hr.arb` (template) → `app_en.arb` → `flutter gen-l10n`.
Prefiks ključeva **`voting*`** (`votingTodayHeadline`, `votingStreakDays`,
`votingFlagsLeft`, `votingRoundDaysLeft`, …).

- ICU plural obavezan za dane/glasove/zastavice (hr `one/few/other`):
  „1 dan / 2 dana / 5 dana", „1 zastavica / 2 zastavice / 5 zastavica".
- Perzistentni tekst → `AppLocalizations.of(context)`; `appStrings` **samo** za
  jednokratni event-time resolve (poruke grešaka u catch bloku).
- Bez ALL-CAPS u ARB-u; `.toUpperCase()` u kodu.

---

## 9. Ono što glasanje proizvodi (fulfillment loop)

Bez ovoga je cijela mehanika teatar. Petlja je namjerno **poluručna** — jednom u
14 dana, 10 minuta posla:

```
kolo se zatvori (lijeno, §7.3)
  → vote_candidates.status = 'winner'
  → operater u fetch.domovina.tv:
      1. registry: tracking.enabled = true (+ min_duration_override ako treba)
      2. automatic/refresh_podcasts.sh: dodaj "slug|youtube_url" u KANALI
      3. pokreni ciklus obrade
  → status = 'onboarding' (UI: „U obradi")
  → kanal se pojavi u channels/data/index.json
  → status = 'onboarded' + onboarded_channel_id
  → UI: kartica pobjednika linka na /c/<slug>, s pečatom
        „Onboardan zahvaljujući 214 glasova u kolu 7"
```

`vote_candidates.status` nikad se ne mijenja ručno u bazi — sve ide kroz
`scripts/promote_winner.mjs` (novi, u `fetch.domovina.tv`) koji radi sva tri
koraka atomarno i zapiše status natrag preko `service_role` ključa.

**Ovaj pečat je najjači dio feature-a.** „Ti si ovo izglasao" je razlog za povratak
koji nadživi streak.

### 9.1 Sync registra → baze

`fetch.domovina.tv/scripts/sync_voting_candidates.mjs`, pokreće se ručno ili uz
regeneraciju registra:

- čita `data/podcasts_registry.json`
- filtrira po §3 pravilima (181 kandidat danas)
- upserta u `domovina_ai.vote_candidates` (`service_role`)
- **nikad ne briše** kandidate koji imaju glasove — samo `status = 'withdrawn'`
  ako nestanu iz registra ili se u međuvremenu počnu pratiti
- povlači i uploada avatare (§8.4)

---

## 10. Faze isporuke

| # | Faza | Sadržaj | Rezultat |
|---|---|---|---|
| **0** | Zatvaranje rupe | `voters` s trajnim `oib_hash`, `on delete set null` | Jedan-čovjek-jedan-glas stvarno drži |
| **1** | Backend | Migracije (schema + RLS + RPC), pgTAP scenarij | `cast_vote` radi kroz `curl` |
| **2** | Sync | `sync_voting_candidates.mjs` + avatari na CDN | 181 kandidat u bazi sa slikama |
| **3** | Flutter core | `VotingService`, modeli, `/glasanje` s ljestvicom i glasanjem, 5 stanja iz §8.2 | Feature radi end-to-end |
| **4** | Streak UI | Zastavice, animacije, „niz visi", „niz pukao", home chip | Retencijska petlja zatvorena |
| **5** | Kola | Arhiva `/glasanje/kola`, pečat pobjednika, `promote_winner.mjs` | Prvi stvarno onboardan pobjednik |
| **6** | Distribucija | OG za `/glasanje` i `/glasanje/:slug`, AASA + intent filter, „podijeli svoj niz" | Dijeljenje kao kanal rasta |
| **7** | *(uvjetno)* | Podsjetnici — vidi §11.1 | — |

Faze 0–3 su minimalni isporučivi rez. Faza 4 je ono zbog čega feature postoji.

---

## 11. Rizici i otvoreno

### 11.1 Nema podsjetnika (svjesna odluka)

Odlučeno: v1 bez podsjetnika, mjerimo koliko se ljudi vraća samo od sebe.

**To je najveći rizik plana.** Streak bez kanala obavještavanja oslanja se
isključivo na to da korisnik sam otvori aplikaciju — Duolingo bez notifikacija
ne bi imao streak feature, imao bi tablicu. Zastavice ovo djelomično pokrivaju
(dva dana zaborava su besplatna), ali očekuj znatno kraće nizove nego u
referentnim brojkama iz §2.2.

Odluka o gradnji podsjetnika mora se donijeti nad podacima, ne dojmom. Zato
faza 3 **mora** logirati:

- distribuciju duljine niza (medijan, p90) po tjednu
- udio glasača koji potroše zastavicu (ako je > 40 %, ljudi zaboravljaju → kanal
  obavještavanja se isplati)
- D1/D7/D14 retenciju verificiranog glasača

Redoslijed kad dođe red: **e-mail (Resend, već imamo, cron 18:00 samo onima koji
danas nisu glasali)** → web push (VAPID, proširenje postojećeg SW-a; iOS samo za
PWA na home screenu) → native FCM/APNs.

### 11.2 Certilia friktcija je uska grla cijelog feature-a

e-Osobna + čitač/mToken je ozbiljna prepreka; realno očekivati jednoznamenkasti
postotak konverzije iz posjetitelja u glasača. Zato:

- Ljestvica je **javna bez prijave** — vrijednost se vidi prije nego se traži trud.
- `⚑ Prati kandidata` radi bez ikakve prijave i daje mjeru latentne potražnje
  (koliko bi ljudi glasalo da nema gatea).
- Verifikacija se traži **tek na tap na 👍/👎**, s konkretnim kontekstom
  („Potvrdi se da tvoj glas za *Rebootcast* bude prebrojan"), nikad unaprijed.

### 11.3 Ostalo

| Rizik | Ublažavanje |
|---|---|
| Raspršenost glasova po 181 kandidatu (§3.1) | Sort chipovi, tag filteri, kvorum, mjerenje Ginija |
| Prvo kolo bez kvoruma | Carry-over tally; kolo 1 se može produžiti na 21 dan |
| Pobjednik kojeg pipeline ne može obraditi (playlist-only, prekratke epizode) | `sync` označava `source_type`; UI to prikazuje; operater može `withdrawn` uz javno obrazloženje **prije** kraja kola, nikad poslije |
| Vlasnik kanala ne želi biti onboardan | Postojeći `channel_ownership` flow (`/c/:slug/claim`) + `withdrawn` status s razlogom |
| Optužba za namještanje | Objavi po kolu: ukupan broj glasača, dnevni total, puni tally svih kandidata (ne pojedinačne glasove) |
| Osjetljivost političkih/vjerskih tagova (§4.3) | Privola pri prvom glasu, agregati only, dopuna `/privacy` |

### 11.4 Odluke koje ostaju otvorene

1. **Duljina kola** — 14 dana je pretpostavka. Ako pipeline lako proguta kanal
   tjedno, 7 dana daje dvostruko više „pobjeda" i jaču petlju.
2. **Prikaz 👎** — javno pokazivati negativne glasove ili samo neto? Javni 👎
   uz ime hrvatskog podcastera je potencijalno neugodan; sklon sam prikazivati
   **samo neto**, a razdvojeno up/down držati u API-ju za transparentnost na
   zahtjev.
3. **Smije li se glas promijeniti isti dan** — trenutno ne (jednostavnije,
   „glas je glas"). Alternativa: izmjena dopuštena do ponoći.
4. **Streak Society / milestone nagrade** (7, 30, 100, 365 dana) — Duolingo ih
   ima; kod nas bi mogle biti bedževi ili pravo predlaganja kandidata izvan
   registra. Faza 8+.

---

## 12. Metrike uspjeha

| Metrika | Cilj kola 1 | Kako mjerimo |
|---|---|---|
| Verificiranih glasača | 250 | `count(distinct voter_id)` |
| Dnevna stopa glasanja | 45 % verificiranih | `votes/day ÷ voters` |
| Medijan niza nakon 14 dana | 6 dana | `voters.current_streak` |
| D7 retencija glasača | 40 % | glasao dan 1 → glasao dan 7 |
| Udio potrošenih zastavica | < 40 % | signal treba li podsjetnik (§11.1) |
| Gini raspodjele glasova | < 0,7 | signal treba li „trojka dana" (§3.1) |
| Konverzija posjetitelj → verificiran | ≥ 3 % | posjeti `/glasanje` → prvi glas |

---

## Izvori

[b1]: https://brilliant.org/help/using-brilliant/what-is-a-streak/
[b2]: https://brilliant.org/help/using-brilliant/what-is-a-streak-charge/
[d1]: https://medium.com/@salamprem49/duolingo-streak-system-detailed-breakdown-design-flow-886f591c953f
[d2]: https://yukaichou.com/gamification-study/master-the-art-of-streak-design-for-short-term-engagement-and-long-term-success/
[d3]: https://apptitude.io/blog/how-duolingos-streak-mechanic-actually-works/
[d4]: https://www.strivecloud.io/blog/gamification-examples-boost-user-retention-duolingo
[t1]: https://help.tryhackme.com/en/articles/7843540-streaks-streak-freezes-and-dodging-the-reset-button
[tr1]: https://trophy.so/blog/streak-timezone-dst-handling
[r1]: https://rive.app/blog/how-brilliant-org-motivates-learners-with-rive-animations

- Brilliant — [Što je streak][b1] · [Što je Streak Charge][b2]
- Duolingo — [detaljna razrada sustava][d1] · [teardown mehanike][d3] ·
  [4 pravila streak dizajna (Yu-kai Chou)][d2] · [utjecaj na retenciju][d4]
- TryHackMe — [streaks & streak freezes][t1]
- Trophy — [timezone & DST handling][tr1]
- Rive — [kako Brilliant animira streak][r1]
- Interno: `fetch.domovina.tv/data/podcasts_registry.json` (v1.2),
  `https://podcast-registry.domovina.ai/registry.json`,
  `domovina-api/supabase/migrations/20260529120000_identity_verifications.sql`,
  `domovina-api/supabase/functions/certilia/index.ts`,
  `domovina-api/docs/backend-architecture.md`
