#!/usr/bin/env bash
# tim.sh — "AI tim" oneliner: 1 tmux session s 3 Claude Code panela.
#
#   ┌───────────────┬───────────────┐
#   │               │     dev1      │
#   │  orkestrator  ├───────────────┤
#   │               │     dev2      │
#   └───────────────┴───────────────┘
#
# Pokretanje (prazan iTerm2 window):
#   cd ~/git/domovinatv/domovina.ai && ./scripts/tim.sh
#
# U lijevom panelu (orkestrator) utipkaj:  /tim <opis posla>
# — slash komanda (.claude/commands/tim.md) uči orkestratora kako slati
# taskove dev panelima, čitati im output i čistiti im kontekst.
#
# Ponovno pokretanje istog onelinera samo se attacha na postojeći session.
# Gašenje svega: tmux kill-session -t tim
set -euo pipefail

SESSION=tim
cd "$(cd "$(dirname "$0")/.." && pwd)"

command -v tmux >/dev/null 2>&1 || { echo "tmux fali — instaliram (brew)…"; brew install tmux; }
command -v claude >/dev/null 2>&1 || { echo "GREŠKA: 'claude' CLI nije u PATH-u"; exit 1; }

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Session '$SESSION' već postoji — attacham."
  exec tmux attach -t "$SESSION"
fi

# Pane ID-evi (%N) su stabilni neovisno o base-index konfiguraciji korisnika.
P_ORCH=$(tmux new-session -d -s "$SESSION" -c "$PWD" -P -F '#{pane_id}' claude)
P_DEV1=$(tmux split-window -h -t "$P_ORCH" -c "$PWD" -P -F '#{pane_id}' claude)
P_DEV2=$(tmux split-window -v -t "$P_DEV1" -c "$PWD" -P -F '#{pane_id}' claude)

tmux select-pane -t "$P_ORCH" -T orkestrator
tmux select-pane -t "$P_DEV1" -T dev1
tmux select-pane -t "$P_DEV2" -T dev2

# Border prikazuje pane_id + naslov. NAPOMENA: Claude Code TUI runtime
# pregazi pane_title ("✳ Claude Code…"), pa se za targetiranje koristi
# pane_id + geometrija (orkestrator = lijevi stupac; vidi .claude/commands/tim.md).
tmux set -t "$SESSION" pane-border-status top
tmux set -t "$SESSION" pane-border-format ' #{pane_id} #{pane_title} '
tmux set -t "$SESSION" mouse on

tmux select-pane -t "$P_ORCH"

if [ -t 0 ]; then
  exec tmux attach -t "$SESSION"
else
  echo "Session '$SESSION' spreman — attachaj s: tmux attach -t $SESSION"
fi
