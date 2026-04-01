# Chapter Sync State Machine

Single source of truth za svu logiku sinkronizacije chaptera, video playera,
scrollanja i dual pointera u episode detaljnom prikazu.

**Datoteke:** `lib/screens/episode_screen.dart`, `lib/widgets/table_of_contents.dart`, `lib/widgets/video_panel.dart`

---

## State varijable

| Varijabla | Tip | Opis |
|-----------|-----|------|
| `_activeTimestamp` | String? | Plavi pointer — prati video player poziciju |
| `_scrollTimestamp` | String? | Narancasti pointer — prati scroll poziciju srednje liste |
| `_seekLock` | DateTime? | Lock koji blokira auto-sync (2100ms) |
| `_scrollLock` | DateTime? | Lock koji blokira scroll listener (300ms) |
| `_lastManualScroll` | DateTime? | Kad je korisnik zadnji put rucno scrollao srednju listu |

---

## Inputi (korisnicke akcije i sistemski eventi)

| ID | Input | Izvor |
|----|-------|-------|
| A | Klik na TOC lijevu listu | `onSectionTap` → `_seekAndPlay(ts)` |
| B | Klik na Play ikonu u srednoj listi | `onPlayTap` → `_seekAndPlay(ts, preroll: true)` |
| C | Klik na chapter u desnoj listi | `onChapterTap` → `_seekAndPlay(ts)` |
| D | Video player dosao na novi chapter | `_onVideoPosition(pos)` listener |
| E | Korisnik rucno scrolla srednju listu | `_onScroll()` listener |
| F | Korisnik seeka slider | `_onVideoSeek(pos)` |
| G | Klik na drawer TOC (mobile) | `_drawerTap(ts)` → `_seekAndPlay(ts)` |

---

## Akcije po inputu

### A/B/C/G — Rucni klik na chapter (seekAndPlay)

```
1. _seekLock = DateTime.now()              // blokira D i E za 2100ms
2. setState:
     _activeTimestamp = timestamp           // plavi pointer instant
     _scrollTimestamp = timestamp           // narancasti pointer instant
3. _scrollToSection(timestamp)              // srednja lista instant scroll
4. Video seek:
     preroll=false: seek na tocni timestamp
     preroll=true:  seek na timestamp - 2s
5. Sve tri liste:
     - TOC (lijeva): didUpdateWidget → ensureVisible
     - Srednja: scrollToSection vec obavljen u koraku 3
     - Chapter (desna): didUpdateWidget → postFrameCallback → ensureVisible
```

**Preroll (-2s) koriste:** Play ikone u srednjoj listi (input B)
**Exact seek (+-0s) koriste:** TOC lijeva (A), chapter desna (C), drawer (G)

### D — Video player dosao na novi timestamp

```
1. Provjera seekLock:
     Ako je aktivan (< 2100ms) → SKIP (ne radi nista)
2. Provjera backward jump grace period:
     Ako je seekLock istekao < 500ms i newTs < currentTs → SKIP
     (sprjecava flicker nakon preroll seeka)
3. setState:
     _activeTimestamp = newTs               // plavi pointer
     _scrollTimestamp = newTs               // narancasti pointer syncan
4. Provjera _lastManualScroll:
     Ako korisnik NIJE rucno scrollao zadnje 2s:
       _scrollLock = DateTime.now()         // blokira E za 300ms
       _scrollToSection(newTs)              // auto-scroll srednje liste
     Ako JE rucno scrollao:
       NE scrollaj srednju listu (korisnik cita)
5. Sve tri liste updejt pointere (setState)
6. TOC + chapter lista: ensureVisible za plavi pointer
```

### E — Korisnik rucno scrolla srednju listu

```
1. Provjera seekLock:
     Ako je aktivan (< 2100ms) → SKIP
2. Provjera scrollLock:
     Ako je aktivan (< 300ms) → SKIP
     (sprjecava scroll listener od overridea nakon programatskog scrolla)
3. _lastManualScroll = DateTime.now()
4. _updateActiveSectionFromScroll():
     Pronadji prvi section ciji je vrh >= 0 i < 40% ekrana
     Ako se razlikuje od _scrollTimestamp:
       setState(_scrollTimestamp = foundTs)  // narancasti pointer
     _activeTimestamp se NE MIJENJA          // plavi ostaje na video poziciji
5. TOC + chapter lista: ensureVisible za narancasti pointer
```

