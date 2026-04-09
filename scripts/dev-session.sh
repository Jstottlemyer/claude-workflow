#!/usr/bin/env bash
# Usage:
#   dev-session.sh              — generic 4-window dev session in cwd
#   dev-session.sh cosmic       — CosmicExplorer preset
#   dev-session.sh <name> <dir> — custom session in specified directory

set -euo pipefail

preset="${1:-default}"
SESSION=""
PROJECT_DIR=""

case "$preset" in
  cosmic)
    SESSION="cosmic"
    PROJECT_DIR="$HOME/Projects/Mobile/CosmicExplorer"
    ;;
  *)
    SESSION="${1:-dev}"
    PROJECT_DIR="${2:-$(pwd)}"
    ;;
esac

# Attach if session already exists
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Attaching to existing session: $SESSION"
  exec tmux attach -t "$SESSION"
fi

# Window 1: Claude Code (main workspace)
tmux new-session -d -s "$SESSION" -n "claude" -c "$PROJECT_DIR"

# Window 2: Build & Test output
tmux new-window -t "$SESSION" -n "build" -c "$PROJECT_DIR"

# Window 3: Simulator / Logs
tmux new-window -t "$SESSION" -n "logs" -c "$PROJECT_DIR"
tmux send-keys -t "$SESSION:logs" "# Simulator logs: xcrun simctl spawn booted log stream --predicate 'subsystem == \"com.cosmicexplorer\"'" Enter

# Window 4: Git & file watching
tmux new-window -t "$SESSION" -n "git" -c "$PROJECT_DIR"
tmux send-keys -t "$SESSION:git" "git status" Enter

# Session logging — pipe claude window output to a shared file
LOG_DIR="$HOME/.claude/session-logs"
LOG_FILE="$LOG_DIR/${SESSION}-$(date +%Y%m%d-%H%M%S).log"
tmux pipe-pane -t "$SESSION:claude" -o "cat >> '$LOG_FILE'"

# Select window 1 and launch Claude Code with remote-control
tmux select-window -t "$SESSION:claude"
tmux send-keys -t "$SESSION:claude" "claude --dangerously-skip-permissions" Enter
sleep 3
tmux send-keys -t "$SESSION:claude" "/remote-control" Enter

# Attach
exec tmux attach -t "$SESSION"
