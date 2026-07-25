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
| orkestrator | **fable** | Dispatch, polling, čitanje sažetaka, git. Traži pouzdanost i brzinu, ne dubinu. |
| reviewer | **fable** (+ eskalacija) | Konformnost planu, `flutter analyze`, očiti bugovi. Za *Rizik: visok* orkestrator mu pošalje `/model opus` prije pregleda. |
| dev1, dev2 | **opus** | Pisanje koda. |

Override preko env varijabli:
`TIM_MODEL_PLAN`, `TIM_MODEL_ORCH`, `TIM_MODEL_REVIEW`, `TIM_MODEL_DEV`.

⚠️ **Fable NIJE jeftiniji od Opusa — dvostruko je skuplji** (API cjenik: fable-5
$10/$50 po MTok, opus-5 $5/$25). Podjela stoji zbog *sposobnosti i brzine*
koordinacije, ne zbog cijene. Izmjereno na prvom krugu: orkestrator je bio
NAJSKUPLJI panel u timu ($4.15 od $12.28 ukupno) iako nije napisao ni retka
koda — polling mu je napuhao cache-read (2.4 M tokena). Ako trošak postane
problem, prvo skrati polling (vidi dolje), pa tek onda diraj podjelu modela.

## Petlja

0. **Kickoff je automatiziran** — `tim.sh` planneru pošalje `/pocni`
   (`.claude/commands/pocni.md`) čim mu TUI proradi: pročita ovaj doc i
   `delegiraj.md`, provjeri panele i stanje repoa, javi ti to u 5 redaka i
   stane. Nema uvodnog prompta koji moraš čuvati u clipboardu.
   Isključivanje: `TIM_AUTOSTART=0 ./scripts/tim.sh`.
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
./scripts/tim-status.sh [set "<tekst>"] [session]
./scripts/tim-watch.sh [--once]                  # nadzornik: 1 linija = 1 događaj
./scripts/tim-cost.py [--since HH:MM] [--json]   # izmjerena potrošnja po ulozi i modelu
./scripts/tim-kill.sh [-f]                       # ugasi SAMO tim ovog repoa
```

`tim-cost.py` **mjeri**, ne procjenjuje: čita `usage` blok svake assistant
poruke iz transkripata sesija (`~/.claude/projects/<slug>/*.jsonl`), pripisuje
ulogu preko `agent-name` zapisa koji nastaje iz `claude -n <ime>`, i dedupe-a
po `message.id` (isti zapis se u JSONL-u ponovi više puta). Sesije bez uloge
(ovaj alatnički chat, drugi prozori) ne ulaze u zbroj tima osim uz `--all`.
Iznos u dolarima je API cjenik — vlasnik je na Claude Max pretplati, pa je to
„koliko bi ovo stajalo preko API-ja", ne račun.

`tim-watch.sh` je čisti promatrač (ništa ne šalje, ništa ne mijenja): javlja
`GOTOV` (dev stao + SAŽETAK), `MIRUJE` (dev stao BEZ sažetka — sumnjivo),
`BLOKIRAN` (čeka odgovor na pitanje), `NEPOSLANO` (utipkan tekst stoji u input
boxu >40 s), `GREŠKA`, `KONTEKST` (>70 %), `VERDIKT` (novi fajl u
`.tim/reviews/`), `PANEL`/`TIM` (nestali). Povijest u
`.tim/watch.log`. Namjerno NE javlja početke radova — nadzor mora biti tiši
od tima. Pusti ga u zaseban prozor (`./scripts/tim-watch.sh`) ili ga koristi
kao izvor događaja za agenta.

**Dvije zaštite u `tim-send.sh`** (obje se gase s `--force`):
`/clear` i `/compact` se **odbijaju dok panel radi** (TUI bi ih stavio u red i
izvršio čim task završi — pobrisao bi baš ono što reviewer treba); i svaka
poruka se nakon slanja **provjeri** — ako se panel nije prerendao, izlaz je 4
uz upozorenje da poruka vjerojatno nije stigla.

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

## Odluke o dizajnu (zašto baš tako)

**Gdje što živi — tri sloja, ne jedan:**

| Sloj | Za što služi | Kod nas |
|---|---|---|
| `--append-system-prompt` | identitet i pravila koja vrijede **uvijek**, u svakoj poruci | uloge u `tim.sh` |
| slash komanda (`.claude/commands/*.md`) | determinističan **ritual** koji netko pokrene | `/pocni`, `/delegiraj`, `/tim`, `/pregled` |
| skill | sposobnost koju model **sam otkrije**, s pratećim fajlovima | ne koristimo — kickoff je fiksan, discovery ne treba |

Uvodni prompt u clipboardu je bio četvrta, najgora varijanta: neverzioniran,
ispari, i duplicira ono što system prompt ionako nosi. Pravilo: **ako to mora
vrijediti uvijek → system prompt; ako to pokrećeš → slash komanda.**

**Zašto reviewer nije samo još jedan zadatak orkestratoru:** orkestratorov
kontekst je pun dispatcha, sažetaka i polling ispisa; svjež panel gleda samo
diff naspram plana. Odvojen panel je i jedini način da review ima *drugi*
model od izvođenja.

**Zašto status ide u tmux status bar, a ne u planner panel:** jedina površina
koju čovjek gleda periferno, a koja mu ne može upasti usred tipkanja.

## Vruće točke i zamke iz prakse

- **Panel koji čeka odgovor izgleda kao gotov.** Claude Code za pitanja s
  ponuđenim opcijama otvori picker (`Enter to select · Tab/Arrow keys to
  navigate`) i time *prestane raditi* — `tim-status.sh` ga vidi kao IDLE.
  Orkestrator zato ne smije zaključiti "dev je gotov" bez SAŽETKA: ako u
  zadnjoj liniji piše `Enter to select`, dev je **blokiran pitanjem** i treba
  mu odgovoriti (`tim-send.sh dev1 '2'` ili tekstom).
- **`app_hr.arb` / `app_en.arb` su najgore usko grlo za paralelizaciju** —
  dira ih gotovo svaki UI task. Ili sve i18n izmjene jednog kruga idu jednom
  devu, ili se taskovi serijaliziraju. Isto vrijedi za `web/_worker.js`
  (sve rute na jednom mjestu) i `pubspec.yaml`.
- **Utipkan a neposlan tekst je tiha zamka.** Poruka koja ostane u input boxu
  (netko je tipkao pa otišao, ili je Enter promašio) izgleda identično kao
  „panel čeka posao" — orkestrator polla, dev miruje, nitko ne napreduje.
  Watcher to javlja kao `NEPOSLANO`. Isto vrijedi za tebe: ako utipkaš uputu
  devu, provjeri da si je poslao.
- **Deploy pripada orkestratoru, i kad ga tražiš od plannera.** `deploy.sh`
  bumpa verziju u `pubspec.yaml` i `lib/main.dart`, pa iza sebe ostavlja
  necommitane izmjene u zajedničkom radnom stablu — netko ih mora commitati, i
  to je integrator. Izmjereno 2026-07-25: planner je odradio deploy na izravnu
  uputu, orkestrator je poslije commitao version bump; radilo je, ali su uloge
  ispale zamućene, a build output je sjeo u plannerov kontekst.
- **Ako ručno pišeš devu, javi orkestratoru.** Rad koji si naručio izravno u
  dev panelu ne postoji u orkestratorovoj knjigovodstvenoj slici: neće ga
  uključiti u opseg reviewa ni u zapisnik plana, a može i sudariti fajlove s
  taskom koji je sam dodijelio. Kratka poruka orkestratoru („dev2 sam dodatno
  zamolio za X") to rješava.
- **Prebacivanje sessiona tmux prefiksom (`prefix )`) te može odvesti u tuđi
  tim** — poruka onda završi u krivom planneru. Prije tipkanja provjeri ime
  u status baru (lijevo dolje) ili `./scripts/tim-status.sh session`.
- **Polling je glavni trošak orkestratora, ne razmišljanje.** Svaki
  `capture-pane` ciklus ulazi mu u kontekst i onda se cijeli kontekst čita
  iznova na sljedećem potezu — 29 poruka orkestratora proizvelo je 2.4 M
  cache-read tokena u prvom krugu. Umjesto ponavljanog pollanja neka **jednom
  blokira** u shellu (`until` petlja koja čeka da devovi padnu na IDLE) i
  probudi se gotov. Nadzor je ionako besplatan: `tim-watch.sh` je bash proces,
  ne model.
- **`ctx` stupac u `tim-status.sh`** pokazuje popunjenost konteksta po panelu —
  to je signal orkestratoru kad devu treba `/clear` (nakon `VERDIKT: OK`) ili
  `/compact` (usred dugog taska).

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
- **BUSY/IDLE se NE može mjeriti tekstom "esc to interrupt"** — u 2.1.220 ga
  footer zna zamijeniti prikazom tokena/efforta ("Puzzling… (1m 31s · ↓ 4.5k
  tokens · thinking with high effort)"). Zato `tim-status.sh` uzima dva uzorka
  panela u razmaku od 1.2 s i uspoređuje ih: promjena = BUSY.
- Filtriranje TUI linija radi FIKSNIM stringovima, ne bracket klasama —
  okvir (`─`) i prompt (`❯`) su multibajtni i BSD `grep` ih u `[]` ne hvata
  pouzdano. Uz `set -e` svaki takav `grep -v` treba `|| true` (prazan rezultat
  je izlaz 1 i ubio bi skriptu).
- `#{@role}` user opcija se rezolvira u `pane-border-format` i `list-panes -F`
  kroz hijerarhiju pane→window→session — zato border pokazuje točnu ulogu iako
  Claude Code TUI pregazi `pane_title`.
- **Prompt u TUI input boxu je `❯` + U+00A0 (non-breaking space)**, ne obični
  razmak. Uzorak `^❯ .` zato nikad ne pogodi živi panel — a sintetički test
  napisan s običnim razmakom uredno prođe. Detekcija neposlanog teksta traži
  alfanumerik iza prompta. Pouka šire: TUI parsere validiraj na uhvaćenom
  panelu (`tmux capture-pane … | od -An -tx1`), ne na vlastitoj fixture-i.
- `tmux send-keys -l "$msg"` prenosi navodnike, `$VAR` i `--flag` doslovno u
  TUI input; Enter mora ići kao zaseban `send-keys` nakon ~0.4 s.
- `split-window -l 60%` (ne stari `-p`) radi na 3.5a; postotak je relativan na
  pane koji se dijeli, pa je redoslijed splitova bitan (vidi `tim.sh`).
- Slanje `/clear` je lokalna TUI komanda — dobar način da se kanal testira bez
  ijednog API poziva.
- `status-right "#(cat …/.tim/status.line)"` uz `status-interval 5` daje
  ambijentalni napredak bez ijedne poruke u planner panel.
- **tmux paneli nasljeđuju okolinu tmux SERVERA, ne shella koji je pokrenuo
  skriptu** — zato `tim.sh` `TIM_SESSION` upisuje izravno u komandu svakog
  panela (`TIM_SESSION=… claude …`). Bez toga bi helper pozvan IZ panela kod
  `TIM_SESSION` overridea izvijestio o krivom (izvedenom) sessionu.
- Autostart čeka da se u planner panelu pojavi footer "bypass permissions"
  (do 20 s) prije nego pošalje `/pocni` — slanje prije toga TUI proguta.

## Isti obrazac u drugim repoima

`rodjendaonice.domovina.ai` ima svoju varijantu (session `tim-rodj`, 3 panela,
handoff dokumenti umjesto plan-fajlova). Kad se i ondje napravi ovaj prolaz,
ime mu po ovoj konvenciji postaje `tim-rodjendaonice-domovina-ai` — prefiks
`tim-` je zajednički da `tmux ls | grep '^tim-'` izlista sve timove na stroju.
