# 06 — Handoff RPC (M4 cross-device)

> **Cilj:** RPC funkcije za sigurno generiranje 6-znamenkastog koda na uređaju A, i njegovo konzumiranje (sign-in same user) na uređaju B.
>
> **Use case:** user gleda anonimno na desktopu, klikne "Pošalji na mobitel" → dobije kod `483-291`. Na mobitelu otvori `domovina.ai/handoff`, unese kod, instantno se ulogira kao isti user.

---

## Prompt za Claude Code

```
Napiši migraciju `sql/migrations/006_handoff_rpc.sql`. Funkcije su
SECURITY DEFINER da mogu raditi cross-user lookup, ali strogo validiraju ulaz.

1. `domovina_ai.create_handoff_token() returns text`
   - SECURITY DEFINER set search_path = ''.
   - Validate: (select auth.uid()) IS NOT NULL.
   - Generiraj 6-znamenkasti random kod:
     code := lpad((floor(random() * 1000000))::int::text, 6, '0');
     -- Retry do 5 puta ako collision (gotovo nemoguće, ali safeguard).
   - DELETE postojeće nepotrošene kodove istog usera:
     delete from domovina_ai.handoff_tokens
     where user_id = (select auth.uid())
       and consumed_at is null;
   - INSERT (code, user_id, source_device, expires_at default).
   - Return code.

2. `domovina_ai.consume_handoff_token(p_code text, p_device text) returns jsonb`
   - SECURITY DEFINER set search_path = ''.
   - Validate format: p_code mora biti exactly 6 znamenki (regex).
   - Lookup:
     select user_id from domovina_ai.handoff_tokens
     where code = p_code
       and consumed_at is null
       and expires_at > now()
     for update skip locked;
   - Ako nema reda → raise exception 'invalid_or_expired_code'.
   - UPDATE consumed_at = now(), consumed_by_device = p_device.
   - Return jsonb {
       'user_id': <found user_id>,
       'success': true
     }.
   - NOTE: ova funkcija NE vraća session JWT. Kako sign-in:
     - Opcija A (preporučeno): edge function/Node servis poziva ovaj RPC
       sa service_role, dobije user_id, generira magic link preko admin API-ja,
       Flutter odmah otvori taj link da dobije session.
     - Opcija B (jednostavnija ali manje sigurna): Flutter koristi anon key
       da pozove ovaj RPC, dobije user_id, ali tada treba poseban mehanizam
       da sign-ina taj user_id. Ovo zahtjeva ili pre-shared token ili
       drugi server-side endpoint.
     => Implementiramo opciju A: edge function `api.domovina.ai/handoff/consume`
        koja consume-a kod i odmah radi `auth.admin.generateLink({ type: 'magiclink', email })`
        ili koristi internal JWT signing.

3. `domovina_ai.cleanup_expired_handoffs() returns int`
   - delete from domovina_ai.handoff_tokens where expires_at < now() - interval '1 day';
   - return broj obrisanih.

4. Schedule cleanup (zahtjeva pg_cron extension):
   create extension if not exists pg_cron;
   select cron.schedule('cleanup-handoffs', '*/15 * * * *',
     $$select domovina_ai.cleanup_expired_handoffs();$$);

5. Grant execute na anon i authenticated:
   grant execute on function domovina_ai.create_handoff_token() to authenticated;
   -- consume_handoff_token NE eksponiraj direktno klijentu;
   -- samo edge function/service role poziva.

6. Output 'OK 06'.
```

---

## Edge function za consume (preporučeno)

`api.domovina.ai/handoff/consume` — mali Deno/Node endpoint:

```typescript
// supabase/functions/handoff-consume/index.ts
import { createClient } from '@supabase/supabase-js'

Deno.serve(async (req) => {
  const { code, device } = await req.json()

  if (!/^\d{6}$/.test(code)) {
    return new Response('invalid', { status: 400 })
  }

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  // Consume token (RPC)
  const { data: result, error } = await admin
    .schema('domovina_ai')
    .rpc('consume_handoff_token', { p_code: code, p_device: device })

  if (error) return new Response(error.message, { status: 400 })

  const userId = result.user_id

  // Generiraj jednokratan magic link za tog usera
  const { data: linkData, error: linkError } = await admin.auth.admin.generateLink({
    type: 'magiclink',
    email: (await admin.auth.admin.getUserById(userId)).data.user!.email
      ?? `${userId}@anonymous.local`,
  })

  if (linkError) return new Response(linkError.message, { status: 500 })

  return Response.json({ action_link: linkData.properties.action_link })
})
```

**Caveat:** ako je source user **anonymous** (nema emaila), ne možeš generirati magic link. Tada je alternativa:

- Force-promote anonymous → permanent prije nego što handoff postane dostupan.
- Ili: vrati raw GoTrue JWT signed s GOTRUE_JWT_SECRET (manje sigurno, ali working).

Za sad MVP: **handoff je dostupan samo logged-in userima** (UI gate). To kompletira loop "anon → M2 link → cross-device" kao prirodan progression.

---

## Smoke test

```bash
# 1. Login kao user A → create code
curl -X POST 'https://api.domovina.ai/rest/v1/rpc/create_handoff_token' \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $USER_JWT" \
  -H "Content-Type: application/json" -d '{}'
# Vraća "483291"

# 2. Iz drugog browsera, consume
curl -X POST 'https://api.domovina.ai/handoff/consume' \
  -H "Content-Type: application/json" \
  -d '{"code":"483291","device":"iphone-safari"}'
# Vraća { "action_link": "https://api.domovina.ai/auth/v1/verify?token=..." }
# Flutter otvori taj link u istom WebView/redirect → dobije session.
```

---

## Što ide u sljedeći korak

- `07-flutter-swap-mocks.md` — kako u Flutter kodu zamijeniti `auth_service.dart` mock za prave Supabase pozive.
