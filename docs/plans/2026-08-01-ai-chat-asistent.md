# AI chat asistent — ekstrakcija ovdje, prototip u `domovina-chat`

> **Status 2026-08-01:** slojevi „kvaliteta odgovora" i „backend" **preseljeni su
> u zaseban repo `domovina-chat`** (skela commitana, gradi se, retrieval provjeren
> protiv živog korpusa). Plan, odluke i kriterij izlaska: `domovina-chat/docs/plan.md`.
>
> **U OVOM repou ostaje T1** — ekstrakcija reusable dijelova iz
> `search_overlay.dart` — i kasnija integracija.

## Cilj

Uz postojeću Cmd+K pretragu (koja ostaje **netaknuta**) korisnik dobiva drugi
način ulaska u isti korpus: razgovor na hrvatskom, s odgovorom koji citira
konkretne epizode i minute. Uzor je `magisterium.com/new`.

Nefunkcionalni cilj jednako važan: **nula regresije na postojećoj pretrazi** i
**nula LLM ključeva u klijentu**.

## Zašto je posao podijeljen na dva repoa

Rizik nije UI, nego **kvaliteta odgovora** — daje li jeftin model pouzdane,
citirane hrvatske odgovore nad našim chunkovima. Taj sloj traži 50–200 iteracija
prompta i posve je neovisan o Flutteru; ovdje bi svaka iteracija bila rebuild.
Presedan je `domovina-stats` (odvojen repo za vizualizaciju iste RAG baze).

```
domovina-chat   Vite + React + Hono na CF Workers, AI SDK v7
      │                  ← prompt, eval, provider bake-off, backend
      ├─ HTTP ─▶ mcp.domovina.ai/api/search     (postojeći, netaknut)
      └─ HTTP ─▶ AI Gateway ─▶ Gemini | Mistral

domovina.ai     T1 ekstrakcija SADA (koristan refaktor i bez chata)
                Flutter UI TEK nakon kriterija izlaska
```

**Opovrgnuta odluka (bila O1 u prvoj verziji ovog plana):** backend NE mora od
prvog dana biti in-process u `domovina-rag`. Taj argument vrijedi za agentic loop
(3–4 hopa po poruci), a ne za retrieve-then-read gdje je točno jedan retrieval:
~50 ms na operaciji od ~4 000 ms je 1,2 %.

## Zatečeno stanje (provjereno u kodu 2026-08-01)

| Komad | Gdje | Stanje |
|---|---|---|
| Ulaz u pretragu | `home_screen.dart:155` `_openSearchOverlay()` | ✅ tanko — home prosljeđuje `index.channels` + 3 nav callbacka |
| Search overlay | `home/search_overlay.dart` (1231 linija, jedan `State`) | ⚠️ pet odgovornosti u jednoj klasi |
| Tier-0 lokalni scoring | `search_overlay.dart:336-378`, `:941-958` | ⚠️ čiste funkcije, ali `private` |
| Tier-1 semantic klijent | `services/search_service.dart` | ✅ već standalone, `SemanticResult` reusable |
| Renderiranje redaka | `search_overlay.dart:752-1127` | ⚠️ `private` — chat citati moraju izgledati isto |
| Deterministički RAG | `domovina-rag/…/public-api.ts` → `GET /api/search` | ✅ live na `mcp.domovina.ai` |
| Chat bilo koje vrste | — | ❌ ne postoji ovdje (živi u `domovina-chat`) |

## Zašto ne postojećim protokolima

**MCP se NE zove iz Fluttera.** MCP je transport *za LLM klijente* (Claude.ai,
Cursor). Naš app nije LLM klijent nego korisnik agenta. Da Flutter priča MCP,
svaki tool poziv bio bi Worker → `mcp.domovina.ai` → ClickHouse, plus MCP ključ
u klijentu.

**A2A je overkill.** Dohvaćena stvarna agent kartica Magisteriuma
(`magisterium.com/.well-known/agent.json`):

```json
{
  "url": "https://magisterium.com/api/v1/a2a",
  "protocolVersion": "0.2.6",
  "capabilities": { "streaming": false, "pushNotifications": false }
}
```

`streaming: false` — Magisterium **ne može** izgraditi vlastiti `/new` chat na
vlastitom A2A endpointu. A2A im je *treća, van-okrenuta* površina uz REST chat
(za njihov UI) i MCP (za Claude/Cursor):

| Površina | Za koga | Kod nas |
|---|---|---|
| REST chat API | vlastiti UI | 🔨 gradi se u `domovina-chat` |
| MCP | Claude, Cursor, ChatGPT | ✅ `mcp.domovina.ai` |
| A2A | tuđi agenti/orkestratori | ❌ i to je u redu |
| REST search | frontend tražilica | ✅ `/api/search` |

