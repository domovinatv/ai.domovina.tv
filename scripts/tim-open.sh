#!/usr/bin/env bash
# tim-open.sh [prompt…] — otvori NOVI maksimiziran iTerm2 prozor, digni tim u
# njemu i (ako je dan prompt) posij ga u planner panel.
#
#   ./scripts/tim-open.sh                       # attach na postojeći tim (ako radi)
#   ./scripts/tim-open.sh --fresh '<prompt>'    # ugasi stari tim pa digni ČIST
#   ./scripts/tim-open.sh 'Predaj timu redizajn Zida podrške. Plan: docs/plans/…'
#   ./scripts/tim-open.sh --dry-run 'test'      # ispiši što bi napravio, ne diraj ništa
#
# BEZ `--fresh` novi prozor se ATTACHA na postojeći session — to nije bug nego
# jedina sigurna opcija: tim.sh po dizanju provjeri `has-session` i attacha se.
# Drugi tim u istom repou ne postoji kao opcija (vidi komentar uz --fresh dolje).
#
# Zašto skripta a ne goli `osascript`: tri zamke koje su se pokazale u testu
# (iTerm2 3.6.10, macOS 15).
#
# ZAMKA 1: `create window with default profile command "…"` vraća `missing
# value` — ne možeš uhvatiti prozor koji si upravo stvorio. Zato prozor
# otvaramo BEZ komande (tada vraća pravi objekt) pa komandu utipkamo s
# `write text` u njegovu sesiju.
#
# ZAMKA 2: `current window` odmah nakon `create window` NIJE novi prozor —
# vratio je zatečeni Claude prozor i `set bounds` je otišao njemu. Uvijek radi
# nad uhvaćenim objektom, nikad nad `current window`.
#
# ZAMKA 3: prozor otvoren s komandom koja odmah završi digne iTermov modal
# „A session ended very soon after starting". `write text` u živi shell taj
# problem nema — shell ostaje i kad tim.sh padne, pa se greška vidi.
#
# Maksimiziranje: bounds se postave na cijeli desktop, a macOS ih sam podreže
# na vidljivi okvir (menu bar + dock) → 0,30,1920,990 na 1920×1080. Puni zaslon
# je i dalje ⌘+Enter, ručno — namjerno, jer fullscreen skriva ostale prozore.
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
[ "$(uname -s)" = "Darwin" ] || die "ovo je macOS/iTerm2 launcher; drugdje pokreni ./scripts/tim.sh ručno."
[ -d /Applications/iTerm.app ] || die "iTerm2 nije instaliran (/Applications/iTerm.app). Pokreni ./scripts/tim.sh u svom terminalu."
command -v tmux >/dev/null 2>&1 || die "tmux fali — 'brew install tmux'."
command -v claude >/dev/null 2>&1 || die "'claude' CLI nije u PATH-u."
[ -x ./scripts/tim.sh ] || die "./scripts/tim.sh ne postoji ili nije izvršna."

# Ne diži tim IZ tima — nested tmux + drugi Claude u istom stablu.
[ -z "${TMUX:-}" ] || die "već si u tmuxu ($TMUX). Ovo se pokreće izvan tima."

RESUME=0
if tmux has-session -t "$TARGET" 2>/dev/null; then
  if [ "$FRESH" -eq 1 ]; then
    # --fresh: ugasi stari tim pa digni čist. Namjerno NEMA varijante "digni
    # drugi tim uz postojeći": dev1/dev2 dijele radni direktorij, a orkestrator
    # je jedini koji commita — dva orkestratora u istom stablu neizbježno
    # commitaju jedan drugome nedovršen rad. Izolaciju bi rješavao worktree,
    # koji je odbačen (relativni path u pubspec.yaml + .env; vidi tim.sh header).
    echo "--fresh: gasim '$SESSION' (kontekst svih pet panela nestaje)…"
    if [ "$DRY" -eq 1 ]; then
      echo "[dry-run] preskačem stvarno gašenje"
    else
      ./scripts/tim-kill.sh || die "tim je zauzet — ili pričekaj, ili ./scripts/tim-kill.sh -f pa ponovi."
      for _ in $(seq 20); do
        tmux has-session -t "$TARGET" 2>/dev/null || break
        sleep 0.25
      done
      # Runtime stanje starog tima: pane mapa je mrtva, status linija laže.
      # Verdikte reviewera NE diramo — to je zapisnik, ne runtime.
      rm -f .tim/panes.env .tim/status.line
    fi
  else
    RESUME=1
    echo "NAPOMENA: session '$SESSION' već postoji — novi prozor će se ATTACHATI na njega,"
    echo "          neće se dizati drugi tim (tim.sh to sam radi)."
    echo "          Za čist tim: ./scripts/tim-open.sh --fresh '<prompt>'"
  fi
