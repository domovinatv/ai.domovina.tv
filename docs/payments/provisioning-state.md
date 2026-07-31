# Provisioning — stvarno stanje (log)

Što je **doista** provisionirano, s ID-evima, dokazima i datumima. Pandan
`provisioning.md`, koji opisuje *što mora postojati*; ovaj dokument bilježi *što
postoji i kako je provjereno*, plus zamke koje se ne vide iz koda.

Zadnja provjera: **2026-07-31**.

---

## 1. Komercijalni preduvjeti — OTVORENO na obje strane

Ovo je bio tvrdi gate ispred svega (bez njega se IAP proizvodi ne mogu ni
kreirati). Provjereno u konzolama 2026-07-31.

### Apple — ITalk d.o.o.

| Stavka | Stanje |
|---|---|
| Paid Apps Agreement | **Active**, 8. 6. 2026 – 17. 5. 2027, sve zemlje |
| Free Apps Agreement | Active, 16. 6. 2026 – 17. 5. 2027 |
| Bankovni račun | HPB (4819), Hrvatska, EUR, royalty valuta USD — Active |
| Porezne forme | U.S. Certificate of Foreign Status + W-8BEN-E — Active (23. 1. 2023) |
| Compliance | Digital Services Act + DAC7 (7. amandman) — Active |

### Google — ITalk Ltd.

- Payments profil postoji (nema blokade „set up a payments profile" na
  Subscriptions stranici; Monetization setup je živ s licensing ključem).
- `ai.domovina` je u **Production**, zadnji release 10. 7. 2026 (v2.0.74).

---

## 2. RevenueCat — ID-evi

Projekt **DOMOVINA** = `projb53a2472`.

| Objekt | ID |
|---|---|
| App Store app | `appd2362fe55f` — „DOMOVINA.ai (iOS)", bundle `ai.domovina` |
| Play Store app | `app1ab026387a` — „DOMOVINA.ai (Android)", package `ai.domovina` |
| Test Store app | `app9c4cb97e9e` (stariji, ostaje za test putanju) |
| Entitlement | `entlb2b5d96f1b` = `domovina_plus` |
| Offering | `ofrngb784f920af` = `default` (is_current) |
| Package `$rc_monthly` | `pkge0aa06706de` |
| Package `$rc_annual` | `pkgec883c0cf72` |
| Package `$rc_lifetime` | `pkgea5cc6e1dfa` |

### Proizvodi (svi zakačeni na `domovina_plus`)

| | iOS (`appd2362fe55f`) | Android (`app1ab026387a`) |
|---|---|---|
| Mjesečno | `ai.domovina.plus.monthly` → `prod3f82e308df` | `domovina_plus_monthly:monthly` → `prod64d212ad74` |
| Godišnje | `ai.domovina.plus.yearly` → `prod502758c3f4` | `domovina_plus_yearly:yearly` → `prod69155fe421` |
| Doživotno | `ai.domovina.plus.lifetime` → `prod6e627278bc` | `domovina_plus_lifetime` → `prod13be265c4c` |

Svaki paket drži **tri** proizvoda (iOS + Android + Test Store); SDK bira po
platformi, pa test putanja i dalje radi.

> **Play format**: `store_identifier` za pretplate MORA biti
> `productId:basePlanId`. Za jednokratne proizvode ide goli SKU.

### Public SDK ključevi

Client-embeddable (završe u binaryju), pa nisu tajna. Žive u `.env`, a
`scripts/build-mobile-release.sh` ih ubacuje kao `--dart-define`:

```
RC_PUBLIC_SDK_KEY_IOS=appl_MqAqoMJHARBAHKTDqzQABleKShJ
RC_PUBLIC_SDK_KEY_ANDROID=goog_gzYTwerlNwBPayYGfcesWACQiQz
```

Čitaju se u `lib/services/revenue_cat/revenue_cat_service_native.dart` preko
`String.fromEnvironment`. Prije 2026-07-31 nisu postojali → kupnja je u store
buildovima bila no-op.

---

## 3. Apple kredencijali

