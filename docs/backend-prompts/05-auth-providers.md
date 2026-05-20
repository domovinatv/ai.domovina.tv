# 05 — Auth providers (Google + Apple + Email magic + Passkey)

> **Cilj:** konfigurirati GoTrue za sva 4 sign-in providera koje Flutter mock već prikazuje.
>
> **Reference:** `docs/auth-and-database-plan.md` §Tech stack odluka.

---

## Prompt za Claude Code (configuration, ne SQL)

```
Trebam konfigurirati Supabase GoTrue (self-hosted na Coolify, domain
api.domovina.ai) za 4 providera. Env vars idu u Coolify Supabase service
configuration; restart container nakon svake izmjene.

Pravilo: SVE redirect-e moraju biti HTTPS osim localhost-a. SITE_URL =
'https://domovina.ai'. ADDITIONAL_REDIRECT_URLS = lista svih budućih
domovina.* domena + 'http://localhost:*' za dev.

=== 1. Anonymous sign-in ===
GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED=true
(Klijent: supabase.auth.signInAnonymously() → vraća session bez emaila.)

=== 2. Email magic link / OTP ===
GOTRUE_MAILER_AUTOCONFIRM=false
GOTRUE_EXTERNAL_EMAIL_ENABLED=true
GOTRUE_SMTP_HOST=<npr. mailgun ili resend SMTP relay>
GOTRUE_SMTP_PORT=587
GOTRUE_SMTP_USER=<smtp user>
GOTRUE_SMTP_PASS=<smtp pass>
GOTRUE_SMTP_ADMIN_EMAIL=noreply@domovina.ai
GOTRUE_SMTP_SENDER_NAME=DOMOVINA.ai
GOTRUE_MAILER_OTP_LENGTH=6
GOTRUE_MAILER_OTP_EXP=300  -- 5 minuta

Custom email template — `magic_link.html`:
- Title hrvatski: "Tvoja prijava na DOMOVINA.ai"
- Link: {{ .ConfirmationURL }}
- OTP code: {{ .Token }}
- "Ako nisi ti tražio prijavu, ignoriraj ovaj email."

=== 3. Google OAuth ===
GOTRUE_EXTERNAL_GOOGLE_ENABLED=true
GOTRUE_EXTERNAL_GOOGLE_CLIENT_ID=<iz Google Cloud Console>
GOTRUE_EXTERNAL_GOOGLE_SECRET=<isto>
GOTRUE_EXTERNAL_GOOGLE_REDIRECT_URI=https://api.domovina.ai/auth/v1/callback

Setup koraci:
1. Otvori Google Cloud Console → OAuth 2.0 Client.
2. Authorized JavaScript origins: https://domovina.ai
3. Authorized redirect URIs: https://api.domovina.ai/auth/v1/callback
4. Scopes: openid email profile.

=== 4. Apple Sign In (obavezno za iOS App Store kasnije) ===
GOTRUE_EXTERNAL_APPLE_ENABLED=true
GOTRUE_EXTERNAL_APPLE_CLIENT_ID=<Services ID iz Apple Developer>
GOTRUE_EXTERNAL_APPLE_SECRET=<JWT generiran iz privatnog ključa, refresh svakih 6 mjeseci>
GOTRUE_EXTERNAL_APPLE_REDIRECT_URI=https://api.domovina.ai/auth/v1/callback

Setup koraci:
1. Apple Developer → Identifiers → Services ID:
   - Domains: api.domovina.ai
   - Return URLs: https://api.domovina.ai/auth/v1/callback
2. Generiraj Sign In with Apple private key (.p8).
3. Build client_secret JWT (Apple zahtjeva, vrijedi do 6 mjeseci):
   - alg: ES256
   - kid: Key ID
   - iss: Team ID
   - sub: Services ID
   - aud: https://appleid.apple.com
   - iat / exp do 15777000s (~6 mj)
   Skripta primjer u `scripts/apple-client-secret.mjs` koja generira ovaj JWT.

=== 5. Passkey / WebAuthn ===

GoTrue još nema first-class passkey support (provjeri za nove verzije nakon
v2.180.0; ako podržava nativno → koristi to umjesto custom).

Trenutni approach — manual WebAuthn integration:

a) Tablica za credentialse:
```
sql/migrations/005_passkeys.sql:

create table if not exists public.user_passkeys (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  credential_id text not null unique,           -- base64url
  public_key bytea not null,                    -- COSE key
  sign_count bigint not null default 0,
  transports text[],                            -- ['internal','hybrid','usb']
  device_name text,
  created_at timestamptz not null default now(),
  last_used_at timestamptz
);

create index if not exists ix_passkeys_user on public.user_passkeys(user_id);
alter table public.user_passkeys enable row level security;

create policy passkeys_read on public.user_passkeys
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy passkeys_write on public.user_passkeys
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
```

b) Edge function ili dedicirani mali Node servis na `api.domovina.ai/passkey/*`:
   - POST /passkey/register/start — vrati WebAuthn challenge + relying party info.
   - POST /passkey/register/finish — verificiraj attestation, insertiraj u user_passkeys.
   - POST /passkey/login/start — vrati assertion challenge (po user_id ili discovery).
   - POST /passkey/login/finish — verificiraj signature, vrati GoTrue JWT
     (preko `auth.admin.generateLink` ili custom JWT signed with GOTRUE_JWT_SECRET).

   Library: `@simplewebauthn/server` (Node). Relying party ID = 'domovina.ai'.

c) Flutter strana koristi `passkeys` Flutter package za WebAuthn API
   (`navigator.credentials.create` na webu).

=== 6. Provjeri GoTrue restart ===

Coolify → Supabase project → Restart → odaberi `auth` (GoTrue) container.

=== 7. Verifikacija ===

```bash
# Anonymous signup:
curl -X POST 'https://api.domovina.ai/auth/v1/signup' \
  -H "apikey: $ANON_KEY" -H "Content-Type: application/json" -d '{}'

# Email magic link:
curl -X POST 'https://api.domovina.ai/auth/v1/otp' \
  -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","create_user":true}'
# Provjeri inbox.

# Google OAuth — otvori u browseru:
# https://api.domovina.ai/auth/v1/authorize?provider=google&redirect_to=https://domovina.ai/
```

=== 8. Update Flutter env vars ===

Cloudflare Pages → domovina.ai project → Settings → Environment variables:
- SUPABASE_URL=https://api.domovina.ai
- SUPABASE_ANON_KEY=<iz Coolify Supabase config-a>

(Anon key je javan — embedirava se u Flutter web bundle.)
```

---

## Što ide u sljedeći korak

- `06-handoff-rpc.md` — RPC za M4 cross-device handoff.
