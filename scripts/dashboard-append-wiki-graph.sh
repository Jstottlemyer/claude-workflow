#!/usr/bin/env bash
# Thin wrapper: appends a wiki-graph-weekly event to dashboard data for project=wiki-graph.
set -euo pipefail
WORKFLOW_ROOT="$HOME/Projects/claude-workflow"
"$WORKFLOW_ROOT/scripts/dashboard-append.sh" \
  --event wiki-graph-weekly \
  --project wiki-graph \
  --cwd "$HOME/Projects/wiki-graph"
