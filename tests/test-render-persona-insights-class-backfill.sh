#!/usr/bin/env bash
##############################################################################
# tests/test-render-persona-insights-class-backfill.sh
#
# Wave 3 task 3.10 (pipeline-gate-permissiveness) — verifies the class
# back-fill in scripts/_render_persona_insights_text.py:
#
#   - findings.jsonl rows lacking `class:` default to "unclassified"
#   - per-class survival aggregation filters out class == "unclassified"
#     so pre-v0.9.0 rows don't pollute per-class stats
#   - rows with explicit class values from the v1 enum
#     (architectural, security, contract, documentation, tests, scope-cuts)
#     pass through unchanged
#
# Spec: docs/specs/pipeline-gate-permissiveness/spec.md §"Persona-metrics
# integration" (line 339): "/wrap-insights Phase 1c reads `class` with
# default `unclassified` for missing-field rows, AND filters survival-rate
# joins to `class != \"unclassified\"`".
#
# Strategy: the renderer's public render() function reads pre-aggregated
# persona-rankings.jsonl, NOT raw findings.jsonl — per the integration
# persona's analysis the back-fill lives at the renderer's row-consumption
# layer as forward-compatible helpers (backfill_class, aggregate_survival_
# by_class). We exercise those helpers directly via a Python harness over
# synthetic findings.jsonl fixtures (pre-v0.9.0, post-v0.9.0, mixed).
##############################################################################
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RENDERER="$REPO_ROOT/scripts/_render_persona_insights_text.py"

if [ ! -f "$RENDERER" ]; then
  echo "FAIL: renderer missing at $RENDERER" >&2
  exit 2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Pre-v0.9.0 fixture: rows lacking `class` field entirely.
cat > "$TMP/pre-v0.9.0.jsonl" <<'EOF'
{"persona": "ux-flow", "severity": "M", "finding_id": "MF1", "title": "old finding 1"}
{"persona": "scope-discipline", "severity": "H", "finding_id": "MF2", "title": "old finding 2"}
{"persona": "feasibility", "severity": "L", "finding_id": "MF3", "title": "old finding 3"}
EOF

# Post-v0.9.0 fixture: rows with each of the 6 explicit v1 classes.
cat > "$TMP/post-v0.9.0.jsonl" <<'EOF'
{"persona": "security-architect", "severity": "H", "class": "architectural", "finding_id": "MF1"}
{"persona": "security-architect", "severity": "H", "class": "security", "finding_id": "MF2"}
{"persona": "scope-discipline", "severity": "M", "class": "contract", "finding_id": "MF3"}
{"persona": "ux-flow", "severity": "L", "class": "documentation", "finding_id": "MF4"}
{"persona": "test-pyramid", "severity": "M", "class": "tests", "finding_id": "MF5"}
{"persona": "scope-discipline", "severity": "L", "class": "scope-cuts", "finding_id": "MF6"}
EOF

# Mixed fixture: half pre-v0.9.0 (no class), half post-v0.9.0 (explicit class).
cat > "$TMP/mixed.jsonl" <<'EOF'
{"persona": "ux-flow", "severity": "M", "finding_id": "MF1", "title": "pre 1"}
{"persona": "scope-discipline", "severity": "H", "finding_id": "MF2", "title": "pre 2"}
{"persona": "security-architect", "severity": "H", "class": "architectural", "finding_id": "MF3"}
{"persona": "test-pyramid", "severity": "M", "class": "tests", "finding_id": "MF4"}
EOF

# Empty-class and null-class edge cases.
cat > "$TMP/edge.jsonl" <<'EOF'
{"persona": "ux-flow", "class": "", "finding_id": "EF1"}
{"persona": "ux-flow", "class": null, "finding_id": "EF2"}
{"persona": "ux-flow", "class": "architectural", "finding_id": "EF3"}
EOF

# Python harness: import renderer, exercise back-fill helpers on each
# fixture, assert structural invariants. Stdlib only.
python3 - "$RENDERER" "$TMP" <<'PY'
import json
import sys
import importlib.util
from pathlib import Path

renderer_path = Path(sys.argv[1])
tmp = Path(sys.argv[2])

