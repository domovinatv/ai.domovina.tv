#!/usr/bin/env bash
# tim-kickoff.sh [--fresh] ['<prompt>'] — digni tim i posij planneru prvi
# zadatak. **Pokreće ga ČOVJEK, u iTerm prozoru koji je sam otvorio.**
#
#   ./scripts/tim-kickoff.sh --fresh          # ugasi stari tim, digni čist, attach
#   ./scripts/tim-kickoff.sh --fresh 'Predaj timu … Plan: docs/plans/….md'
#   ./scripts/tim-kickoff.sh                  # attach na postojeći (ili digni ako ga nema)
#   ./scripts/tim-kickoff.sh --dry-run --fresh
#
# Bez prompta u argumentu, a s postojećim `.tim/kickoff-prompt.md`, koristi se
# taj fajl — tako agent pripremi zadatak, a ti samo pokreneš komandu.
#
# ─── ZAŠTO OVDJE NEMA `osascript` ────────────────────────────────────────────
# Prijašnja verzija (`tim-open.sh`) otvarala je iTerm prozor sama. To je
# UKINUTO odlukom vlasnika 8.8.2026.: **iTerm prozor otvara isključivo čovjek,
# ručno.** Agent smije dizati tim i slati poruke panelima, ali ne smije
# stvarati, resizeati ni zatvarati prozore.
#
# Razlog nije estetika — izmjereno je kako se to lomi:
#   1. `create window with default profile command "…"` vraća `missing value`,
#      pa se prozor ne može uhvatiti.
#   2. `current window` odmah nakon `create window` NIJE novi prozor — u testu
#      je `set bounds` otišao zatečenom Claude prozoru korisnika.
#   3. Kad `--fresh` ubije session na koji su prozori attachani, njihov
#      `tmux attach` izađe u istoj sekundi i iTermov AppleScript se ZABLOKIRA
#      (`AppleEvent timed out -1712`) — trajno, do restarta iTerma. Tada je
#      stari tim bio ubijen a novi se nije digao.
#
# Ako ti treba prozor: ⌘N u iTermu, pa ovdje navedena komanda. ⌘+Enter za
# fullscreen.
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/tim-common.sh"

ROOT=$(tim_repo_root)
cd "$ROOT"
SESSION=$(tim_session_name)
TARGET=$(tim_target)

DRY=0
FRESH=0
while :; do
  case "${1:-}" in
    --dry-run) DRY=1; shift ;;
    --fresh)   FRESH=1; shift ;;
    *) break ;;
  esac
done
PROMPT="$*"

die() { echo "GREŠKA: $*" >&2; exit 1; }

# ----- preduvjeti -----------------------------------------------------------
command -v tmux >/dev/null 2>&1 || die "tmux fali — 'brew install tmux'."
command -v claude >/dev/null 2>&1 || die "'claude' CLI nije u PATH-u."
[ -x ./scripts/tim.sh ] || die "./scripts/tim.sh ne postoji ili nije izvršna."
[ -z "${TMUX:-}" ] || die "već si u tmuxu ($TMUX) — ovo se pokreće izvan tima."

KICKOFF=".tim/kickoff-prompt.md"

# ----- gašenje starog tima --------------------------------------------------
RESUME=0
if tmux has-session -t "$TARGET" 2>/dev/null; then
  if [ "$FRESH" -eq 1 ]; then
    # Namjerno NEMA varijante "digni drugi tim uz postojeći": dev1/dev2 dijele
    # radni direktorij, a orkestrator je jedini koji commita — dva orkestratora
    # u istom stablu commitaju jedan drugome nedovršen rad. Paralelan rad ide
    # kroz drugi REPO (session je tim-<repo-slug>).
    echo "--fresh: gasim '$SESSION' (kontekst svih pet panela nestaje)…"
    if [ "$DRY" -eq 1 ]; then
      echo "[dry-run] preskačem stvarno gašenje"
    else
      ./scripts/tim-kill.sh || die "tim je zauzet — pričekaj ili ./scripts/tim-kill.sh -f, pa ponovi."
      for _ in $(seq 20); do
        tmux has-session -t "$TARGET" 2>/dev/null || break
        sleep 0.25
      done
      # Mrtvo runtime stanje starog tima. Verdikti u .tim/reviews/ ostaju —
      # to je zapisnik, ne runtime.
      rm -f .tim/panes.env .tim/status.line
    fi
  else
    RESUME=1
    echo "Session '$SESSION' već radi — attacham se na njega."
    echo "Za čist tim: ./scripts/tim-kickoff.sh --fresh"
  fi
fi