### F — Korisnik seeka slider

```
1. Pronadji section za novu poziciju
2. setState(_activeTimestamp = newTs)
3. _scrollToSection(newTs)
4. NEMA seekLocka (slider seek je intencionalan, ne treba grace period)
```

---

## Lock mehanizmi

### seekLock (2100ms)

**Aktivira se:** svaki `_seekAndPlay` poziv (A, B, C, G)
**Blokira:**
- `_onVideoPosition` (input D) — video listener ne smije overrideati rucno selektirani chapter
- `_onScroll` (input E) — scroll listener ne smije reagirati na programatski scroll
- `_updateActiveSectionFromScroll` — dodatna zastita

**Grace period (+500ms nakon isteka):** blokira backward jump u `_onVideoPosition`.
Razlog: preroll -2s znaci da player stoji na prethodnom chapteru dok ne prijedze na ciljani.
Bez grace perioda: flicker prethodni → ispravni chapter.

### scrollLock (300ms)

**Aktivira se:** kad `_onVideoPosition` radi auto-scroll srednje liste
**Blokira:** `_onScroll` — sprjecava scroll listener od tretiranja programatskog scrolla kao rucnog

---

## Widget scroll ponasanje

### TOC lijeva lista (`TableOfContents`)

- **Svi itemi uvijek mountani** (ListView s children, ne builder)
- **GlobalKey** po svakom section timestampu
- `didUpdateWidget`: ensureVisible kad se promijeni `activeTimestamp` ILI `scrollTimestamp`
- Narancasti se scrolla samo ako != activeTimestamp (da ne radi double scroll)
- **Dual pointer:** plavi = isPlaying, narancasti = isScrolled (samo kad != plavi)

### Srednja lista (CustomScrollView)

- **Svi itemi uvijek mountani** (SliverToBoxAdapter)
- **GlobalKey** po svakom section timestampu (`_sectionKeys`)
- Scroll via `Scrollable.ensureVisible(duration: Duration.zero)`
- ScrollController listener za `_onScroll`

### Chapter desna lista (`VideoPanel`)

- **Svi itemi uvijek mountani** (SingleChildScrollView + Column, NE ListView.builder)
  Razlog: ListView virtualizira — daleki itemi nemaju currentContext
- **GlobalKey** po svakom chapter timestampu
- `didUpdateWidget` + **postFrameCallback**: ensureVisible kad se promijeni activeTimestamp ili scrollTimestamp
  Razlog: didUpdateWidget se poziva prije layout → pozicije su stale bez postFrameCallback
- **Dual pointer:** plavi = isPlaying, narancasti = isScrolled

---

## Boje pointera

| Pointer | Boja | Hex | Alpha pozadine |
|---------|------|-----|----------------|
| Plavi (playing) | `theme.colorScheme.primary` | zavisi od teme | 120 |
| Narancasti (scroll) | `Color(0xFFEF6C00)` | #EF6C00 | 40 |

Kad su oba na istom chapteru → plavi ima prioritet (isPlaying = true, isScrolled = false).

---

## Regresijski checklist

Testiraj svaki slucaj nakon promjena u sync logici:

- [ ] **A: TOC klik** → plavi + narancasti instant na kliknutom, video seeka +-0s, sve tri liste scrollane
- [ ] **B: Play ikona** → plavi + narancasti instant, video seeka -2s, za 2s nema flickera
- [ ] **C: Chapter klik** → plavi + narancasti instant, video seeka +-0s, lijeva + srednja lista scrollane
- [ ] **D: Video playback** → kad prijedze chapter: plavi + narancasti se syncaju, sve liste se scrollaju (ako korisnik ne scrolla rucno)
- [ ] **E: Rucni scroll** → narancasti se odvaja od plavog, prati scroll poziciju, plavi ostaje na video
- [ ] **E → D: Rucni scroll pa video chapter change** → narancasti se vrati na plavi
- [ ] **B grace period** → nakon Play ikone klik, nema flickera kad istekne seekLock
- [ ] **Daleki jump** → klik na chapter koji je 10+ stavki daleko, desna lista scrollana ispravno
- [ ] **Mobile drawer** → TOC u draweru radi isto kao desktop TOC
- [ ] **Slider seek** → plavi se updejta, srednja lista scrolla, nema seekLocka
