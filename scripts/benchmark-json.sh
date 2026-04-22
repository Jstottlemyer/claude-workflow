#!/usr/bin/env bash
# benchmark-json.sh — run graphify's benchmark against a project's graph and
# emit JSON to stdout. The graphify CLI only prints human-readable text, so
# we call the Python API directly via the graphify venv's interpreter.
#
# Usage:
#   benchmark-json.sh [graph-path]
#   (default: graphify-out/graph.json in cwd)

set -euo pipefail

GRAPH_PATH="${1:-graphify-out/graph.json}"
GRAPHIFY_PY="$HOME/.local/venvs/graphify/bin/python3"

[ -f "$GRAPH_PATH" ] || { echo '{"error": "graph not found"}'; exit 1; }
[ -x "$GRAPHIFY_PY" ] || { echo '{"error": "graphify venv python not found"}'; exit 1; }

"$GRAPHIFY_PY" - "$GRAPH_PATH" <<'PY'
import json, sys
from graphify.benchmark import run_benchmark
try:
    result = run_benchmark(sys.argv[1])
except Exception as e:
    result = {"error": f"benchmark failed: {e}"}
print(json.dumps(result))
PY
