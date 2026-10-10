# „Pronađi u epizodi" i članak koji klizi uz reprodukciju (7.10.2026.)

LIVE: v2.0.170 (pretraga), v2.0.171 (klizanje + naslov sekcije u svom redu).

## 1. Pronađi u epizodi

Polje ispod poglavlja na `/v/:id` (i u basic layoutu kad je faza ≥ `transcribed`).
Upis riječi/imena/fraze → SVI trenuci gdje je izgovorena, kronološki; tap skoči u
playeru (`_seekToAndPlay` + `_revealPlayer`, ista putanja kao „Poslušaj" sponzora).

- Servis: `lib/services/transcript_search.dart`; widget:
  `lib/widgets/find_in_episode_section.dart`; testovi: `test/transcript_search_test.dart`.
- Backend: Meili index `segments` na `search.domovina.ai` (1 dok = 1 SRT segment).
  Ključ `MEILI_SEGMENTS_SEARCH_KEY` — search-only, samo `segments`, default u kodu,
  override kroz `deploy.sh` / `build-mobile-release.sh`. Izvor istine i plan:
  `domovina-rag/docs/plans/2026-10-06-meili-segments-pretraga-transkripta.md`.
- Pravila prenesena iz `domovina-rag/services/mcp/src/tools/find-in-transcript.ts`:
  padeži (`toWordFormsQuery`: „Matija" → „Matij"), doslovno vs. tipfeler
  (`classifyMatch`), `matchingStrategy: "all"`.

### Zamke (izmjerene)

1. **`sort: start_sec:asc` NE daje kronologiju.** Meili primjenjuje `sort` iza
   pravila `words`/`typo`, pa tipfeleri stižu na kraju: za „Matij" na
   `35Oq01CmGWE` poredak je bio 117 s, 1396 s, 146 s. Kronologija se slaže u
   klijentu (`TranscriptSearchResult.fromJson`).
2. **`classifyMatch` ide nad POSLANIM upitom** („Matij"), ne nad upisanim
   („Matija") — inače je „Matijom" lažni tipfeler. MCP radi isto (`effectiveQuery`).
3. Segment zna nositi 15+ s govora → `attributesToCrop: text`, `cropLength: 30`.
4. Ime govornika je iz dijarizacije i zna biti krivo (23:16 piše Ante, govori
   Petar) — prikazano kao siva oznaka, nikad „X je rekao".

Provjereno u pregledniku na produkciji: „Matija" → 1:57, 23:16 doslovno; 2:26
(„Marija") pod „Približni pogoci". Tap logira `FindInEpisode: jump 1396s`; da
je video stvarno sjeo na 23:16 NIJE viđeno (automation preglednik ne učita
mediju, player stoji na 00:00/00:00).

## 2. „Odjavna špica" — članak klizi uz reprodukciju

Povod: gledatelj na mobitelu u landscapeu vidi naslov sekcije i screenshot, a
tekst ispod (koji želimo da čita i dijeli po poglavljima) nikad ne dođe na ekran.

`_creditsScroll` u `episode_screen.dart`, zove ga `_onVideoPosition` dok je
pozicija unutar iste sekcije (promjena sekcije i dalje ide kroz `_scrollToSection`):

```
cilj = vrh_sekcije_pod_app_barom + napredak_u_sekciji × (visina_sekcije − 0,6 × vidljivo)
```

- Samo naprijed; tko je odčitao unaprijed, čeka da ga reprodukcija sustigne.
- Ručni scroll pauzira 8 s (`_kCreditsPauseAfterManual`).
- Ako je cilj više od ekrana daleko, korisnik čita drugdje → ne vuče se.
- Ne radi: pauziran player, poruka sponzora (`_sponsorClip`), mobilni tab
  Magisterium (`_mobileTab != 0`), 600 ms nakon skoka na sekciju (snap headera).
- `animateTo` 250 ms linearno po tiku position streama (~5×/s) + `_scrollLock`,
  da `_onScroll` to ne proglasi ručnim scrollom.
- `_pinnedTop()` je izvučen iz `_jumpSectionToTop`; u phone landscapeu vraća samo
  inset jer se floating header na scroll prema dolje skrije.

Radi u svim layoutima, ne samo phone landscape — svjesno; ako smeta na desktopu,
uvjet je `_isPhoneLandscape(context)`.

## 3. Naslov sekcije u svom redu

`ArticleSectionCard`: kad je kartica uža od 520 px (`_kTitleOwnLineBelow`), red
vremena/ikona ostaje gore, naslov ide ispod preko cijele širine. Stisnut uz ikone
prelamao se u 3–4 retka uz prazninu ispod ikona. Provjereno u iframeu 844×390.
Naslov namjerno NIJE `maxLines: 1` — po njemu korisnik bira što dijeli.

## Otvoreno

- **Test na iPhoneu u landscapeu**: glatkoća klizanja, interakcija s floating
  headerom, je li 8 s pauze prava mjera, sjeda li skok iz pretrage na sekundu.
- Kontekst pogotka (segment `seq` n±1 kroz `filter`, ključ ne smije `/documents`)
  nije napravljen.
- Pretraga nije u jednostavnom prikazu (`/m/`, `episode_simple_screen.dart`).
