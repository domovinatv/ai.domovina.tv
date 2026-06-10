# 10 — Account management (passkey list/delete + brisanje računa)

Frontend (`/account` ekran, `lib/screens/account/account_screen.dart`) je već
ožičen na endpointe ispod i graceful degradira dok ne postoje (404 →
"stiže uskoro" / uputa na privacy@italk.hr). Ovaj dokument je spec za
domovina-api implementaciju.

## 1. `passkey/list` — nova grana postojeće `passkey` edge funkcije

- **Ruta**: `POST /functions/v1/passkey/list` (prazan body `{}`)
- **Auth**: `verify_jwt=false` je na funkciji (zbog login grana) → grana MORA
  ručno verificirati `Authorization: Bearer <jwt>` header (isti pattern kao
  postojeći register/start za signed-in usera: `supabase.auth.getUser(jwt)`).
  Anonimni i nevaljani JWT → 401 `{"error":"unauthorized"}`.
- **Logika**: `select id, device_name, created_at, last_used_at from
  public.user_passkeys where user_id = <jwt user id> order by created_at`.
- **Response 200**:

```json
{ "passkeys": [
  { "id": "uuid", "device_name": "Mac", "created_at": "...", "last_used_at": "..." }
] }
```

## 2. `passkey/delete` — nova grana

- **Ruta**: `POST /functions/v1/passkey/delete`, body `{ "id": "<uuid>" }`
- **Auth**: isto kao list (JWT obavezan).
- **Logika**: `delete from public.user_passkeys where id = $1 and
  user_id = <jwt user id>` — `user_id` guard je obavezan (korisnik smije
  brisati samo svoje). 0 redova → 404 `{"error":"not_found"}`.
- **Response 200**: `{ "ok": true }`
- **Napomena**: NE blokirati brisanje zadnjeg passkeyja — korisnik se i dalje
  može prijaviti magic linkom / OAuth-om (e-mail uvijek postoji na računu).

## 3. `account-delete` — nova edge funkcija

App Store Guideline 5.1.1(v): app koji nudi kreiranje računa mora nuditi
i brisanje računa u appu. Flutter zove `client.functions.invoke('account-delete')`.

- **Ruta**: `POST /functions/v1/account-delete` (bez bodyja)
- **Auth**: `verify_jwt=true` (ili ručna verifikacija). Anonimni user → 400
  `{"error":"anonymous"}` (anon račune ne brišemo ovuda — GC ih čisti).
- **Logika** (service_role):
  1. `userId` iz JWT-a.
  2. Obriši per-product redove koji NEMAJU FK cascade na auth.users
     (provjeriti `domovina_ai.*` tablice; favorites/watch_progress/handoff/
     onboarding već referenciraju auth.users — ako je `on delete cascade`,
     korak je no-op).
  3. `public.user_passkeys` ima cascade — no-op.
  4. `identity_verifications` (enc OIB iz Certilia KYC) — OBAVEZNO obrisati
     (GDPR; PII se ne smije zadržati nakon brisanja računa).
  5. `await adminClient.auth.admin.deleteUser(userId)`.
- **Response 200**: `{ "ok": true }`
- **Edge case**: vlasnik kanala s aktivnim Safe payout postavkama — za sada
  dopustiti brisanje (Safe multisig je on-chain i ne ovisi o auth.users redu),
  ali logirati event za ručni follow-up.

## Deploy

Edge funkcije žive u git sourceu (`supabase/functions/`), deploy preko
`scripts/deploy-functions.sh` (vidi feedback_coolify_ops memoriju).
