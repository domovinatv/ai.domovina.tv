# AI tim u tmuxu — planner → orkestrator → dev1/dev2 → reviewer

Jedan iTerm2 prozor (fullscreen), pet Claude Code panela, jedan čovjek koji
promptira samo u jednom od njih. Pokretanje:

```bash
cd ~/git/domovinatv/domovina.ai && ./scripts/tim.sh     # ⌘+Enter za fullscreen
tmux kill-session -t "=$(./scripts/tim-status.sh session)"   # gašenje SAMO ovog tima
```

```
┌──────────────┬──────────────┬──────────────┐
│              │ orkestrator  │    dev1      │
│   planner    │   (fable)    │   (opus)     │
│   (opus)     ├──────────────┼──────────────┤
│   ← TI       │  reviewer    │    dev2      │
│  promptaš    │   (fable)    │   (opus)     │
└──────────────┴──────────────┴──────────────┘
   36%              32%             32%
```

Lijevi stupac je tvoj chat; srednji je "management" (koordinacija + kontrola
kvalitete); desni su ruke. Čitaš zdesna nalijevo kad te zanima *što se radi*, a
slijeva nadesno kad *zadaješ*.

## Ime sessiona je per-projekt

Session se zove `tim-<repo-slug>`, izvedeno iz imena repo direktorija:
`domovina.ai` → **`tim-domovina-ai`** (točke i ostali znakovi se sanitiziraju —
tmux ih ne dopušta u imenu). Tako na istom Macu paralelno radi po jedan tim za
svaki projekt, svaki u svom iTerm prozoru, bez kolizije. Override: `TIM_SESSION=…`.

```bash
tmux ls | grep '^tim-'                                       # svi timovi na stroju
./scripts/tim-status.sh session                              # ime tima ovog repoa
tmux kill-session -t "=$(./scripts/tim-status.sh session)"   # ubij samo ovaj
```

**Zašto `=` ispred imena:** tmux radi *prefix matching* na imenima sessiona —
`kill-session -t tim` bi, ako session doslovno imena `tim` ne postoji, pogodio
prvi koji počinje s "tim" (npr. `tim-rodj`, tuđi projekt). `=` traži egzaktan
match. Skripte to rade same (`tim_target()` u `scripts/tim-common.sh`).

## Zašto ovako

Prije: plan si radio u zasebnoj Claude Code sesiji, kopirao ga orkestratoru i
izgubio vezu između planiranja i izvođenja. Sad je planiranje **pane 0** istog
sessiona — vidiš plan, njegovu predaju i izvođenje u istom prozoru, i možeš
planirati sljedeći posao dok tim radi prethodni.

Druga izmjena: **reviewer**. Dev1/dev2 su prije završavali sa SAŽETKOM koji
nitko nije provjeravao prije commita — orkestrator ih je čistio (`/clear`) i
išao dalje, pa se greška otkrivala tek kad je kontekst već bio izgubljen.
Reviewer sada gleda diff **prije commita i prije `/clear`**, pa dorade idu
natrag onom devu koji je kod i pisao — dok mu je kontekst još živ.

## Podjela modela

| Panel | Model | Zašto |
|---|---|---|
| planner | **opus** | Kriva odluka u planu množi se s dva deva — tu ide najjači model. |
| orkestrator | **fable** | Dispatch, polling, čitanje sažetaka, git. Mehanika, ne dubina; brz i jeftin. |
| reviewer | **fable** (+ eskalacija) | Konformnost planu, `flutter analyze`, očiti bugovi. Za *Rizik: visok* orkestrator mu pošalje `/model opus` prije pregleda. |
| dev1, dev2 | **opus** | Pisanje koda. |

Override preko env varijabli:
`TIM_MODEL_PLAN`, `TIM_MODEL_ORCH`, `TIM_MODEL_REVIEW`, `TIM_MODEL_DEV`.

## Petlja

1. **Ti u planneru** — normalan razgovor: istraživanje koda, dogovor opsega.
2. **`/delegiraj`** (ili "daj timu") → planner zapiše
   `docs/plans/YYYY-MM-DD-<slug>.md` (Cilj, Kontekst, Taskovi s popisom
   fajlova, Ovisnosti, Rizik, Verifikacija, Van opsega) i pošalje orkestratoru
   `/tim izvrši plan iz docs/plans/….md`.
3. **Orkestrator** razbije plan i pošalje po jedan task dev1 i dev2 — samo ako
   su im popisi fajlova disjunktni; inače serijalizira.
4. **Devovi** rade, završe SAŽETKOM. Ne commitaju, ne deployaju.
5. **Reviewer** dobije `/pregled …`, čita `git diff` radnog stabla, pokreće
   `flutter analyze`, i piše verdikt u `.tim/reviews/<slug>-rN.md`
   (prva linija `VERDIKT: OK` ili `VERDIKT: DORADA`).
6. **DORADA** → dorade idu istom devu, bez `/clear`, pa novi krug pregleda.
   **OK** → orkestrator commita, tek onda `/clear` objema devovima i novi krug.