# ----- kickoff prompt -------------------------------------------------------
# Claude Code TUI svaki \n čita kao submit, pa se višelinijski prompt NE šalje
# kroz send-keys. Zapiše se u fajl, a planneru ide samo putanja — isto pravilo
# kao u .claude/commands/delegiraj.md ("šalješ putanju, ne sadržaj").
SEND_PROMPT=0
if [ -n "$PROMPT" ]; then
  if [ "$DRY" -eq 1 ]; then
    echo "[dry-run] kickoff → $KICKOFF (ne pišem, da ne pregazim nepročitani)"
  else
    mkdir -p .tim
    cat > "$KICKOFF" <<EOF
# Kickoff za planner — $(date '+%Y-%m-%d %H:%M')

Prvo se orijentiraj po \`.claude/commands/pocni.md\` (uloge, provjera da su svi
paneli živi), zatim izvrši ovo:

---

$PROMPT
EOF
    echo "kickoff → $KICKOFF"
  fi
  SEND_PROMPT=1
elif [ -f "$KICKOFF" ]; then
  # Agent je pripremio zadatak, korisnik samo pokreće komandu.
  echo "kickoff: koristim postojeći $KICKOFF ($(wc -l < "$KICKOFF" | tr -d ' ') linija)"
  SEND_PROMPT=1
fi

if [ "$DRY" -eq 1 ]; then
  echo "[dry-run] session:  $SESSION (resume=$RESUME)"
  [ "$RESUME" -eq 0 ] && echo "[dry-run] tim:      TIM_AUTOSTART=$([ "$SEND_PROMPT" -eq 1 ] && echo 0 || echo 1) ./scripts/tim.sh (headless)"
  if [ "$SEND_PROMPT" -eq 1 ] && [ "$RESUME" -eq 0 ]; then
    echo "[dry-run] planner:  tim-send.sh --force planner 'Pročitaj $KICKOFF pa izvrši.'"
  elif [ "$SEND_PROMPT" -eq 1 ]; then
    echo "[dry-run] planner:  PRESKAČEM slanje (session već radi — ondje tipkaš)"
  fi
  echo "[dry-run] na kraju: $([ -t 1 ] && echo "exec tmux attach -t $TARGET" || echo "ispis attach komande (nema TTY)")"
  exit 0
fi

# ----- 1. tim (headless) ----------------------------------------------------
# tim.sh bez TTY-ja NE attacha se, samo javi ime sessiona. Attach radimo mi na
# kraju, da se prompt pošalje prije nego korisnik uđe u panel.
if [ "$RESUME" -eq 0 ]; then
  if [ "$SEND_PROMPT" -eq 1 ]; then
    TIM_AUTOSTART=0 ./scripts/tim.sh < /dev/null
  else
    ./scripts/tim.sh < /dev/null
  fi
  for _ in $(seq 60); do
    tmux has-session -t "$TARGET" 2>/dev/null && break
    sleep 0.5
  done
  tmux has-session -t "$TARGET" 2>/dev/null || die "session '$SESSION' se nije podigao za 30 s."
fi

# ----- 2. prompt ------------------------------------------------------------
if [ "$SEND_PROMPT" -eq 1 ] && [ "$RESUME" -eq 0 ]; then
  PLAN=$(tim_pane planner)
  [ -n "$PLAN" ] || die "planner pane nije registriran u sessionu '$SESSION'."
  READY=0
  for _ in $(seq 60); do
    if tmux capture-pane -p -t "$PLAN" -S -20 2>/dev/null | grep -qi 'bypass permissions'; then
      READY=1; break
    fi
    sleep 0.5
  done
  [ "$READY" -eq 1 ] || die "planner TUI se nije javio za 30 s — pošalji ručno:
  ./scripts/tim-send.sh --force planner 'Pročitaj $KICKOFF pa izvrši.'"
  # --force: panel je nov i prazan — jedini trenutak kad je pisanje u planner
  # dopušteno (isto obrazloženje kao autostart /pocni u tim.sh).
  sleep 1
  ./scripts/tim-send.sh --force planner "Pročitaj $KICKOFF pa izvrši."
elif [ "$SEND_PROMPT" -eq 1 ]; then
  echo
  echo "Prompt NIJE poslan — session je već radio, pa ne znam tipkaš li u planneru."
  echo "Pošalji ga sam kad je panel prazan:"
  echo "  ./scripts/tim-send.sh --force planner 'Pročitaj $KICKOFF pa izvrši.'"
fi

# ----- 3. attach ------------------------------------------------------------
if [ -t 1 ]; then
  echo "Attacham… (⌘+Enter za fullscreen, Ctrl+b d za detach)"
  exec tmux attach -t "$TARGET"
fi
echo
echo "Tim je gore. Attachaj se u iTerm prozoru koji si otvorio:"
echo "  tmux attach -t $TARGET"
