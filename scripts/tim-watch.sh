#!/usr/bin/env bash
# tim-watch.sh — nadzornik AI tima: prati sve panele i javlja SAMO događaje na
# koje se reagira. Svaka linija na stdout je jedan događaj (format za Monitor /
# `tail -f`), a povijest ide u .tim/watch.log.
#
#   ./scripts/tim-watch.sh            # petlja (default svakih 20 s)
#   ./scripts/tim-watch.sh --once     # jedan prolaz pa izlaz
#   TIM_WATCH_INTERVAL=10 ./scripts/tim-watch.sh
#
# Što javlja:
#   GOTOV      dev prešao iz rada u mirovanje i ispisao SAŽETAK
#   MIRUJE     panel prestao raditi bez SAŽETKA (sumnjivo — prekid ili greška)
#   BLOKIRAN   panel čeka odgovor (picker "Enter to select" / dijalog)
#   GREŠKA     u panelu je API/tool greška, rate limit, crash
#   KONTEKST   panel prešao 70 % konteksta (vrijeme za /compact ili /clear)
#   VERDIKT    reviewer je zapisao novi .tim/reviews/*.md
#   PANEL      panel je nestao (zatvoren/ugašen)
#   TIM        session je nestao → watcher staje
#
# NAMJERNO ne javlja početke radova ni svaku promjenu stanja — inače bi
# nadzor bio bučniji od samog tima.
#
# Watcher NIŠTA ne šalje panelima i ništa ne mijenja u repou. Čisti promatrač.
set -uo pipefail   # bez -e: nadzornik mora preživjeti tranzijentne greške
. "$(cd "$(dirname "$0")" && pwd)/tim-common.sh"

SESSION=$(tim_session_name)
TARGET=$(tim_target)
ROOT=$(tim_repo_root)
INTERVAL="${TIM_WATCH_INTERVAL:-20}"
ONCE=0
[ "${1:-}" = "--once" ] && ONCE=1

mkdir -p "$ROOT/.tim/reviews"
LOG="$ROOT/.tim/watch.log"

emit() {
  printf '%s %s\n' "$(date +%H:%M:%S)" "$1"
  printf '%s %s\n' "$(date '+%F %T')" "$1" >> "$LOG"
}

snap() { tmux capture-pane -p -t "$1" -S -40 2>/dev/null | cat -s; }

# Marker skupovi. Držani kao fiksni stringovi (BSD grep + multibajtni TUI znaci).
is_blocked() { printf '%s' "$1" | grep -qE 'Enter to select|Tab/Arrow keys|Do you want to|❯ 1\. Yes'; }
has_error()  { printf '%s' "$1" | grep -qE 'API Error|Request timed out|rate limit|Overloaded|usage limit reached|Killed: 9|command not found|Segmentation fault|Traceback \(most recent'; }
has_summary() { printf '%s' "$1" | grep -qiE 'SAŽETAK|SAZETAK'; }
ctx_pct() {
  # footer: "ctx: 134.4k/1.0M (13%)"
  printf '%s' "$1" | grep -oE 'ctx: [^)]*\(([0-9]+)%\)' | tail -1 | grep -oE '\(([0-9]+)%\)' | tr -dc '0-9'
}

ROLES=(planner orkestrator reviewer dev1 dev2)
PREV_SNAP=(); PREV_BUSY=(); PREV_BLOCK=(); PREV_ERR=(); PREV_CTX=()
for i in "${!ROLES[@]}"; do PREV_SNAP[$i]=""; PREV_BUSY[$i]=0; PREV_BLOCK[$i]=0; PREV_ERR[$i]=0; PREV_CTX[$i]=0; done
SEEN_REVIEWS=$(ls "$ROOT"/.tim/reviews/*.md 2>/dev/null | tr '\n' ' ')

emit "TIM watcher pokrenut na sessionu $SESSION (interval ${INTERVAL}s)"

while :; do
  if ! tmux has-session -t "$TARGET" 2>/dev/null; then
    emit "TIM session $SESSION je nestao — watcher staje"
    exit 0
  fi

  for i in "${!ROLES[@]}"; do
    role="${ROLES[$i]}"
    pane=$(tim_pane "$role")
    if [ -z "$pane" ] || ! tmux list-panes -t "$TARGET" -F '#{pane_id}' 2>/dev/null | grep -qx "$pane"; then
      [ "${PREV_BUSY[$i]}" = "gone" ] || { emit "PANEL $role je nestao"; PREV_BUSY[$i]=gone; }
      continue
    fi

    cur=$(snap "$pane")
    busy=0
    [ -n "${PREV_SNAP[$i]}" ] && [ "$cur" != "${PREV_SNAP[$i]}" ] && busy=1

    # BLOKIRAN — čeka odgovor. Javi jednom po pojavi.
    if is_blocked "$cur"; then
      [ "${PREV_BLOCK[$i]}" -eq 1 ] || emit "BLOKIRAN $role čeka odgovor (picker/dijalog) — pogledaj: ./scripts/tim-read.sh $role"
      PREV_BLOCK[$i]=1
    else
      PREV_BLOCK[$i]=0
    fi

    # GREŠKA — javi jednom dok traje.
    if has_error "$cur"; then
      [ "${PREV_ERR[$i]}" -eq 1 ] || emit "GREŠKA u panelu $role — ./scripts/tim-read.sh $role 60"
      PREV_ERR[$i]=1
    else
      PREV_ERR[$i]=0
    fi

    # Prijelaz rad → mirovanje: gotov posao ili tihi prekid.
    if [ "${PREV_BUSY[$i]}" = "1" ] && [ "$busy" -eq 0 ]; then
      if has_summary "$cur"; then
        emit "GOTOV $role je završio i ispisao SAŽETAK"
      elif ! is_blocked "$cur"; then
        emit "MIRUJE $role je stao bez SAŽETKA — provjeri je li prekinut"
      fi
    fi
    [ "${PREV_BUSY[$i]}" = "gone" ] || PREV_BUSY[$i]=$busy

    # Kontekst preko 70 % — jednom po prelasku praga.
    pct=$(ctx_pct "$cur"); pct=${pct:-0}
    if [ "$pct" -ge 70 ] 2>/dev/null && [ "${PREV_CTX[$i]}" -lt 70 ]; then
      emit "KONTEKST $role na ${pct}% — vrijeme za /compact (u tijeku) ili /clear (nakon verdikta)"
    fi
    PREV_CTX[$i]=$pct
    PREV_SNAP[$i]="$cur"
  done

  # Novi verdikt reviewera.
  for f in "$ROOT"/.tim/reviews/*.md; do
    [ -e "$f" ] || continue
    case " $SEEN_REVIEWS " in
      *" $f "*) ;;
      *) emit "VERDIKT $(basename "$f"): $(head -1 "$f")"; SEEN_REVIEWS="$SEEN_REVIEWS $f" ;;
    esac
  done

  [ "$ONCE" -eq 1 ] && break
  sleep "$INTERVAL"
done
