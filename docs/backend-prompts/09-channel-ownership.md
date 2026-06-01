# Prompt 09 — Channel ownership claim + Safe Multisig payout

**Kontekst:** implementira backend za feature "vlasnik YouTube kanala preuzima
vlasništvo i kupi sredstva iz per-epizoda Safe Multisig walleta". Pretpostavlja
da su prompti 01–08 izvršeni (accounts, profiles, domovina_ai schema, RLS,
auth provideri, handoff/anon migracije). KYC (Certilia) flow već postavlja
`auth.users.app_metadata.kyc_verified = true`.

**Repo:** `domovina-api` (zaseban od Flutter app repoa).
**Gdje:** `supabase/migrations/` (SQL) + `supabase/functions/` (edge funkcije).
**Master plan:** [`../channel-ownership-and-safe-payout-plan.md`](../channel-ownership-and-safe-payout-plan.md) — single source of truth (odluke D1–D4, dijagrami).

Flutter klijent je već implementiran i očekuje **točno** ove tablice/funkcije:
- `lib/services/channel_ownership_service.dart`
- `lib/services/wallet_service.dart`
- `lib/services/safe_service.dart`
- modeli: `channel_claim.dart`, `owner_wallet.dart`, `episode_safe.dart`

---

## A. SQL migracija — tablice + RLS

```sql
-- ── channel_claims ──────────────────────────────────────────────────────────
create table domovina_ai.channel_claims (
  id                  uuid primary key default gen_random_uuid(),
  account_id          uuid not null references auth.users(id) on delete cascade,
  youtube_channel_id  text not null check (youtube_channel_id ~ '^UC[0-9A-Za-z_-]{22}$'),
  channel_title       text,
  google_sub          text not null,
  role                text not null default 'primary'
                        check (role in ('primary','collaborator')),
  status              text not null default 'pending'
                        check (status in ('pending','verified','revoked','disputed')),
  method              text not null default 'youtube_oauth',
  verified_at         timestamptz,
  last_checked_at     timestamptz,
  created_at          timestamptz not null default now(),
  unique (account_id, youtube_channel_id)
);

-- D2: samo JEDAN verified primary po kanalu. Collaboratori neograničeno.
create unique index one_primary_per_channel
  on domovina_ai.channel_claims (youtube_channel_id)
  where (role = 'primary' and status = 'verified');

alter table domovina_ai.channel_claims enable row level security;

-- user vidi samo svoje claimove
create policy claims_select_own on domovina_ai.channel_claims
  for select using (account_id = auth.uid());
-- user smije INSERT samo pending claim za sebe (status mijenja service-role)
create policy claims_insert_own on domovina_ai.channel_claims
  for insert with check (account_id = auth.uid() and status = 'pending');
-- NEMA update/delete policy za usera → samo service-role (edge fn) mijenja status

-- ── episode_safes ───────────────────────────────────────────────────────────
create table domovina_ai.episode_safes (
  episode_id          text primary key,
  youtube_channel_id  text not null,
  safe_address        text not null,
  chain_id            integer not null,
  threshold           smallint not null default 2,
  status              text not null default 'active'
                        check (status in ('active','frozen','settled')),
  created_at          timestamptz not null default now()
);
alter table domovina_ai.episode_safes enable row level security;
-- metapodaci javno čitljivi (read-only); pisanje samo service-role
create policy safes_select_all on domovina_ai.episode_safes
  for select using (true);

-- ── owner_wallets ───────────────────────────────────────────────────────────
create table domovina_ai.owner_wallets (
  id            uuid primary key default gen_random_uuid(),
  account_id    uuid not null references auth.users(id) on delete cascade,
  address       text not null check (address ~ '^0x[0-9a-fA-F]{40}$'),
  verified_at   timestamptz,
  created_at    timestamptz not null default now(),
  unique (account_id, address)
);
alter table domovina_ai.owner_wallets enable row level security;
create policy wallets_all_own on domovina_ai.owner_wallets
  for all using (account_id = auth.uid()) with check (account_id = auth.uid());

-- ── safe_actions (audit) ────────────────────────────────────────────────────
create table domovina_ai.safe_actions (
  id            uuid primary key default gen_random_uuid(),
  episode_id    text not null references domovina_ai.episode_safes(episode_id),
  account_id    uuid references auth.users(id),
  action        text not null,
  safe_tx_hash  text,
  payload       jsonb,
  created_at    timestamptz not null default now()
);
alter table domovina_ai.safe_actions enable row level security;
-- user vidi akcije nad epizodama čiji je verified vlasnik
create policy actions_select_owner on domovina_ai.safe_actions
  for select using (
    exists (
      select 1
      from domovina_ai.episode_safes es
      join domovina_ai.channel_claims cc
        on cc.youtube_channel_id = es.youtube_channel_id
      where es.episode_id = safe_actions.episode_id
        and cc.account_id = auth.uid()
        and cc.status = 'verified'
    )
  );
-- INSERT samo service-role
```

