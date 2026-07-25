#!/usr/bin/env bash
# tim.sh — "AI tim" oneliner: 1 tmux session s 5 Claude Code panela, 100% YOLO.
#
#   ┌──────────────┬──────────────┬──────────────┐
#   │              │ orkestrator  │    dev1      │
#   │   planner    │   (fable)    │   (opus)     │
#   │   (opus)     ├──────────────┼──────────────┤
#   │   ← TI       │  reviewer    │    dev2      │
#   │              │   (fable)    │   (opus)     │
#   └──────────────┴──────────────┴──────────────┘
#
# Ti promptaš SAMO u lijevom (planner) panelu — kao u običnoj Claude Code
# sesiji. Kad je plan gotov, u planneru kažeš "daj timu" (ili /delegiraj) i
# plan ide orkestratoru, koji ga razbija na taskove za dev1/dev2, pa nakon
# njih pušta reviewera. Ti cijelo vrijeme vidiš sve u jednom iTerm prozoru
# i možeš dalje planirati sljedeći posao.
#
# Pokretanje (prazan iTerm2 window, ⌘+Enter za fullscreen):
#   cd ~/git/domovinatv/domovina.ai && ./scripts/tim.sh
#
# Puni opis petlje: docs/ai-tim-tmux.md
# Uloge/pravila: .claude/commands/{delegiraj,tim,pregled}.md
#
# Planneru se pri dizanju automatski pošalje /pocni (.claude/commands/pocni.md)
# — kickoff koji ga orijentira i provjeri da su svi paneli živi. Ne trebaš
# pamtiti nikakav uvodni prompt. Isključivanje: TIM_AUTOSTART=0
#
# Modeli (default: planiranje i pisanje koda = opus, koordinacija = fable):
#   TIM_MODEL_PLAN=opus TIM_MODEL_ORCH=fable TIM_MODEL_REVIEW=fable \
#   TIM_MODEL_DEV=opus ./scripts/tim.sh
#
# SVI paneli rade s --dangerously-skip-permissions (ništa ne pita) — po
# eksplicitnoj odluci vlasnika repoa. Za oprezniji mod makni tu zastavicu
# ili je zamijeni s --permission-mode acceptEdits.
#
# Zašto NE `claude --tmux` / `--worktree`: --tmux traži --worktree i radi
# jedan session po worktree-u (iTerm2 native panes), a ne ovaj layout kojim
# orkestrator upravlja preko tmux send-keys. Worktree za devove namjerno ne
# koristimo — lomi relativni path dependency u pubspec.yaml
# (../../stepanic/flutter_certilia) i nema .env; izolaciju čuva pravilo
# "disjunktni fajlovi" u /tim komandi.
#
# Ponovno pokretanje istog onelinera samo se attacha na postojeći session.
# Ime sessiona je izvedeno iz repo direktorija (domovina.ai → tim-domovina-ai) da
# timovi za različite projekte na istom Macu ne kolidiraju; override: TIM_SESSION=…
# Gašenje SAMO ovog tima:  tmux kill-session -t "=$(./scripts/tim-status.sh session)"
# Popis svih timova:       tmux ls | grep '^tim-'
set -euo pipefail

. "$(cd "$(dirname "$0")" && pwd)/tim-common.sh"
SESSION=$(tim_session_name)     # tim-<repo-slug>, npr. tim-domovina-ai
TARGET=$(tim_target)            # "=$SESSION" — egzaktan match (has-session/attach/list-panes)
OPT=$(tim_opt_target)           # golo ime — set-option/rename-window ne primaju "=" (vidi tim-common.sh)
MODEL_PLAN="${TIM_MODEL_PLAN:-opus}"
MODEL_ORCH="${TIM_MODEL_ORCH:-fable}"
MODEL_REVIEW="${TIM_MODEL_REVIEW:-fable}"
MODEL_DEV="${TIM_MODEL_DEV:-opus}"
cd "$(cd "$(dirname "$0")/.." && pwd)"

command -v tmux >/dev/null 2>&1 || { echo "tmux fali — instaliram (brew)…"; brew install tmux; }
command -v claude >/dev/null 2>&1 || { echo "GREŠKA: 'claude' CLI nije u PATH-u"; exit 1; }

if tmux has-session -t "$TARGET" 2>/dev/null; then
  echo "Session '$SESSION' već postoji — attacham."
  exec tmux attach -t "$TARGET"
fi

# Runtime stanje tima (gitignorirano): pane mapa, verdikti reviewera, status
# linija koju tmux status bar prikazuje.
mkdir -p .tim/reviews
: > .tim/status.line

# ── Uloge u system promptu ────────────────────────────────────────────────
# Ide u --append-system-prompt da ih orkestrator ne mora ponavljati u svakom
# tasku, i da panel zna svoju ulogu i bez slash komande.

