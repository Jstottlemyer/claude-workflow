#!/usr/bin/env bash
##############################################################################
# tests/test-spec-frontmatter-gate-fields.sh
#
# Validates that commands/spec.md's Phase 3 frontmatter schema includes the
# new pipeline-gate-permissiveness knobs: gate_mode and gate_max_recycles.
#
# Bash 3.2 compatible. Pure grep assertions on the file contents.
##############################################################################
set -uo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SPEC_CMD="$ENGINE_DIR/commands/spec.md"

PASS=0
FAIL=0

assert_grep() {
  # $1 = pattern (fixed string), $2 = description
  local pattern="$1"
  local desc="$2"
  if grep -F -q -- "$pattern" "$SPEC_CMD"; then
    echo "  ok — $desc"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL — $desc (missing: $pattern)"
    FAIL=$(( FAIL + 1 ))
  fi
}

assert_grep_ext() {
  # extended regex variant for clamp range alternation
  local pattern="$1"
  local desc="$2"
  if grep -E -q -- "$pattern" "$SPEC_CMD"; then
    echo "  ok — $desc"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL — $desc (missing pattern: $pattern)"
    FAIL=$(( FAIL + 1 ))
  fi
}

if [ ! -f "$SPEC_CMD" ]; then
  echo "✗ commands/spec.md not found at $SPEC_CMD"
  exit 1
fi

echo "test-spec-frontmatter-gate-fields"
echo "  target: $SPEC_CMD"

# 1. gate_mode field present
assert_grep "gate_mode" "Phase 3 frontmatter declares gate_mode"

# 2. gate_max_recycles field present
assert_grep "gate_max_recycles" "Phase 3 frontmatter declares gate_max_recycles"

# 3. References commands/_gate-mode.md (CLI flag truth table)
assert_grep "commands/_gate-mode.md" "Phase 3 references commands/_gate-mode.md"

# 4. Enum values for gate_mode
assert_grep "permissive" "gate_mode enum value 'permissive' documented"
assert_grep "strict" "gate_mode enum value 'strict' documented"

# 5. Clamp range for gate_max_recycles — accept [1, 5] or 1-5
assert_grep_ext "\[1, 5\]|1-5" "gate_max_recycles clamp range [1, 5] or 1-5 documented"

echo ""
echo "  passed: $PASS"
echo "  failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