- Team `6SCK58757K` (ITalk d.o.o.), App Store app id `6781716801`.
- **Vendor number `87530352`** — RC ga je sam povukao preko ASC API-ja, što je
  ujedno dokaz da veza radi (a ne da je ključ samo spremljen kao tekst).
- **Issuer ID `69a6de85-f7cc-47e3-e053-5b8c7c11a4d1`** — isti za ASC API i za
  In-App Purchase ključeve.
- **ASC API ključ `25KYCN22QD`** — `~/.appstoreconnect/private_keys/AuthKey_25KYCN22QD.p8`.
  Koristi ga i `scripts/build-mobile-release.sh` (xcodebuild) i RevenueCat
  („App Store Connect API" sekcija).
- **In-App Purchase ključ `9H7HMZ4M53`** — kreiran 31. 7. 2026,
  `~/.appstoreconnect/private_keys/SubscriptionKey_9H7HMZ4M53.p8`.
- **Master Shared Secret** postoji (generiran 4. 10. 2023), vidljiv i kopirljiv
  u ASC → Users and Access → Integrations → Shared Secret. Vrijednost NIJE u
  repou. Legacy put za validaciju računa; IAP ključ je moderniji.
- Stariji IAP ključ **`2SPM9XAPS8`** („RevenueCat Mulligan M Demo", skinut
  1. 2. 2023) je *siroče* — `.p8` nije ni na jednom našem stroju, a Apple ga ne
  da ponovno skinuti. Ne koristiti; može se opozvati.

> **Zamka**: IAP `.p8` se skida **samo jednom**, pri kreiranju. Izgubljen ključ =
> novi ključ (limit 10 aktivnih). Isto vrijedi i za ASC API ključeve.

### Stanje u RevenueCatu (provjereno `get-app`)

```
subscription_key_configured         : true
app_store_connect_api_key_configured: true
app_store_connect_vendor_number     : 87530352
```

---

## 4. Google kredencijali i notifikacije

- Play developer account **ITalk Ltd.** = `7441230488937961517`;
  Play app id `4974512212242280565`.
- Service account **`play-publisher@domovina-production.iam.gserviceaccount.com`**
  (JSON: `~/.config/play-publisher/domovina-play-publisher.json`), GCP projekt
  `domovina-production`.
  - U Play Consoleu: **Active, never expires, Admin (all permissions)** — pokriva
    „View financial data" i „Manage orders and subscriptions" koje RC traži.

### Real-time developer notifications (RTDN) — RADI

Postavljeno 2026-07-31, gcloudom/REST-om preko ADC-a:

1. Topic `projects/domovina-production/topics/revenuecat-play-notifications`
2. Na topicu: `roles/pubsub.publisher` za
   `google-play-developer-notifications@system.gserviceaccount.com`
   (bez toga Google Play ne smije objavljivati)
3. Na projektu: `roles/pubsub.editor` za naš SA
4. RevenueCat („Connect to Google") sam kreirao pretplatu
   `projects/domovina-production/subscriptions/RevenueCat-Subscriber-app1ab026387a`
5. Play Console → Monetization setup: RTDN uključen, topic upisan,
   **Notification content = „Subscriptions, voided purchases, and all one-time
   products"** (uža opcija ne bi pokrila doživotni SKU)

**Dokaz da lanac radi**: testna notifikacija iz Play Consolea → RC pokazuje
`Last received 2026-07-31, 7:02 UTC`.

> **Zamka (velika)**: Play Console ovlasti i GCP IAM su **dva odvojena sustava**.
> Naš SA je bio Admin u Play Consoleu, a u GCP projektu nije imao **nijednu**
> rolu — RC zato nije mogao ni izlistati Pub/Sub topice (prazan dropdown,
> `pubsub.topics.list` denied). Rješenje je bila IAM rola na GCP projektu.

---

## 5. Što API pokriva, a što ne

### RevenueCat API (preko hosted MCP-a)

Radi: `create-app`, `create-product`, `attach-products-to-entitlement`,
`attach-products-to-package`, `list-app-public-api-keys`, `get-app`,
`set-product-store-state` (piše proizvode **u same trgovine** — cijene po
teritoriju, lokalizacije, subscription grupe, base planovi, offeri, trial),
`submit-products-to-store`.

Ne radi / zamke:

- **`create-app` prima samo `bundle_id` / `package_name`** — nema polja za
  kredencijale. `update-app` ih ipak prima
  (`subscription_key_id`, `subscription_key_issuer`, `subscription_private_key`,
  `app_store_connect_api_key*`, `shared_secret`). Za Play nema polja — SA JSON
  ide isključivo kroz dashboard.
- **`get-app` ne izlaže stanje Play kredencijala.** Za App Store vraća
  `subscription_key_configured` / `app_store_connect_api_key_configured`, za Play
  ništa — provjera je vizualna („Valid credentials" u dashboardu).
- **`submit-products-to-store`**: Apple traži da **prva** pretplata/IAP ide uz
  **novu verziju appa** kroz App Store Connect. RC taj proizvod preskoči i to
  eksplicitno javi. Tek sljedeći idu API-jem.
- **RC MCP je udaljeni HTTP server** (`https://mcp.revenuecat.ai/mcp`) —
  autentikacija ne ostavlja tajni ključ lokalno, pa nema curl fallbacka. Sve ide
  kroz MCP alate.

### Console-only (nema API ni kod Applea ni Googlea)

App Privacy / Data safety, IARC content rating, age rating detalji, app access,
ads, target audience, financial features, Paid Apps agreement i bankovni/porezni
podaci, Play payments profil, App Store Server Notifications URL-ovi, Web
Billing / Stripe connect.

### gcloud / GCP

`gcloud auth list` je imao samo servisne račune; radna putanja bio je **ADC**
(`~/.config/gcloud/application_default_credentials.json`), autoriziran kao
`stepanic.matija@gmail.com` sa `cloud-platform` scopeom. Preko njega su Pub/Sub i
Resource Manager REST API-ji radili bez ikakvog interaktivnog logina:

```bash
TOKEN=$(gcloud auth application-default print-access-token)
```

Za IAM promjene koristiti getIamPolicy → izmjena → setIamPolicy **s etagom**
(read-modify-write nad cijelom politikom projekta).

---

## 6. Preostalo

1. **Apple App Store Server Notifications** — ASC → app → App Information →
   „App Store Server Notifications" → Production i Sandbox „Set Up URL". URL se
   kopira iz RC iOS app stranice („Apple Server to Server notification
   settings"). Trenutno neposta­vljeno; RC javlja „No notifications received".
   Ovo je Appleov pandan Play RTDN-u.
2. **Pravi store proizvodi s cijenama** — ne postoje ni u ASC-u ni u Play
   Consoleu. Kreiranje ide preko RC `set-product-store-state` (+ Appleovo
   ograničenje za prvi proizvod iz §5). Prijedlog cijena i trial: vidi
   `pricing-and-tiers.md`.
3. **Web Billing (Stripe)** — nije dirano.
4. **Higijena**: radne kopije ključeva na Desktopu i u Downloadsu
   (`AuthKey_25KYCN22QD.p8`, `SubscriptionKey_9H7HMZ4M53.p8`,
   `domovina-play-publisher.json`) obrisati kad provisioning završi. Originali su
   u `~/.appstoreconnect/private_keys/` i `~/.config/play-publisher/`.
5. **Backup**: IAP i ASC `.p8` ključevi te Android upload keystore nisu
   regenerabilni na isti identitet — pripadaju u offsite backup.

---

## 7. Povezano

- `provisioning.md` — plan (što mora postojati), redoslijed, checklista
- `architecture.md` — jedan entitlement, jedan webhook, tok podataka
- `pricing-and-tiers.md` — cjenik i pakiranje
- `docs/mobile-release-pipeline.md`, `docs/release-mobile.md` — build i upload
- `domovina-api/supabase/functions/revenuecat-webhook/` — webhook (Edge Function,
  **ne** Cloudflare Worker; piše našu bazu)
