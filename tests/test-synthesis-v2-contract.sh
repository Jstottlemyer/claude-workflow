#!/usr/bin/env bash
##############################################################################
# tests/test-synthesis-v2-contract.sh
#
# Validates personas/synthesis.md carries the v0.9.0 (check-verdict@2.0)
# contract additions from W2.4 of pipeline-gate-permissiveness.
#
# Asserts (grep-only; bash 3.2 compatible):
#   1. First-line contract documented: `OVERALL_VERDICT:` mentioned.
#   2. Verdict version named: `check-verdict@2.0`.
#   3. Lock acquisition via `_followups_lock` documented.
#   4. Lifecycle policy named: `regenerate-active`.
#   5. Cross-gate scoping documented: `source_gate == current_gate`.
#   6. Iteration counter source-of-truth named: `.iteration-state.json`.
#   7. Audit trail file named: `.force-permissive-log`.
##############################################################################
set -uo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SYNTH="$ENGINE_DIR/personas/synthesis.md"

PASS=0
FAIL=0
FAILED=()

note_pass() {
  PASS=$(( PASS + 1 ))
  echo "  PASS — $1"
}

note_fail() {
  FAIL=$(( FAIL + 1 ))
  FAILED+=("$1")
  echo "  FAIL — $1"
}

if [ ! -f "$SYNTH" ]; then
  echo "  FAIL — missing file: $SYNTH"
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

# 1. First-line verdict contract
if grep -q "OVERALL_VERDICT:" "$SYNTH"; then
  note_pass "first-line contract present (OVERALL_VERDICT:)"
else
  note_fail "missing first-line contract token: OVERALL_VERDICT:"
fi

# 2. Verdict prompt-version
if grep -q "check-verdict@2.0" "$SYNTH"; then
  note_pass "verdict prompt version named (check-verdict@2.0)"
else
  note_fail "missing verdict prompt version: check-verdict@2.0"
fi

# 3. Lock helper named
if grep -q "_followups_lock" "$SYNTH"; then
  note_pass "lock acquisition documented (_followups_lock)"
else
  note_fail "missing lock helper reference: _followups_lock"
fi

# 4. Lifecycle policy name
if grep -q "regenerate-active" "$SYNTH"; then
  note_pass "lifecycle policy named (regenerate-active)"
else
  note_fail "missing lifecycle policy: regenerate-active"
fi

# 5. Cross-gate scoping
if grep -q "source_gate == current_gate" "$SYNTH"; then
  note_pass "cross-gate scoping documented (source_gate == current_gate)"
else
  note_fail "missing cross-gate scoping: source_gate == current_gate"
fi

# 6. Iteration counter source
if grep -q "\.iteration-state\.json" "$SYNTH"; then
  note_pass "iteration counter source-of-truth named (.iteration-state.json)"
else
  note_fail "missing iteration counter sidecar: .iteration-state.json"
fi

# 7. Force-permissive audit trail
if grep -q "\.force-permissive-log" "$SYNTH"; then
  note_pass "audit trail file named (.force-permissive-log)"
else
  note_fail "missing audit trail file: .force-permissive-log"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed:"
  for f in "${FAILED[@]}"; do
    echo "  - $f"
  done
  exit 1
fi
exit 0
