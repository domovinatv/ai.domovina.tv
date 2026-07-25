#!/usr/bin/env bash
# tim-read.sh <uloga> [linija] — pročitaj zadnjih N linija iz panela (default 80).
#
#   ./scripts/tim-read.sh dev1
#   ./scripts/tim-read.sh reviewer 200
#
# Prazne linije se kolabiraju (Claude TUI ih baca na desetke) da ti capture
# ne pojede kontekst.
set -euo pipefail

SESSION="${TIM_SESSION:-tim}"
role="${1:-}"
lines="${2:-80}"
[ -n "$role" ] || { echo "upotreba: tim-read.sh <planner|orkestrator|reviewer|dev1|dev2> [linija]" >&2; exit 1; }

pane=$(tmux show -v -t "$SESSION" "@tim_$role" 2>/dev/null || true)
[ -n "$pane" ] || { echo "GREŠKA: uloga '$role' nije registrirana u sessionu '$SESSION'." >&2; exit 1; }

tmux capture-pane -p -t "$pane" -S "-$lines" | cat -s
