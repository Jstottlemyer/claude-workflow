#!/usr/bin/env bash
# benchmarks-all.sh — weekly launchd target. Walks owned projects, refreshes
# the benchmark JSON, and appends a benchmark-weekly record to each
# project's dashboard JSONL.

set -euo pipefail

WORKFLOW_ROOT="$HOME/Projects/MonsterFlow"
PROJECTS_ROOT="$HOME/Projects"
GRAPHIFY="$HOME/.local/bin/graphify"
LOG="$WORKFLOW_ROOT/dashboard/data/.benchmarks.log"

mkdir -p "$(dirname "$LOG")"
exec >>"$LOG" 2>&1
echo "--- $(date -u +%Y-%m-%dT%H:%M:%SZ) benchmarks-all start ---"

classify_project() {
  case "$1" in
    graphify|obsidian-wiki)   echo "upstream-readonly" ;;
    _archive)                 echo "skip" ;;
    security)                 echo "security" ;;
    career)                   echo "career" ;;
    Mobile)                   echo "ios-swift" ;;
    *)                        echo "default" ;;
  esac
}

for entry in "$PROJECTS_ROOT"/*; do
  [ -d "$entry" ] || continue
  name=$(basename "$entry")
  # Skip upstream-readonly, skip-marked, and dirs without graphify-out
  kind=$(classify_project "$name")
  [ "$kind" = "upstream-readonly" ] && continue
  [ "$kind" = "skip" ] && continue
  [ -f "$entry/graphify-out/graph.json" ] || continue

  echo "[$name] running benchmark"
  bench_json="$entry/graphify-out/last-benchmark.json"
  if (cd "$entry" && "$HOME/.local/venvs/graphify/bin/python3" - <<'PY' 2>/dev/null >"$bench_json"
import json
from graphify.benchmark import run_benchmark
try:
    result = run_benchmark("graphify-out/graph.json")
except Exception as e:
    result = {"error": str(e)}
print(json.dumps(result))
PY
  ); then
    "$WORKFLOW_ROOT/scripts/dashboard-append.sh" \
      --event benchmark-weekly \
      --project "$name" \
      --cwd "$entry" || true
  else
    echo "[$name] benchmark failed"
  fi
done

echo "[cost-backfill] estimating build tokens where missing"
"$WORKFLOW_ROOT/scripts/graphify-cost-backfill.sh" || true

echo "[wiki-benchmark] measuring wiki-query efficiency"
"$WORKFLOW_ROOT/scripts/wiki-benchmark.sh" || true

echo "--- done ---"
