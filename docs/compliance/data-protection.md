# Zaštita osobnih podataka — master dokument (ROPA / DPIA / TOMs)

> **NACRT — nije pravni savjet.** Vidi [`README.md`](README.md). Polja `‹…›`
> popunjava voditelj obrade / DPO prije korištenja.

Utemeljeno na: GDPR (Uredba (EU) 2016/679), Zakon o provedbi OUZP (NN 42/2018),
smjernice AZOP-a i EDPB-a.

---

## 1. Voditelj obrade (Controller)

| Stavka | Vrijednost |
|---|---|
| Naziv pravne osobe | ‹tvrtka / obrt / udruga — popuniti› |
| OIB voditelja | ‹…› |
| Sjedište | ‹adresa› |
| Kontakt za privatnost | `privacy@domovina.ai` ‹potvrditi› |
| Službenik za zaštitu podataka (DPO) | ‹vidi §7 — procjena obveze› |

## 2. Evidencija aktivnosti obrade — ROPA (čl. 30)

### Obrada A — Račun i autentifikacija
- **Svrha:** prijava, identifikacija korisnika, sigurnost računa.
- **Pravna osnova:** čl. 6(1)(b) — izvršenje ugovora (pružanje usluge); za
  anonimne sesije čl. 6(1)(f) legitimni interes (kontinuitet korištenja).
- **Kategorije podataka:** e-mail (ako se koristi), provider identiteta, OAuth
  metapodaci (ime, avatar), passkey credential (javni ključ — nije PII osobe),
  tokeni sesije.
- **Ispitanici:** registrirani i anonimni korisnici.
- **Rok čuvanja:** za vrijeme postojanja računa; brisanjem računa se brišu.
- **Lokacija:** self-hosted Supabase (`auth.users`) na ‹EU regija / VPS lokacija›.

### Obrada B — Verifikacija identiteta (KYC) putem Certilia / NIAS eID
- **Svrha:** potvrda da je korisnik **stvarna, verificirana osoba** (priprema za
  regulirane funkcije, npr. self-custody wallet); sprječavanje višestrukih/lažnih
  računa.
- **Pravna osnova:** čl. 6(1)(a) **privola** (korisnik kroz Certilia consent
  ekran bira koje podatke dijeli) + čl. 6(1)(b) ako je nužno za uslugu. **Nije**
  čl. 9 (posebne kategorije) jer se **ne** obrađuje fotografija/biometrija.
- **Kategorije podataka:** **OIB** (nacionalni identifikator — osjetljiv),
  ime, prezime, datum rođenja, država. *Namjerno se NE prikupljaju:* fotografija,
  podaci o ispravi, adresa, spol, mobitel.
- **Izvor:** Certilia / NIAS (e-Osobna).
- **Rok čuvanja:** za vrijeme postojanja računa; briše se kaskadno pri brisanju
  računa. *(Ako wallet uđe pod AML — revidirati na zakonski rok, npr. +5 god.)*
- **Lokacija + zaštita:** `public.identity_verifications`; OIB **enkriptiran**
  (pgcrypto), pristup samo `service_role`.

### Obrada C — Korištenje sadržaja (watch progress, favoriti)
- **Svrha:** nastavak gledanja, personalizacija, sinkronizacija uređaja.
- **Pravna osnova:** čl. 6(1)(b) / (f).
- **Kategorije:** ID epizode, pozicija, vremenske oznake.
- **Rok čuvanja:** za vrijeme postojanja računa.

### Obrada D — Transakcijski e-mail (magic link / OTP)
- **Svrha:** prijava bez lozinke.
- **Pravna osnova:** čl. 6(1)(b).
- **Kategorije:** e-mail adresa.
- **Primatelj / izvršitelj obrade:** Resend (SMTP).

## 3. Pravna osnova — sažetak (čl. 6)

| Obrada | Osnova |
|---|---|
| Anonimna sesija | čl. 6(1)(f) legitimni interes |
| Račun (OAuth/email/passkey) | čl. 6(1)(b) ugovor |
| KYC (Certilia eID) | čl. 6(1)(a) privola + (b) nužnost |
| Sadržaj/napredak | čl. 6(1)(b)/(f) |

> **Zašto NE čl. 9:** posebne kategorije (biometrija) bi nastale obradom
> fotografije s e-Osobne. Sustav **ne prikuplja fotografiju** → izbjegnut je
> režim posebnih kategorija. OIB je nacionalni identifikator (čl. 87) — tretira
> se s pojačanim mjerama (enkripcija, minimizacija), ali nije čl. 9.

## 4. DPIA — procjena učinka (čl. 35)

