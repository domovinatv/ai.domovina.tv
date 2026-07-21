# Pinka Flutter SDK (embedded)

Samostalna reimplementacija pinka.io **"Zida podrške"** u Flutteru —
crowdfunding / donacijske kampanje sa **SEPA** i **on-chain (EURe/Gnosis preko
MPT protokola)** uplatama + živi zid javnih doprinosa.

Ovo je _embedded_ kopija u `domovina.ai` repou. Vizija: kad se stabilizira,
podiže se u zaseban **`pinka_flutter` package** (otud `pinka_sdk.dart` barrel,
`src/` layout i sve ovisnosti kroz `PinkaConfig`/`PinkaClient`). Izvorni razvoj
i dalje teče u `pinka.io` (Next.js, `/Users/ms/git/pinka-finance/app`); ovdje
je reimplementacija trenutnog stanja + nadskup (Flutter-native, kanal + epizoda).

## Backend (dijeljen!)

`domovina.ai` i `pinka.io` koriste **isti** `domovina-api` Supabase backend.
SDK ne treba novu backend infrastrukturu — gađa postojeću schemu i edge fns:

| Resurs | Što radi |
|---|---|
| `pinka_finance.campaigns` (+ `campaign_stats`) | kampanja po subjektu; lookup po `(subject_type, subject_ref)` |
| `pinka_finance.public_contributions` (view) | "Zid podrške" — samo `paid`, ne-anonimni, javne kampanje |
| `contribution_status(uuid)` RPC | **guest-pollable** stanje doprinosa (anon ne može čitati `contributions` kroz RLS) |
| `pinka-contribute` edge fn | kreira pending doprinos + MPT payment intent → vraća EPC QR / IBAN |
| `pinka-onchain-confirm` edge fn | verificira + kreditira EURe tx po hashu (instant flip) |
| `pinka-webhook` / `pinka-onchain-ingest` | rail/cron kreditiranje (SEPA i direktne on-chain donacije) — **van klijenta** |

Plan & ER model: `domovina-api/docs/pinka-finance-platform-plan.md`,
rails: `domovina-api/docs/pinka-donation-rails.md`.

## Tok plaćanja

- **SEPA** → `contribute()` kreira intent → prikaže EPC QR + IBAN/primatelj/memo
  → poll `contribution_status` dok rail (`pinka-webhook`) ne flipne na `paid`.
- **On-chain (in-app)** → web-only DOMOVINA wallet (`wallet.domovina.ai/sdk.js`)
  pošalje EURe → `confirmOnchain()` verificira tx → instant flip.
- **On-chain (vanjski novčanik)** → EIP-681 QR (`PinkaConfig.eip681`) na campaign
  Safe → cron indexer (`pinka-onchain-ingest`) kreditira za ~1–2 min.

## Javni API (`pinka_sdk.dart`)

- `PinkaSupportCard` — kompaktna kartica (kanal/epizoda); **sama se sakrije** ako
  subjekt nema aktivnu kampanju. Tap → `onOpen` (host navigira).
- `PinkaSupportBar` — uvijek-vidljiva ("sticky") traka za dno ekrana (~56 px),
  namijenjena `Scaffold.bottomNavigationBar`-u; isto auto-skrivanje kao kartica.
  Dodatno podržava **fallback subjekt**: `.episode(youtubeId, channelRefs: […])`
  pokaže kampanju KANALA ako epizoda nema svoju, a `onOpen(campaign, viaFallback)`
  javi hostu na koju rutu podrške navigirati. `applyBottomSafeArea: false` kad
  ispod nje stoji još jedna donja navigacija (inače dupli safe-area razmak).
- `PinkaCampaignScreen` — pun ekran: cover/opis, stats, contribute panel, živi zid.
- `PinkaContributePanel` / `PinkaWallList` — composable dijelovi.
- `PinkaClient` + `PinkaConfig` — backend i konfiguracija (chain konstante,
  edge-fn imena, wallet SDK URL). Default zrcali produkcijski pinka.io.

Konstruktori `.channel(...)` / `.episode(...)` postave `subject_type` i kandidate
`subject_ref`-ova. **Kanal** matcha po internom channel id-u _ili_ kanonskom
YouTube `UC…` id-u (oba se pretražuju).

## Wiring u ovaj app

- Ruta: `/c/:slug/support` → `PinkaCampaignScreen.channel(...)` (`app_router.dart`).
- Kartica: `PinkaSupportCard.channel(...)` iznad liste videa (`channel_screen.dart`).
- Ruta: `/v/:videoId/support` → `PinkaCampaignScreen.episode(...)`.
- Sticky traka: `PinkaSupportBar.episode(...)` u `bottomNavigationBar`-u oba
  episode ekrana (`episode_screen.dart` standard+basic layout,
  `episode_simple_screen.dart`) — na mobitelu složena IZNAD postojeće nav trake.
  Fallback refs = `info.youtubeChannelId` + interni channel id (slug s `_`).

## Što treba da se "Zid podrške" pojavi

Identično postojećem episode panelu: panel/kartica je vidljiv **samo ako
postoji aktivna kampanja** u bazi (`pinka_finance.campaigns`, `state='active'`,
`subject_type='podcast_channel'`, `subject_ref` = channel id ili UC id). Nije
CDN/R2 uvjet — kampanje se kreiraju na pinka.io/admin strani.

## Odnos prema postojećem `lib/widgets/support_episode_panel.dart`

Stariji, **SEPA-only** episode panel (`lib/models/pinka.dart` +
`lib/services/pinka_service.dart` + `widgets/support_episode_panel.dart`) ostaje
u codebaseu kao referenca. Ovaj SDK je nadskup: dodaje on-chain mod, zid podrške
i koristi `contribution_status` RPC (stari panel polla `contributions` direktno
što RLS blokira za anon — latentni bug). Migracija episode ekrana na SDK
(`PinkaCampaignScreen.episode` / nova episode kartica) je sljedeći korak.

## TODO / vizija

- [ ] Episode `Zid podrške` (ruta `/v/:id/support`, `*.episode(...)` već postoji).
- [ ] Migrirati `SupportEpisodePanel` na SDK, ukloniti duplikaciju.
- [ ] Extract u `pinka_flutter` package (inject `SupabaseClient` umjesto `Supabase.instance`).
- [ ] TV (Leanback) varijanta widgeta.
