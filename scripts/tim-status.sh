#!/usr/bin/env bash
# tim-status.sh — stanje AI tima.
#
#   ./scripts/tim-status.sh                 # tko radi, tko čeka, zadnji verdikti
#   ./scripts/tim-status.sh set "T3 dev1 · T4 dev2 · review pending"
#                                           # ambijentalna linija u tmux status baru
#
# "set" je jedini način da orkestrator javi napredak korisniku a da mu NE
# upadne u planner panel — tmux status bar se osvježava svakih 5 s.
#
# BUSY/IDLE je heuristika: Claude Code TUI dok radi drži "esc to interrupt"
# na dnu panela. Ako je panel u nekom dijalogu, pokaže se kao IDLE — zato
# prije zaključka pogledaj scripts/tim-read.sh <uloga>.
set -euo pipefail

SESSION="${TIM_SESSION:-tim}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ROLES="planner orkestrator reviewer dev1 dev2"

if [ "${1:-}" = "set" ]; then
  shift
  mkdir -p "$ROOT/.tim"
  printf '%s' "$*" > "$ROOT/.tim/status.line"
  echo "status: $*"
  exit 0
fi

tmux has-session -t "$SESSION" 2>/dev/null || { echo "Session '$SESSION' ne radi (pokreni ./scripts/tim.sh)." >&2; exit 1; }

printf '%-12s %-5s %-6s %s\n' ULOGA PANE STANJE 'ZADNJA LINIJA'
for role in $ROLES; do
  pane=$(tmux show -v -t "$SESSION" "@tim_$role" 2>/dev/null || true)
  [ -n "$pane" ] || continue
  tail=$(tmux capture-pane -p -t "$pane" -S -25 2>/dev/null | cat -s || true)
  if printf '%s' "$tail" | grep -qi 'esc to interrupt'; then state=BUSY; else state=IDLE; fi
  last=$(printf '%s' "$tail" | grep -v '^[[:space:]]*$' | tail -1 | cut -c1-60)
  printf '%-12s %-5s %-6s %s\n' "$role" "$pane" "$state" "$last"
done

if [ -s "$ROOT/.tim/status.line" ]; then
  printf '\nstatus bar: %s\n' "$(cat "$ROOT/.tim/status.line")"
fi

if compgen -G "$ROOT/.tim/reviews/*.md" > /dev/null; then
  echo
  echo "verdikti (.tim/reviews/):"
  for f in "$ROOT"/.tim/reviews/*.md; do
    printf '  %-40s %s\n' "$(basename "$f")" "$(head -1 "$f")"
  done
fi