**Screening:** obrada uključuje **nacionalni identifikator (OIB)** i namjeru
sustavne verifikacije identiteta → prema AZOP/EDPB kriterijima **DPIA je
preporučena/vjerojatno obvezna**. Ovaj dokument je njezina osnova:

- **Opis obrade:** §2 (Obrada B).
- **Nužnost i proporcionalnost:** prikuplja se *minimum* (OIB+ime+prezime+DOB+
  država); alternativa (samo email) ne daje pravnu sigurnost identiteta za
  buduće regulirane funkcije.
- **Rizici:** curenje OIB-a; povezivanje identiteta; neovlašteni pristup.
- **Mjere ublažavanja:** vidi §5 (TOMs) — enkripcija OIB-a, service-role-only
  pristup, Postgres nije javno izložen, minimizacija, brisanje s računom.
- **Rezidualni rizik:** ‹DPO procjenjuje›. Ako *visok* → **prethodna konzultacija
  s AZOP-om (čl. 36)** prije puštanja u produkciju.

## 5. Tehničke i organizacijske mjere — TOMs (čl. 32)

- **Enkripcija u mirovanju:** OIB `pgp_sym_encrypt` (pgcrypto); ključ u env-u
  (`KYC_ENCRYPTION_KEY`), ne u bazi/repou; disk enkripcija hosta ‹potvrditi›.
- **Enkripcija u prijenosu:** HTTPS/TLS svuda (Cloudflare + Kong); Postgres
  **nije javno izložen** (pristup samo SSH + docker exec).
- **Kontrola pristupa:** RLS na svim tablicama; KYC tablica service-role-only;
  OIB ne izlazi klijentu (samo `my_identity_status()` siguran subset); Supabase
  Studio iza Cloudflare Zero Trust.
- **Anti-dup integritet:** `oib_hash` (HMAC) unique → jedna osoba = jedan račun.
- **Odgovornost / audit:** `activity_events` append-only.
- **Backup:** pre-migracijski snapshotovi; ‹politika backupa + enkripcija backupa›.
- **Minimizacija:** vidi §2 Obrada B.

## 6. Prava ispitanika (čl. 15–22)

| Pravo | Kako se izvršava |
|---|---|
| Pristup (15) | `my_identity_status()` + export računa ‹TODO endpoint› |
| Ispravak (16) | ponovni Certilia login osvježi podatke (upsert) |
| Brisanje / zaborav (17) | brisanje računa → `on delete cascade` briše KYC + sve |
| Ograničenje (18) | ‹postupak› |
| Prenosivost (20) | ‹export u strojno čitljivom formatu — TODO› |
| Prigovor (21) | `privacy@domovina.ai` |

Rok za odgovor: **1 mjesec** (čl. 12(3)).

## 7. Službenik za zaštitu podataka — DPO (čl. 37)

Obveza imenovanja DPO-a postoji kod *redovite i sustavne opsežne obrade* ili
*opsežne obrade posebnih kategorija*. Obrada OIB-a + planirani wallet → **procijeniti
obvezu**; ako se imenuje, kontakt objaviti u Politici privatnosti i prijaviti AZOP-u.
‹DPO procjena — TODO›.

## 8. Povreda osobnih podataka (čl. 33/34)

- Prijava **AZOP-u u roku 72 h** od saznanja (osim ako nije vjerojatan rizik).
- Obavijest ispitanicima ako je **visok rizik**.
- Postupak: detekcija → procjena opsega → izolacija → prijava → evidencija u
  internom registru povreda. ‹kontakt osoba / runbook — TODO›.

## 9. Sub-procesori / primatelji i prijenosi

| Primatelj | Uloga | Podaci | Lokacija |
|---|---|---|---|
| Self-hosted Supabase (VPS/Coolify) | obrada/pohrana | svi | ‹EU — potvrditi VPS regiju› |
| Certilia / NIAS (AKD) | izvor eID identiteta | OIB, ime, DOB, država | HR/EU |
| Resend | slanje e-maila | e-mail adresa | ‹regija — potvrditi DPA› |
| Google | OAuth prijava | e-mail, profil | EU/SAD ‹SCC/DPF› |
| Cloudflare | CDN/hosting/TLS | tehnički/IP | globalno ‹DPF/SCC› |

Za svakog sub-procesora osigurati **Ugovor o obradi (DPA, čl. 28)** i, za prijenose
izvan EU, odgovarajući mehanizam (DPF/SCC). ‹potvrditi po procesoru›.

---

_Zadnje ažurirano: 2026-05-29. Vlasnik dokumenta: ‹DPO / voditelj obrade›._