fi

# ----- kickoff prompt -------------------------------------------------------
# Claude Code TUI svaki \n čita kao submit, pa se višelinijski prompt NE šalje
# kroz send-keys. Zapišemo ga u fajl i pošaljemo jednu liniju s putanjom —
# isto pravilo kao u .claude/commands/delegiraj.md ("šalješ putanju, ne sadržaj").
KICKOFF=".tim/kickoff-prompt.md"
if [ -n "$PROMPT" ]; then
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

# ----- AppleScript ----------------------------------------------------------
# Komanda koja se utipka u novi prozor. TIM_AUTOSTART=0 kad imamo vlastiti
# prompt: inače bi tim.sh poslao /pocni i naša poruka bi mu upala u red čekanja
# usred odgovora. Orijentacija je tada dio kickoff fajla (vidi gore).
if [ -n "$PROMPT" ] && [ "$RESUME" -eq 0 ]; then
  LAUNCH="cd ${ROOT} && TIM_AUTOSTART=0 ./scripts/tim.sh"
else
  LAUNCH="cd ${ROOT} && ./scripts/tim.sh"
fi

# AppleScript literal: escapaj \ pa " (redoslijed je bitan).
as_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
LAUNCH_AS=$(as_escape "$LAUNCH")

if [ "$DRY" -eq 1 ]; then
  echo "[dry-run] session:  $SESSION (resume=$RESUME)"
  echo "[dry-run] iTerm:    novi prozor, bounds = cijeli desktop (macOS podreže)"
  echo "[dry-run] komanda:  $LAUNCH"
  if [ -n "$PROMPT" ] && [ "$RESUME" -eq 0 ]; then
    echo "[dry-run] planner:  tim-send.sh --force planner 'Pročitaj $KICKOFF pa izvrši.'"
  elif [ -n "$PROMPT" ]; then
    echo "[dry-run] planner:  PRESKAČEM slanje (session već postoji — vidi napomenu gore)"
  fi
  exit 0
fi

osascript <<APPLESCRIPT >/dev/null
tell application "Finder" to set d to bounds of window of desktop
tell application "iTerm"
	activate
	set nw to (create window with default profile)
	set bounds of nw to {item 1 of d, item 2 of d, item 3 of d, item 4 of d}
	set s to current session of nw
	tell s
		write text "${LAUNCH_AS}"
	end tell
end tell
APPLESCRIPT
echo "iTerm prozor otvoren, tim se diže…"

# ----- sijanje prompta ------------------------------------------------------
[ -n "$PROMPT" ] || exit 0

if [ "$RESUME" -eq 1 ]; then
  echo
  echo "Prompt NIJE poslan — session je već postojao, pa ne znam tipkaš li u planneru."
  echo "Pošalji ga sam kad je panel prazan:"
  echo "  ./scripts/tim-send.sh --force planner 'Pročitaj $KICKOFF pa izvrši.'"
  exit 0
fi

# 1. čekaj da tim.sh stvori session (pet Claude procesa, ~2-5 s)
for _ in $(seq 60); do
  tmux has-session -t "$TARGET" 2>/dev/null && break
  sleep 0.5
done
tmux has-session -t "$TARGET" 2>/dev/null \
  || die "session '$SESSION' se nije podigao za 30 s — pogledaj novi iTerm prozor."

# 2. čekaj da planner TUI proradi — isti detektor kao u tim.sh (footer s
#    permission modom). Bez ovoga poruka ode u prazno.
PLAN=$(tim_pane planner)
[ -n "$PLAN" ] || die "planner pane nije registriran u sessionu '$SESSION'."
READY=0
for _ in $(seq 60); do
  if tmux capture-pane -p -t "$PLAN" -S -20 2>/dev/null | grep -qi 'bypass permissions'; then
    READY=1; break
  fi
  sleep 0.5
done
[ "$READY" -eq 1 ] || die "planner TUI se nije javio za 30 s — pošalji prompt ručno (vidi ispod)."

# 3. jedna linija, s putanjom umjesto sadržaja. --force jer je panel nov i
#    prazan — jedini trenutak kad je pisanje u planner dopušteno (isto
#    obrazloženje kao autostart /pocni u tim.sh).
sleep 1
./scripts/tim-send.sh --force planner "Pročitaj $KICKOFF pa izvrši."