Ti u koraku 3–6 ne moraš raditi ništa. Ako želiš intervenirati, klikni u
orkestratorov panel (miš je uključen) i utipkaj ispravak — to je predviđeno.

## Kako pratiš, a da te nitko ne prekida

Nijedan agent ne smije slati poruke u planner panel (`tim-send.sh` to odbija) —
poruka bi ti upala usred prompta. Umjesto toga:

- **tmux status bar** (dolje desno) — orkestrator ga osvježava sa
  `./scripts/tim-status.sh set '…'`, tmux ga čita svakih 5 s.
- `./scripts/tim-status.sh` — tablica: uloga, pane, BUSY/IDLE, zadnja linija,
  plus popis verdikata iz `.tim/reviews/`.
- `./scripts/tim-read.sh dev1 120` — zadnjih 120 linija iz panela.

## Helperi

```bash
./scripts/tim-send.sh <uloga> '<jedna linija>'   # planner|orkestrator|reviewer|dev1|dev2
./scripts/tim-read.sh  <uloga> [linija]
./scripts/tim-status.sh [set "<tekst>"]
```

`tim-send.sh` rješava tri zamke odjednom: pane ID čita iz tmux user opcije
(`@tim_<uloga>`, postavlja je `tim.sh`) umjesto da pogađa geometriju; tekst
šalje u `-l` literal modu (navodnici, `$`, `-` prolaze netaknuti); Enter šalje
**odvojeno**, nakon pauze — Claude Code TUI inače proguta red. Poruka mora biti
jednolinijska: svaki `\n` je za TUI submit. Dugi sadržaj → fajl, pa pošalji
putanju.

## Runtime stanje (`.tim/`, gitignorirano)

| Fajl | Što je |
|---|---|
| `.tim/panes.env` | mapa uloga → pane ID (debug; skripte čitaju tmux opcije) |
| `.tim/status.line` | tekst koji tmux status bar prikazuje |
| `.tim/reviews/*.md` | verdikti reviewera po krugu |

Planovi (`docs/plans/`) NISU gitignorirani — oni su trag odluka i idu u repo.

## Ograničenja i zamke

- **Nema worktreeja po devu.** Lomi relativni path dependency u `pubspec.yaml`
  (`../../stepanic/flutter_certilia`) i nema `.env`. Izolaciju drži isključivo
  pravilo *disjunktni fajlovi* iz plana — zato je popis fajlova po tasku
  obavezan, a ne ukras.
- **Svi paneli rade s `--dangerously-skip-permissions`** (odluka vlasnika
  repoa, git je sigurnosna mreža). Za oprezniji mod zamijeni tu zastavicu s
  `--permission-mode acceptEdits` u `scripts/tim.sh`.
- **BUSY/IDLE je heuristika** (traži "esc to interrupt" u panelu). Panel
  zaglavljen u dijalogu prikazuje se kao IDLE — provjeri s `tim-read.sh`.
- **Planner ne dira kod dok tim radi** — pregazio bi devove. Piše samo
  `docs/plans/*`.
- **Zašto ne `claude --tmux` / `--worktree`**: `--tmux` traži `--worktree` i
  radi jedan session po worktreeju s iTerm2 native paneima — ne ovaj layout
  kojim agenti upravljaju preko `send-keys`.

## Provjereno pri izradi (2026-07-25, tmux 3.5a, Claude Code 2.1.220)

Da se ne retestira svaki put:

- `set-option`/`show-options`/`rename-window` **ne** primaju `=` prefiks
  ("no such session: =ime") — njima ide golo ime; sigurno je jer tmux egzaktno
  ime traži prije prefiksa. `has-session`/`attach`/`kill-session`/`list-panes`
  `=` primaju i ondje je obavezan. Otud dva helpera: `tim_target()` i
  `tim_opt_target()`.
- `#{@role}` user opcija se rezolvira u `pane-border-format` i `list-panes -F`
  kroz hijerarhiju pane→window→session — zato border pokazuje točnu ulogu iako
  Claude Code TUI pregazi `pane_title`.
- `tmux send-keys -l "$msg"` prenosi navodnike, `$VAR` i `--flag` doslovno u
  TUI input; Enter mora ići kao zaseban `send-keys` nakon ~0.4 s.
- `split-window -l 60%` (ne stari `-p`) radi na 3.5a; postotak je relativan na
  pane koji se dijeli, pa je redoslijed splitova bitan (vidi `tim.sh`).
- Slanje `/clear` je lokalna TUI komanda — dobar način da se kanal testira bez
  ijednog API poziva.
- `status-right "#(cat …/.tim/status.line)"` uz `status-interval 5` daje
  ambijentalni napredak bez ijedne poruke u planner panel.

## Isti obrazac u drugim repoima

`rodjendaonice.domovina.ai` ima svoju varijantu (session `tim-rodj`, 3 panela,
handoff dokumenti umjesto plan-fajlova). Kad se i ondje napravi ovaj prolaz,
ime mu po ovoj konvenciji postaje `tim-rodjendaonice-domovina-ai` — prefiks
`tim-` je zajednički da `tmux ls | grep '^tim-'` izlista sve timove na stroju.
