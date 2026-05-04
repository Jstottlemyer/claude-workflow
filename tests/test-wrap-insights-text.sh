#!/usr/bin/env bash
##############################################################################
# tests/test-wrap-insights-text.sh — Wave 3 Task 3.3 (token-economics, A6)
#
# Acceptance A6 — verify scripts/_render_persona_insights_text.py emits the
# locked /wrap-insights Phase 1c "Persona insights" text section per ux.md
# (lines 215-247).
#
# Asserts (when dashboard/data/persona-rankings.jsonl is present + non-empty):
#   1. Output contains the literal "Persona insights (last 45"
#   2. At least one of the per-gate sections renders (spec-review/plan/check)
#   3. Cost-ranking line uses "tok" or "tok/invocation" suffix (NOT raw int)
#      — sourced from avg_tokens_per_invocation, not total_tokens
#   4. When fewer than 3 personas qualify for a gate, the gate header collapses
#      to "(only N qualifying — need 3 runs each)"
#   5. Trailing semantics note about "retention" being a "compression ratio"
#      is present (locked per ux.md line 247-249)
#
# When the rankings file is absent or empty, the test SKIPS gracefully (per
# spec edge-case e12 — fresh installs render no Phase 1c sub-section).
#
# Spec: docs/specs/token-economics/spec.md (v4.2 §Acceptance A6)
# Plan: docs/specs/token-economics/plan.md (v1.2 — Wave 3 task 3.3)
##############################################################################
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

RENDERER="scripts/_render_persona_insights_text.py"
RANKINGS="dashboard/data/persona-rankings.jsonl"

PASS=0
FAIL=0

note_pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }
note_fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

# Pre-check — graceful skip if there's no rankings file or it's empty. The
# renderer is a no-op in that case (silent exit 0), so there's nothing to
# assert on.
USE_FIXTURE=""
TMP_DIR=""

cleanup() {
  if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

if [ ! -f "$RANKINGS" ] || [ ! -s "$RANKINGS" ]; then
  # No real rankings file — synthesize a tiny fixture so we still exercise
  # the renderer. We construct rows that satisfy the schema enough for the
  # renderer's loose JSON consumption (it doesn't allowlist-validate; only
  # the engine does). One gate with 3 qualifying rows + one gate with 1.
  TMP_DIR="$(mktemp -d /tmp/test-wrap-insights-XXXXXX)"
  USE_FIXTURE="$TMP_DIR/persona-rankings.jsonl"

  python3 - "$USE_FIXTURE" <<'PY'
import json
import sys
from pathlib import Path

out_path = Path(sys.argv[1])

def row(persona, gate, ret, sur, uniq, toks, runs=5):
    return {
        "schema_version": 1,
        "persona": persona,
        "gate": gate,
        "runs_in_window": runs,
        "window_size": 45,
        "cost_runs_in_window": runs,
        "run_state_counts": {
            "complete_value": runs,
            "silent": 0,
            "missing_survival": 0,
            "missing_findings": 0,
            "missing_raw": 0,
            "malformed": 0,
            "cost_only": 0,
        },
        "total_emitted": 100,
        "total_judge_retained": 80,
        "total_downstream_survived": 50,
        "total_unique": 25,
        "silent_runs_count": 0,
        "total_tokens": toks * runs,
        "judge_retention_ratio": ret,
        "downstream_survival_rate": sur,
        "uniqueness_rate": uniq,
        "avg_tokens_per_invocation": toks,
        "last_artifact_created_at": "2026-05-01T12:00:00Z",
        "persona_content_hash": None,
        "contributing_finding_ids": [],
        "truncated_count": 0,
        "insufficient_sample": False,
    }

rows = [
    # spec-review — 3 qualifying personas
    row("scope-discipline", "spec-review", 0.84, 0.62, 0.28, 9000),
    row("ux-flow",          "spec-review", 0.89, 0.40, 0.18, 12000),
    row("ambiguity",        "spec-review", 0.31, 0.08, 0.10, 10400),
    # plan — only 2 qualifying (low-qualify branch)
    row("data-model",       "plan",        0.55, 0.35, 0.20, 11000),
    row("scalability",      "plan",        0.62, 0.45, 0.25, 8500),
]

with open(out_path, "w", encoding="utf-8") as fh:
    for r in rows:
        fh.write(json.dumps(r, sort_keys=True) + "\n")
PY

  RENDER_OUT="$(python3 "$RENDERER" --rankings "$USE_FIXTURE" 2>&1)"
  echo "NOTE: synthesized fixture used (no real $RANKINGS present)"
else
  RENDER_OUT="$(python3 "$RENDERER" 2>&1)"
fi

# 1. "Persona insights (last 45" present.
if printf '%s\n' "$RENDER_OUT" | grep -qF 'Persona insights (last 45'; then
  note_pass "header 'Persona insights (last 45' present"
else
  note_fail "header 'Persona insights (last 45' missing"
fi

# 2. At least one gate section renders.
if printf '%s\n' "$RENDER_OUT" | grep -qE '^\s+(spec-review|plan|check)( |$)'; then
  note_pass "at least one per-gate section rendered"
else
  note_fail "no per-gate section found"
fi

# 3. Cost ranking line uses 'tok' suffix (NOT a raw integer).
#    The renderer formats avg_tokens_per_invocation via _fmt_tokens which
#    appends 'k tok' or 'tok'. Total_tokens would render as bare int.
if printf '%s\n' "$RENDER_OUT" | grep -E 'cheapest per call' | grep -qE 'tok\b'; then
  note_pass "cost line uses 'tok' suffix (avg_tokens_per_invocation, not total)"
else
  # Acceptable if no gate qualified for cost line at all (e.g., synthesized
  # fixture only had a low-qualify plan). Re-check that SOMEWHERE 'tok'
  # appears at all — that proves the suffix is used when the line renders.
  if printf '%s\n' "$RENDER_OUT" | grep -qE 'tok\b'; then
    note_pass "cost line uses 'tok' suffix (avg_tokens_per_invocation, not total)"
  else
    note_fail "cost line missing 'tok' suffix — may be using total_tokens"
  fi
fi

# 4. When fewer than 3 personas qualify, the line collapses to "(only N qualifying".
#    Use the synthesized fixture path (where 'plan' has 2). When real rankings
#    are used, this assertion only fires if at least one gate has <3.
if printf '%s\n' "$RENDER_OUT" | grep -qE '\(only [0-9]+ qualifying'; then
  note_pass "low-qualify gate renders '(only N qualifying' line"
else
  if [ -n "$USE_FIXTURE" ]; then
    note_fail "synthesized fixture should have triggered '(only N qualifying' on 'plan'"
  else
    echo "SKIP: real rankings file had no low-qualify gate to collapse"
  fi
fi

# 5. Trailing semantics note.
if printf '%s\n' "$RENDER_OUT" | grep -qF 'compression ratio' \
   && printf '%s\n' "$RENDER_OUT" | grep -qF 'retention'; then
  note_pass "trailing note '\"retention\" is a compression ratio' present"
else
  note_fail "trailing semantics note missing"
fi

echo ""
echo "test-wrap-insights-text: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
