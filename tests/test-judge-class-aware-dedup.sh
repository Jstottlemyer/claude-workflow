#!/usr/bin/env bash
##############################################################################
# tests/test-judge-class-aware-dedup.sh
#
# Validates personas/judge.md — Class-Aware Dedup (v0.9.0) section. The Judge
# persona is the synthesis step that merges per-reviewer findings into clusters
# under the per-axis policy framework. This test asserts the file documents:
#
#   1. The verbatim highest-class-wins precedence string.
#   2. The class_inferred coercion behavior (Edge Case 1).
#   3. The reclassification authority (named in prose).
#   4. The class:security ↔ tags:["sev:security"] parity rule.
#   5. The architectural carve-outs (data loss as a representative).
#   6. (Implicit) Tests #1–#5 wired into tests/run-tests.sh.
#
# Bash 3.2 compatible. macOS-friendly (BSD-only flags).
##############################################################################
set -uo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JUDGE="$ENGINE_DIR/personas/judge.md"

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

# Pre-flight: file exists
if [ ! -f "$JUDGE" ]; then
  note_fail "missing file: $JUDGE"
  echo ""
  echo "Results: $PASS passed, $FAIL failed"
  exit 1
fi

# 1. Verbatim precedence string. _policy_json.py may cross-validate against
#    this exact ordering as a constant in code; do not loosen this assertion.
PRECEDENCE="architectural > security > unclassified > contract > tests > documentation > scope-cuts"
if grep -qF "$PRECEDENCE" "$JUDGE"; then
  note_pass "verbatim precedence string present"
else
  note_fail "precedence string missing or altered (expected: $PRECEDENCE)"
fi

# 2. class_inferred keyword present (coercion behavior documented)
if grep -q "class_inferred" "$JUDGE"; then
  note_pass "class_inferred keyword present"
else
  note_fail "class_inferred keyword missing — Edge Case 1 coercion not documented"
fi

# 3. reclassification keyword present (authority is named)
if grep -qi "reclassification" "$JUDGE"; then
  note_pass "reclassification authority documented"
else
  note_fail "reclassification keyword missing — upgrade authority not named"
fi

# 4. sev:security parity rule documented
if grep -q "sev:security" "$JUDGE"; then
  note_pass "sev:security parity rule documented"
else
  note_fail "sev:security keyword missing — class↔tag parity rule not documented"
fi

# 5. Architectural carve-outs listed (data loss is the representative trigger)
if grep -q "data loss" "$JUDGE"; then
  note_pass "architectural carve-outs listed (data loss present)"
else
  note_fail "architectural carve-outs missing — 'data loss' trigger not found"
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
