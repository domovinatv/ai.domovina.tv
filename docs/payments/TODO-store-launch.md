# TODO do lansiranja naplate

Stanje na dan **2026-07-31**. Puni kontekst i zamke: `provisioning-state.md`.
Ovdje je samo popis onoga što još treba, podijeljen po tome **tko to može
odraditi**.

---

## ✅ Gotovo (ne treba ti ništa)

- Apple i Google komercijalni preduvjeti (agreementi, banka, porezi) — provjereno
- RevenueCat: oba store appa, 6 proizvoda, entitlement, offering, SDK ključevi u `.env`
- Apple kredencijali u RC (IAP ključ + ASC API ključ + vendor number)
- Play kredencijali u RC + **RTDN radi** (dokazano testnom notifikacijom)
- **Apple App Store Server Notifications** — Production i Sandbox URL upisani
  (RC gumb „Apply in App Store Connect", ne ručno)
- **Store proizvodi — svi na cilju**:
  - Apple: sva tri **Ready to Submit** (cjenik equaliziran, grupa lokalizirana)
  - Play: sva tri **Published** (eurozona, 4,99 / 39,99 / 99,99 € za kupca)
- Plan za pošten paywall napisan i predan timu

---

## 🔴 Blokira sve ostalo

**Uskladiti paywall sa stvarnošću.** Dok to ne padne, ne slati build s IAP-om.
Plan: `docs/plans/2026-07-31-plus-posteni-paywall.md`, predan timu preko
`scripts/tim.sh`. Nakon toga: deploy weba pa mobilni build.

---

## 👤 Tvoje (nema API, moraš ti)

1. **Data safety (Google) i App Privacy (Apple)** — provjeriti treba li dopuna
   sad kad postoji naplata. Vjerojatan kandidat: „Purchase history" u Data
   safety obrascu. Konzolni obrasci, nema API-ja.
2. **Store listing tekst** u obje konzole — ažurirati tek kad tim isporuči
   `docs/payments/store-listing-copy.md` (task T4 iz plana). Provjeriti i
   screenshotove u `store-assets/` da ne prikazuju nepostojeće funkcionalnosti.
3. **Odluka o probnom razdoblju** (npr. 7 dana na godišnjem). Nije postavljeno.
   Kad odlučiš, ja to upišem jednim pozivom.
4. **Brisanje radnih kopija ključeva** s Desktopa i iz Downloadsa — rekao si da
   ćeš sam. Originali ostaju u `~/.appstoreconnect/private_keys/` i
   `~/.config/play-publisher/`.
5. **Offsite backup** neregenerabilnih ključeva: oba `.p8` + Android upload
   keystore. Gubitak = nema više updatea pod istim identitetom.
6. **Ne-euro tržišta na Playu** — Play pretplate su trenutno dostupne samo u
   **21 zemlji eurozone**, jer Play traži eksplicitnu cijenu po zemlji i ne
   prihvaća fallback. Za GB, CH, SE, NO, DK, PL, CZ, HU, RO, US, CA, AU i ostale
   treba odlučiti cijenu u lokalnoj valuti. Nisam ih izmišljao. Apple to nema —
   ondje `equalize` sam izračuna iz hrvatske cijene.

---

## 🤖 Moje (reci i odradim)

1. **Trial** na godišnjem, ako odlučiš da ide.
2. **Build + upload** na TestFlight i Play Internal — čim paywall bude usklađen.

---

## ⛔ Ograničenja koja se ne mogu zaobići

- **Prva Appleova pretplata mora u review uz novu verziju appa.** RC-ov
  `submit-products-to-store` je odbija i to eksplicitno javi. Znači: paywall
  fix → build → nova verzija → tek onda proizvodi u review.
- App u ASC-u trenutno stoji na **2.0.74**, repo je na 2.0.126+ — nova verzija
  ionako treba.
- Sam **review** (Apple i Google) traje koliko traje; to nitko od nas ne ubrzava.