REPO_RULES='Repo je Flutter web/mobile app (DOMOVINA.ai). CLAUDE.md u rootu je obavezno štivo — poštuj sve Rule sekcije (i18n kroz app_hr.arb pa app_en.arb, nikad SharedPreferences na webu, theme tokeni umjesto konstanti, padding unutar scrollabla). Verifikacija: `flutter analyze` mora biti čist. NAPOMENA: test/widget_test.dart (HttpClient smoke) i home_feed_test (datum-ovisan) padaju i na čistom mainu — to NISU regresije.'

planner_prompt() {
  printf 'Ti si PLANNER — lijevi panel AI tima u tmux sessionu "%s"; ovdje korisnik promptira izravno i ovo mu je glavni chat. Tvoj posao je istraživanje koda, dijalog s korisnikom i pisanje plana, a NE izvođenje većih zahvata: kad je plan gotov i korisnik kaže "daj timu" (ili pokrene /delegiraj), plan zapiši u docs/plans/ i pošalji ga orkestratoru — pravila su u .claude/commands/delegiraj.md. Dok tim radi, TI NE MIJENJAŠ kod (dev1 i dev2 dijele isti radni direktorij i pregazili biste se) — smiješ pisati samo docs/plans/*; iznimka je jednolinijski hitni popravak koji korisnik izričito traži i za koji si provjerio da ga nijedan aktivni task ne dira. Status tima čitaš sa scripts/tim-status.sh i scripts/tim-read.sh, nikad ne šalješ poruke u svoj vlastiti panel. %s' "$SESSION" "$REPO_RULES"
}

orch_prompt() {
  printf 'Ti si ORKESTRATOR AI tima u tmux sessionu "%s" (paneli: planner, dev1, dev2, reviewer). Na početku sessiona pročitaj .claude/commands/tim.md — to su tvoja pravila rada; poslove ti šalje planner kao putanju do plana u docs/plans/. Ti si jedini koji commita, deploya i integrira. NIKAD ne šalji poruke u planner panel (korisnik ondje tipka — prekinuo bi ga); status javljaš preko scripts/tim-status.sh set "…". %s' "$SESSION" "$REPO_RULES"
}

review_prompt() {
  printf 'Ti si REVIEWER AI tima u tmux sessionu "%s". Pravila su u .claude/commands/pregled.md — pročitaj ih kad dobiješ prvi zadatak. Ne mijenjaš kod NIKAD: čitaš git diff radnog stabla, uspoređuješ ga s planom, pokrećeš `flutter analyze` (i ciljane testove), pa pišeš verdikt u .tim/reviews/. Dorade izvršavaju dev1/dev2, ne ti. Budi strog ali konkretan: svaki nalaz mora imati fajl:liniju i posljedicu, bez stilskih dlakocjepstava. %s' "$SESSION" "$REPO_RULES"
}

dev_prompt() {
  printf 'Ti si %s — izvršni developer u AI timu (tmux session "%s"). Taskove ti šalje orkestrator, a tvoj rad nakon toga pregledava reviewer i može ti vratiti dorade — dorade radiš bez rasprave, u istom kontekstu. Radi TOČNO opisani task, ništa šire: ne diraj fajlove izvan opsega jer paralelno radi drugi dev u istom direktoriju. NE commitaj, NE pushaj, NE deployaj, NE pokreći scripts/deploy.sh — to radi orkestrator. Kad završiš, zadnji blok odgovora MORA počinjati linijom koja glasi točno "SAŽETAK" (velikim slovima, sama u redu) — po njoj te nadzor prepoznaje kao gotovog. Ispod nje: promijenjeni fajlovi, kako je verificirano, i što si NAMJERNO ostavio nedovršeno. %s' "$1" "$SESSION" "$REPO_RULES"
}

# tmux [new-session|split-window] spaja višestruke argumente razmakom u
# JEDAN shell string, pa svaki arg mora biti shell-quoted (printf %q) —
# inače se --append-system-prompt tekst raspadne na riječi.
q() { printf '%q ' "$@"; }
# TIM_SESSION eksplicitno u okolinu svakog panela: tmux paneli NASLJEĐUJU
# okolinu tmux SERVERA, ne shella koji je pokrenuo skriptu — bez ovoga bi
# helperi pozvani IZ panela (tim-status.sh…) kod TIM_SESSION overridea
# gađali krivi session (izvedeno ime umjesto stvarnog).
ENVP="TIM_SESSION=$(printf '%q' "$SESSION") "
CMD_PLAN=$ENVP$(q claude --dangerously-skip-permissions \
  --model "$MODEL_PLAN" -n planner --append-system-prompt "$(planner_prompt)")
