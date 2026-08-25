# Podsjetnici za niz („Izborni dan") — plan

**Status**: plan, nije implementirano. Obara odluku 4 iz
`docs/plans/2026-08-08-glasanje-predaja.md` („bez podsjetnika u v1").

## 1. Zašto

Zastavice ne mogu spasiti niz korisniku koji ne zna da mu niz curi. Izmjereno na
produkciji 25.8.2026.: glas 12.8., pa 12 propuštenih dana, pa glas 25.8. Kroz tih
12 dana nije postojao nijedan signal — ni u aplikaciji (korisnik nije dolazio),
ni izvan nje (nema podsjetnika). Mehanika koja nagrađuje dnevni povratak, a nema
kanal prema van, u praksi radi samo za ljude koji ionako dolaze svaki dan.

Brilliant, Duolingo i ostali na koje se ovaj sustav ugleda **svi** imaju
podsjetnik. Streak bez podsjetnika je pola mehanike.

**Protuargument koji treba čuti prije nego se ovo gradi**: danas ima **5**
verificiranih korisnika i **1** glasača. Podsjetnici ne rješavaju taj problem —
rješava ga dovođenje ljudi kroz Certiliju (rail „Tko ide sljedeći", `v2.0.138`).
Ovaj plan ima smisla tek kad brojka glasača bude dvoznamenkasta. Do tada je to
infrastruktura koja čeka publiku.

## 2. Koga i kada

Kandidat za podsjetnik je glasač koji **istovremeno**:

- ima `current_streak > 0` (nema smisla braniti niz koji ne postoji),
- **nije** glasao danas,
- ima `user_id` koji nije `null` (bez računa nema adrese — `voters` namjerno ne
  drži PII, §4.1 dizajna),
- ima `reminders_enabled = true`.

Dan slanja: **posljednji dan na koji glas još spašava niz.**

Niz preživi dok je `propušteno ≤ zastavice`, gdje je
`propušteno = danas − last_vote_day − 1`. Zadnji spasonosni dan je zato:

```
danas = last_vote_day + flags + 1
```

Primjeri (`last_vote_day = 12.8.`):

| zastavice | zadnji spasonosni dan | podsjetnik |
|---|---|---|
| 0 | 13.8. | 13.8. |
| 1 | 14.8. | 14.8. |
| 2 | 15.8. | 15.8. |

**Jedan podsjetnik po prilici, ne dnevna kampanja.** Drugi mail („niz ti je
pukao") se NE šalje — to je loša vijest bez radnje, a korisnik ju ionako vidi u
zaglavlju kad dođe.

Otvoreno pitanje za odluku: dodati i **blagi** podsjetnik na prvi propušteni dan
(`danas = last_vote_day + 1`) kad korisnik ima zastavice? Argument za: uči ga da
zastavice postoje. Argument protiv: dva maila u tri dana za feature koji je
sporedan. **Preporuka: ne u prvoj verziji.**

## 3. Kanal

**E-mail preko Resenda.** Već je ožičen — `supabase/functions/auth-send-email`
pokazuje cijeli obrazac (RESEND_API_KEY, `POST https://api.resend.com/emails`).

Web push je **svjesno odgođen**: traži VAPID ključeve, service worker granu za
`push`/`notificationclick`, permission prompt (koji je sam po sebi nudge preko
sadržaja — CLAUDE.md pravilo), a na iOS-u radi tek za PWA dodan na home screen.
Nesrazmjerno velik zahvat za feature koji trenutno ima jednog korisnika.

Native push (APNs/FCM) je još veći — aplikacija danas nema nikakav push stack.

## 4. Raspored

`pg_cron` **nije instaliran** na produkciji (provjereno 25.8.2026. —
`pg_extension` ima `pg_net`, nema `pg_cron`), pa raspoređivanje ne može u bazu.

Sat ide u **Cloudflare Worker Cron Trigger**, odluka i slanje u **Supabase Edge
Function** — po pravilu iz CLAUDE.md („piše našu bazu → Edge Function"):

```
CF Worker cron (svaki sat, UTC)
   → POST https://api.domovina.ai/functions/v1/voting-reminders
        (shared secret u headeru)
   → Edge Function:
        1. je li u Zagrebu 18:00? ako nije → 200 no-op
        2. select kandidata (§2) preko service rolea
        3. za svakog: insert u voter_reminders (idempotencija) → Resend
        4. vrati brojke
```

**Zašto Worker, a ne launchd na Mac miniju**: nightly build i tripwire smiju
ovisiti o tome je li Mac budan — podsjetnik ne smije. Ako Mac spava u 18:00,
korisnik ostane bez jedine prilike da spasi niz.

**Zašto svaki sat, a ne jednom dnevno u 16:00 UTC**: Hrvatska mijenja sat, a
Worker cron je UTC. Satni okidač + provjera lokalnog sata u funkciji je
jednostavnije i otpornije od dva cron izraza po sezoni.

18:00 po hrvatskom: dovoljno kasno da je dan „skoro gotov", dovoljno rano da
korisnik stigne otvoriti aplikaciju.

## 5. Shema

```sql
-- migracija: <ts>_voting_reminders.sql   (NOVI fajl, ne uređuj postojeće)

alter table domovina_ai.voters
  add column if not exists reminders_enabled boolean not null default true;

create table if not exists domovina_ai.voter_reminders (
  voter_id  uuid not null references domovina_ai.voters(id) on delete cascade,
  vote_day  date not null,
  kind      text not null default 'last_chance'
            check (kind in ('last_chance', 'at_risk')),
  sent_at   timestamptz not null default now(),
  primary key (voter_id, vote_day, kind)
);
```

Primarni ključ **jest** idempotencija: dva okidača u istom satu ne mogu poslati
dva maila. Bez RLS policy-ja — tablicu dira samo `service_role`, kao `voters`.

`reminders_enabled` na `voters`, ne na `auth.users`: pripada glasačkom
identitetu koji preživljava brisanje računa (§4.1).

## 6. Sadržaj maila

Registar „ti", bez ALL-CAPS, dijakritici obavezni (CLAUDE.md, lektor).

- **Subject**: „Tvoj niz ističe večeras" (bez emojija u subjectu — Gmail ih reže).
- **Tijelo**: niz koliko dana, koliko zastavica brani, jedan gumb „Glasaj" →
  `https://domovina.ai/glasanje`.
- **Nikad** ne navodi za koga da glasa i ne spominje pojedinog kandidata — to bi
  bilo usmjeravanje glasanja i ruši legitimitet (isti razlog zbog kojeg je §3
  filtar registra namjerno samo tehnički).
- Footer: „Ne želiš ove podsjetnike?" → odjava.

**Odjava mora raditi bez prijave** (jedan klik iz maila, ne „prijavi se pa nađi
postavku"). Potpisani token u linku → `voting-reminders-unsubscribe` funkcija →
`reminders_enabled = false`. Uz to prekidač na `/account`.

`List-Unsubscribe` header obavezan.

## 7. Pravno

Podsjetnik ide **verificiranom građaninu koji je već glasao** — to je servisna
poruka o njegovoj vlastitoj aktivnosti, ne marketing. Osnova: legitiman interes
(čl. 6(1)(f)), uz bezuvjetnu odjavu. Ipak: prekidač je `default true`, pa to
**mora** pisati u `/privacy` prije prvog slanja i biti spomenuto u ekranu privole
(§4.3), koji se ionako prikazuje prije prvog glasa.

Ako se odluči na `default false`, feature praktički ne postoji — nitko ga neće
uključiti. Preporuka: `true` + vidljiva odjava + dopuna `/privacy`.

## 8. Isporuka

| # | Zadatak | Repo | Ovisi o |
|---|---|---|---|
| R1 | Migracija: `reminders_enabled` + `voter_reminders` | domovina-api | — |
| R2 | Edge Function `voting-reminders` (odabir + Resend + upis) | domovina-api | R1 |
| R3 | Edge Function `voting-reminders-unsubscribe` (potpisani token) | domovina-api | R1 |
| R4 | CF Worker cron trigger → R2 | domovina.ai (`web/_worker.js`) | R2 |
| R5 | Prekidač na `/account` + ARB (`votingReminders*`) | domovina.ai | R1 |
| R6 | Dopuna `/privacy` i ekrana privole | domovina.ai | — |

R1–R3 su jedan dan posla, R4–R6 pola. Redoslijed: R1 → R2 → (R3 ‖ R5) → R4 → R6.
**R6 ide prije nego se R4 upali** — ne šalji prvi mail dok pravni tekst ne stoji.

## 9. Kako se zna da radi

- `voter_reminders` raste, a `votes` istog dana raste s njim → mjeri se udio
  poslanih podsjetnika nakon kojih je glas stvarno dan.
- Kontrolna brojka koja mora ostati 0: podsjetnik poslan korisniku koji je toga
  dana već glasao.
- Ako udio konverzije padne ispod ~15 % kroz mjesec dana, podsjetnik ne radi
  posao i copy se mijenja — ili se feature gasi, ne pojačava.