---

## B. Edge funkcija `youtube-claim` (start / callback / reverify)

Vlastiti, DEDICIRANI Google OAuth client (NE GoTrue Google login client —
Princip D iz plana). Env (feature-scoped `YOUTUBE_CLAIM_*` naming da se u Coolify
dijeljenom env poolu jasno odvoji od `GOTRUE_EXTERNAL_GOOGLE_*`):
`YOUTUBE_CLAIM_GOOGLE_CLIENT_ID`, `YOUTUBE_CLAIM_GOOGLE_CLIENT_SECRET`,
`YOUTUBE_CLAIM_REDIRECT_URI` (npr. `https://domovina.ai/youtube-claim/callback`).

### `POST /youtube-claim/start`
Body: `{ channelId: "UC…" }` (+ Authorization: Bearer <user jwt>).
1. Resolve user iz JWT-a (`not_signed_in` ako anon).
2. Generiraj PKCE (`code_verifier`/`code_challenge`) + `state` (random).
3. Spremi `{ state → (user.id, channelId, code_verifier, exp = now+10min) }`
   u kratkotrajni store (npr. tablica `domovina_ai.oauth_states` ili KV).
4. Vrati `{ authUrl }` — Google OAuth consent:
   - `scope=openid https://www.googleapis.com/auth/youtube.readonly`
   - `access_type=offline`, `include_granted_scopes=true`
   - `state`, `code_challenge`, `code_challenge_method=S256`
   - `redirect_uri=YOUTUBE_CLAIM_REDIRECT_URI`

### `POST /youtube-claim/callback`
Body: `{ code, state }`.
1. Dohvati i obriši `state` iz store-a; provjeri exp (`invalid_state` inače).
2. **Server-side** code→token exchange (s `code_verifier`).
3. `GET https://www.googleapis.com/youtube/v3/channels?part=id,snippet&mine=true`
   (Authorization: Bearer <access_token>).
4. Ako nema kanala → `no_channel`. Skupi sve vraćene `channel.id` (Brand Account
   delegirani manageri → više kanala; D2 dopušta).
5. Usporedi s `channelId` iz state-a:
   - **mismatch** → `{ ok:false, reason:'channel_mismatch' }`
   - **match** → odredi `role`: ako već postoji verified primary za taj kanal
     (drugi account) → `role='collaborator'`, inače `'primary'`.
   - Ako postoji verified primary drugog accounta i ovaj traži primary →
     `already_claimed` (osim ako je isti account).
6. `upsert` u `channel_claims` (service-role): `status='verified'`,
   `verified_at=now()`, `last_checked_at=now()`, `google_sub=<id_token.sub>`,
   `channel_title=<snippet.title>`. Vrati `{ ok:true, claim: <row> }`.
7. Refresh token (ako postoji) enkriptiraj pgcrypto-om (kao OIB) — opcionalno,
   samo ako treba za reverify bez ponovnog consenta.

### `POST /youtube-claim/reverify`
Body: `{ claimId }`. D4: ponovi korak 3–6 (refresh token ili novi consent).
Ako kanal više nije među `mine=true` → `status='revoked'`, vrati
`{ ok:false, reason:'channel_mismatch' }`. Inače osvježi `verified_at`.

---

## C. Edge funkcija `safe-owner-add`