# Load the renderer as an importable module (its filename starts with
# underscore so a regular import would work too if scripts/ is on path,
# but spec_from_file_location is more portable).
spec = importlib.util.spec_from_file_location("_render_phelp", renderer_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

assert hasattr(mod, "backfill_class"), "missing backfill_class helper"
assert hasattr(mod, "aggregate_survival_by_class"), \
    "missing aggregate_survival_by_class helper"


def load(path):
    rows = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if line:
            rows.append(json.loads(line))
    return rows


# ----- Test 1: pre-v0.9.0 rows back-fill to 'unclassified' -----
pre = load(tmp / "pre-v0.9.0.jsonl")
assert len(pre) == 3, "pre fixture has 3 rows"
for r in pre:
    cls = mod.backfill_class(r)
    assert cls == "unclassified", \
        f"pre-v0.9.0 row should back-fill to unclassified, got {cls!r}"

agg_pre = mod.aggregate_survival_by_class(pre)
assert agg_pre == {}, \
    f"per-class agg of pre-v0.9.0 must be empty (filtered out), got {agg_pre!r}"

# Overall row count is preserved (caller iterates raw rows for totals).
assert len(pre) == 3, "overall count includes pre-v0.9.0 rows"
print("PASS: pre-v0.9.0 rows back-fill to unclassified and are filtered "
      "from per-class agg")

# ----- Test 2: post-v0.9.0 rows produce all 6 explicit classes -----
post = load(tmp / "post-v0.9.0.jsonl")
assert len(post) == 6
for r in post:
    cls = mod.backfill_class(r)
    assert cls == r["class"], f"explicit class should pass through, got {cls!r}"

agg_post = mod.aggregate_survival_by_class(post)
expected = {"architectural", "security", "contract",
            "documentation", "tests", "scope-cuts"}
assert set(agg_post.keys()) == expected, \
    f"post-v0.9.0 agg should cover all 6 v1 classes, got {set(agg_post.keys())!r}"
for cls_name in expected:
    assert len(agg_post[cls_name]) == 1, \
        f"each class should have exactly 1 row, {cls_name} has {len(agg_post[cls_name])}"
print("PASS: post-v0.9.0 rows aggregate cleanly into all 6 v1 classes")

# ----- Test 3: mixed fixture — only post rows survive per-class agg -----
mixed = load(tmp / "mixed.jsonl")
assert len(mixed) == 4
agg_mixed = mod.aggregate_survival_by_class(mixed)
assert set(agg_mixed.keys()) == {"architectural", "tests"}, \
    f"mixed agg should cover only the 2 post-v0.9.0 classes, got {set(agg_mixed.keys())!r}"
total_in_per_class = sum(len(v) for v in agg_mixed.values())
assert total_in_per_class == 2, \
    f"only 2 of 4 mixed rows should appear in per-class agg, got {total_in_per_class}"
# But the 2 pre rows are still present in the raw row list.
assert len(mixed) == 4, "raw row count includes pre rows for overall totals"
print("PASS: mixed fixture — pre rows excluded from per-class, "
      "included in overall")

# ----- Test 4: edge cases (empty string, null) coerce to unclassified -----
edge = load(tmp / "edge.jsonl")
assert len(edge) == 3
classes = [mod.backfill_class(r) for r in edge]
assert classes == ["unclassified", "unclassified", "architectural"], \
    f"edge cases should coerce '' and None to unclassified, got {classes!r}"
agg_edge = mod.aggregate_survival_by_class(edge)
assert set(agg_edge.keys()) == {"architectural"}, \
    f"only the explicit-class row should survive per-class agg, got {set(agg_edge.keys())!r}"
print("PASS: edge cases (empty/null class) coerce to unclassified")

# ----- Test 5: existing render() unchanged for fully-class-tagged input -----
# render() reads persona-rankings.jsonl (aggregated), not findings.jsonl —
# verify the back-fill addition didn't break the existing render path. A
# missing rankings file still produces empty output (silent — fresh-install
# semantics per ux.md spec line 36).
empty_path = tmp / "no-such-file.jsonl"
out = mod.render(empty_path)
assert out == "", \
    f"render() of missing file should produce empty string, got {out!r}"
print("PASS: existing render() behavior unchanged (empty-input contract)")

print("ALL TESTS PASSED")
PY
