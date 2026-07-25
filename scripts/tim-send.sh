#!/usr/bin/env bash
# tim-send.sh <uloga> <poruka…> — pošalji JEDNU liniju u Claude Code panel.
#
#   ./scripts/tim-send.sh dev1 'Pročitaj docs/plans/2026-07-25-x.md pa izvrši task T1.'
#   ./scripts/tim-send.sh dev2 /clear
#
# Uloge: planner | orkestrator | reviewer | dev1 | dev2
#
# Zašto skripta a ne goli send-keys: pane ID se čita iz tmux user opcije
# (@tim_<uloga>) koju je postavio tim.sh, tekst ide u -l literal modu (ne
# interpretira se kao imena tipki, pa navodnici/$/- prolaze netaknuti), a
# Enter ide ODVOJENO nakon kratke pauze — Claude Code TUI inače proguta red.
set -euo pipefail

SESSION="${TIM_SESSION:-tim}"
FORCE=0
[ "${1:-}" = "--force" ] && { FORCE=1; shift; }

role="${1:-}"; shift || true
msg="$*"
[ -n "$role" ] && [ -n "$msg" ] || {
  echo "upotreba: tim-send.sh [--force] <planner|orkestrator|reviewer|dev1|dev2> <poruka>" >&2
  exit 1
}

case "$msg" in
  *$'\n'*)
    echo "GREŠKA: poruka mora biti JEDNA linija — Claude TUI svaki \\n čita kao submit." >&2
    echo "       Dugi sadržaj zapiši u fajl pa pošalji putanju ('Pročitaj X pa izvrši')." >&2
    exit 1 ;;
esac

if [ "$role" = "planner" ] && [ "$FORCE" -eq 0 ]; then
  echo "ODBIJENO: u planner panel se ne šalje — ondje korisnik tipka i poruka bi mu" >&2
  echo "          upala usred prompta. Status javi s: scripts/tim-status.sh set \"…\"" >&2
  echo "          (ako baš moraš i znaš da je panel prazan: --force)" >&2
  exit 2
fi

pane=$(tmux show -v -t "$SESSION" "@tim_$role" 2>/dev/null || true)
[ -n "$pane" ] || { echo "GREŠKA: uloga '$role' nije registrirana u sessionu '$SESSION'." >&2; exit 1; }
tmux list-panes -t "$SESSION" -F '#{pane_id}' | grep -qx "$pane" || {
  echo "GREŠKA: pane $pane ($role) više ne postoji — je li panel zatvoren?" >&2; exit 1; }

tmux send-keys -t "$pane" -l "$msg"
sleep 0.4
tmux send-keys -t "$pane" Enter
echo "→ $role ($pane): $msg"