A2A ima smisla tek kad želimo da nas **tuđi** orkestrator može zvati — to je
distribucijska igra, ne tehnička potreba. Kad/ako dođe red: **A2A v1.0**
(stabilan od travnja 2026, potpisane agent kartice, Linux Foundation), ne 0.2.6
na kojem je Magisterium zapeo, i tada kao ~400 linija omotača oko iste petlje
koja već postoji u `domovina-chat`.

## T1 — Ekstrakcija reusable dijelova iz `search_overlay.dart`

**Jedini task koji se izvodi u ovom repou prije integracije.** Čist refaktor:
ponašanje pretrage se ne smije promijeniti ni za piksel. Mergea se zasebno.

Vrijedi i bez chata — `search_overlay.dart` je 1231 linija s pet odgovornosti u
jednom `State`-u.

**Fajlovi:**

- novo `lib/widgets/search/result_tiles.dart` — `SemanticResultTile`,
  `EpisodeResultTile`, `PersonResultTile`, `RelevanceMeter` (javne verzije
  `_semanticRow`/`_videoRow`/`_personRow`/`_relevanceMeter`, `search_overlay.dart:752-1127`).
  `onTap` je **parametar** — chat ne smije raditi `Navigator.pop`.
- novo `lib/services/local_search.dart` — `localPersons/localChannels/localVideos/
  localMatchContext` (`search_overlay.dart:336-378`, `:941-958`). Čiste funkcije
  nad `channelCache` + `personIndexCache`.
- novo `lib/widgets/command_palette_shell.dart` — dialog chrome iz
  `showSearchOverlay` (`:32-63`) + header s inputom (`:424-478`), sa slotom za
  mod u headeru (`Traži` | `Pitaj`).
- izmjena `lib/screens/home/search_overlay.dart` — postaje korisnik gornjeg troga.

**Prihvatni kriterij:** `flutter analyze` čist; testovi kao prije (usporedi s
`known_failing_tests` baselineom — `widget_test` i `home_feed_test` padaju i na
čistom mainu); ručno: Cmd+K, dvostupčani layout, ↑↓←→, Enter, „Otvori po ID-u" —
sve identično.

**Rule:** ako se tijekom ekstrakcije primijeti bug u pretrazi — zapiši ga,
popravi **zasebnim** commitom.

## Integracija (tek nakon kriterija izlaska)

Kriteriji K1–K4 su u `domovina-chat/docs/plan.md`. Ukratko: nula izmišljenih
citata, ≥18/20 na slijepoj ocjeni, svih 6 `absent`/`trap` pitanja odbijeno,
p95 do prvog tokena < 6 s.

Kad prođu, ovdje se radi:

1. **Chat kao drugi mod Cmd+K palete**, ne novi ekran. Korisnik ne uči novu
   površinu; `/pitaj` otvara paletu odmah u chat modu.
2. **`lib/models/chat_message.dart`** zrcali `domovina-chat/src/shared/contract.ts`
   — to je specifikacija, ne inspiracija.
3. **Citati kroz `SemanticResultTile` iz T1.** Chat odgovor bez identično
   izgledajućih izvora je generički chatbot.
4. **i18n** `chat*` ključevi, HR template prvi, registar „ti".
5. **Gating** preko `EntitlementService.instance.isPlus`. Kad se limit potroši:
   persistentna traka/kartica, **nikad modal** (`CLAUDE.md` — nudge ne prekida).
6. **`/pitaj` NE ide u AASA components ni u Android intent filter** dok se ne
   odluči je li javno dijeljiva.

## Zamke za Flutter fazu

1. **SSE ne radi kroz `package:http` na webu** — `BrowserClient` bufferira cijeli
   response. Treba `fetch` + `ReadableStream` preko `package:web`, conditional
   import po uzoru na `services/browser_fullscreen.dart` /
   `services/media_element_mute_web.dart`, gate na `dart.library.js_interop`
   (**ne** `dart.library.html` — `--wasm`).
   **Prototip ovo NE de-riskira** — u pregledniku SSE radi out-of-the-box. Zaseban
   spike, svjesno odgođen.
2. **`Scrollable.ensureVisible` scrolla sve roditelje** — auto-scroll na dno chata
   unutar palete traži vlastiti `ScrollController` + ručni offset, kao `PeopleRail`.
3. **`flutter_markdown` inline builder mora vratiti `Text.rich`/`RichText`**;
   `WidgetSpan` za citat treba baseline.
4. **Perzistencija razgovora: `localStorage` na webu**, nikad `SharedPreferences`.
5. **`MarkdownStyleSheet.withBrandBlockquote(theme)`** — default je nečitljiv u dark.

## Izvan opsega

- **A2A endpoint** — vidi gore. Tek nakon što chat backend stabilizira.
- **MCP SDK migracija na spec 2026-07-28** — stateless jezgra + `Tasks`
  ekstenzija su breaking change za `@modelcontextprotocol/sdk ^1.0.4` i
  session-id model. Stvarniji tehnički dug od A2A, ali odvojen posao.
- **Glasovni unos**, **chat na TV-u**, **chat u kontekstu jedne epizode**.