Body: `{ episodeId, address }` (+ user jwt).
1. Resolve user. Dohvati `episode_safes[episodeId]` (`no_safe` / `safe_frozen`).
2. **Re-provjeri eligibility server-side** (NE vjeruj klijentu):
   - verified `channel_claims` za `es.youtube_channel_id` + `account_id=user`
   - `verified_at` mlađi od 90 dana (inače → `reverify_needed`)
   - `kyc_verified == true` (inače → `kyc_required`). **VAŽNO:** čitaj
     `app_metadata` AUTORITATIVNO iz baze preko
     `admin.auth.admin.getUserById(user.id)`, NE iz `getUser()` tokena —
     password-grant/anon JWT ne odražava `kyc_verified` koji Certilia upiše
     naknadno (`updateUserById`). Lokalno potvrđeno: token tvrdi `true`, baza
     `false` → fn ispravno vrati `kyc_required`.
   - claim mora postojati (inače → `not_eligible`); adresa u `owner_wallets`
     (inače → `wallet_not_registered`)
3. Provjeri da je `address` u `owner_wallets` tog usera.
4. Preko Safe Transaction Service (chain `es.chain_id`): predloži
   `addOwnerWithThreshold(address, threshold)`. Platforma (trajni co-signer)
   potpiše svoj dio; izvrši kad threshold zadovoljen (D3, 2-of-N).
5. Loguj u `safe_actions` (`owner_add_proposed`, pa `owner_add_executed`).
6. Vrati `{ ok:true, safe_tx_hash }`.

Env: `SAFE_TX_SERVICE_URL`, `PLATFORM_SIGNER_KEY` (server-side only, nikad klijentu).

---

## D. Faza 0 preduvjet — `youtube_channel_id` u kanalima

Pipeline (`fetch.domovina.tv`) mora upisati `youtube_channel_id` (`UC…`, izvor
yt-dlp `channel_id`) u `channel.json`. Flutter modeli to već parsiraju
(`ChannelDetail.youtubeChannelId`) i fallbackaju na `/channel/UC…` iz URL-a.
Bez ovoga "Preuzmi vlasništvo" akcija je skrivena.

Opcionalno: dodaj `youtube_channel_id text` u `domovina_ai.channels` (ako
postoji) + index za server-side match.

---

## Lokalno testiranje (verificirano 2026-05-30)

```bash
# 1. migracija (db-migrate.sh je SSH-to-PROD; lokalno ide direktno psql)
psql "postgresql://postgres:postgres@127.0.0.1:55322/postgres" \
  -v ON_ERROR_STOP=1 -f supabase/migrations/20260530130000_channel_ownership.sql

# 2. deno check obiju fn
deno check supabase/functions/youtube-claim/index.ts
deno check supabase/functions/safe-owner-add/index.ts

# 3. VAŽNO: supabase CLI bakea listu funkcija + verify_jwt u edge container env
#    (SUPABASE_INTERNAL_FUNCTIONS_CONFIG) pri `supabase start`. NOVE funkcije ili
#    config.toml izmjene NE pokupi `docker restart` (ni `start` dok stack radi —
#    no-op) → treba PUN stop+start. DB volumeni ostaju, migracije perzistiraju.
#    Inače 404 "Function not found" (registry) ili 401 "Invalid JWT" (verify_jwt).
#    Izmjena SAMO koda postojeće fn → dovoljan `docker restart` (reload modula).
supabase stop && supabase start

# 4. ključevi:  supabase status -o env | grep -E 'ANON_KEY|SERVICE_ROLE_KEY'
#    (skini navodnike: sed -E 's/^[A-Z_]+="?([^"]*)"?$/\1/')
```

Pokriveno (sve prolazi): 8 SQL/RLS testova + edge E2E — youtube-claim/start
(not_signed_in / invalid_channel_id / authUrl+PKCE+oauth_state) i safe-owner-add
puni ladder (wallet_not_registered → ok:true+stub tx+audit → reverify_needed →
kyc_required). callback (Google consent) nije E2E.

## Acceptance kriteriji

- [ ] RLS enabled na sve 4 tablice; user NE može sam postaviti `status='verified'`
- [ ] `one_primary_per_channel` sprječava dva verified primary-ja istog kanala
- [ ] `youtube-claim/callback` radi code exchange **server-side**; access token
      nikad ne ide klijentu
- [ ] `channels.list?mine=true` match je jedini izvor istine za vlasništvo
- [ ] `safe-owner-add` re-provjeri (ownership ∧ KYC ∧ <90d) prije on-chain akcije
- [ ] `PLATFORM_SIGNER_KEY` / OAuth secret nisu izloženi klijentu
- [ ] Flutter `ChannelOwnershipService`/`WalletService`/`SafeService` rade E2E
- [ ] reverify postavlja `revoked` kad kanal više nije `mine=true`
```