CMD_ORCH=$ENVP$(q claude --dangerously-skip-permissions \
  --model "$MODEL_ORCH" -n orkestrator --append-system-prompt "$(orch_prompt)")
CMD_REVW=$ENVP$(q claude --dangerously-skip-permissions \
  --model "$MODEL_REVIEW" -n reviewer --append-system-prompt "$(review_prompt)")
CMD_DEV1=$ENVP$(q claude --dangerously-skip-permissions \
  --model "$MODEL_DEV" -n dev1 --append-system-prompt "$(dev_prompt dev1)")
CMD_DEV2=$ENVP$(q claude --dangerously-skip-permissions \
  --model "$MODEL_DEV" -n dev2 --append-system-prompt "$(dev_prompt dev2)")

# Pane ID-evi (%N) su stabilni neovisno o base-index konfiguraciji korisnika.
# Layout: planner 36% | orkestrator+reviewer 32% | dev1+dev2 32%.
P_PLAN=$(tmux new-session -d -s "$SESSION" -c "$PWD" -P -F '#{pane_id}' "$CMD_PLAN")
P_ORCH=$(tmux split-window -h -t "$P_PLAN" -c "$PWD" -l 64% -P -F '#{pane_id}' "$CMD_ORCH")
P_DEV1=$(tmux split-window -h -t "$P_ORCH" -c "$PWD" -l 50% -P -F '#{pane_id}' "$CMD_DEV1")
P_REVW=$(tmux split-window -v -t "$P_ORCH" -c "$PWD" -l 45% -P -F '#{pane_id}' "$CMD_REVW")
P_DEV2=$(tmux split-window -v -t "$P_DEV1" -c "$PWD" -l 50% -P -F '#{pane_id}' "$CMD_DEV2")

# Uloga → pane ID. Claude Code TUI pregazi pane_title, pa uloge držimo u
# tmux user opcijama: na pane-u (@role, za border) i na sessionu (@tim_<uloga>,
# za lookup iz skripti). Format #{@role} se rezolvira kroz hijerarhiju
# pane→window→session, pa border uvijek pokazuje točnu ulogu.
set_role() {
  tmux set -p -t "$2" @role "$1"
  tmux set -t "$OPT" "@tim_$1" "$2"
  tmux select-pane -t "$2" -T "$1"
}
set_role planner     "$P_PLAN"
set_role orkestrator "$P_ORCH"
set_role reviewer    "$P_REVW"
set_role dev1        "$P_DEV1"
set_role dev2        "$P_DEV2"

# Mapa i za ne-tmux potrošače (debug, `cat .tim/panes.env`).
cat > .tim/panes.env <<EOF
TIM_SESSION=$SESSION
TIM_PANE_PLANNER=$P_PLAN
TIM_PANE_ORKESTRATOR=$P_ORCH
TIM_PANE_REVIEWER=$P_REVW
TIM_PANE_DEV1=$P_DEV1
TIM_PANE_DEV2=$P_DEV2
EOF

tmux set -t "$OPT" pane-border-status top
tmux set -t "$OPT" pane-border-format ' #{pane_id} #{@role} '
tmux set -t "$OPT" mouse on
tmux set -w -t "$OPT" automatic-rename off
tmux rename-window -t "$OPT" tim

# Ambijentalni status: orkestrator piše u .tim/status.line
# (scripts/tim-status.sh set "…"), tmux ga vrti u status baru — tako vidiš
# napredak bez da itko upada u tvoj planner panel.
tmux set -t "$OPT" status-interval 5
tmux set -t "$OPT" status-right-length 140
tmux set -t "$OPT" status-right "#(cat '$PWD/.tim/status.line' 2>/dev/null) "

tmux select-pane -t "$P_PLAN"

# Kickoff: planneru pošalji /pocni (.claude/commands/pocni.md) čim mu TUI
# proradi — da ne moraš pamtiti nikakav uvodni prompt. Ovo je JEDINI trenutak
# kad išta ide u planner panel: session je nov, korisnik još ne tipka.
# Isključivanje: TIM_AUTOSTART=0 ./scripts/tim.sh
if [ "${TIM_AUTOSTART:-1}" != "0" ]; then
  for _ in $(seq 40); do
    # TUI je spreman kad iscrta footer s permission modom (~2-4 s).
    tmux capture-pane -p -t "$P_PLAN" -S -20 2>/dev/null | grep -qi 'bypass permissions' && break
    sleep 0.5
  done
  tmux send-keys -t "$P_PLAN" -l '/pocni'
  sleep 0.4
  tmux send-keys -t "$P_PLAN" Enter
fi

if [ -t 0 ]; then
  exec tmux attach -t "$TARGET"
else
  echo "Session '$SESSION' spreman — attachaj s: tmux attach -t =$SESSION"
fi
