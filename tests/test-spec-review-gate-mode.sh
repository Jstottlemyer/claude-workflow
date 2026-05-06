#!/usr/bin/env bash
# test-spec-review-gate-mode.sh
#
# Smoke test for commands/spec-review.md Phase 0c (W3.5 deliverable).
# Verifies the gate-mode preamble references the canonical helpers + truth-table
# file rather than duplicating the truth table inline.
#
# Bash 3.2 compatible (macOS default). No bashisms past 3.2.

set -e
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CMD_FILE="$REPO_ROOT/commands/spec-review.md"

PASS=0
FAIL=0

assert_grep() {
  local label="$1"
  local pattern="$2"
  local file="$3"
  if grep -qF -e "$pattern" "$file"; then
    echo "  PASS  $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL  $label"
    echo "        pattern not found: $pattern"
    FAIL=$((FAIL + 1))
  fi
}

echo "test-spec-review-gate-mode.sh"
echo "  cmd: $CMD_FILE"

if [ ! -f "$CMD_FILE" ]; then
  echo "  FAIL  commands/spec-review.md does not exist at $CMD_FILE"
  exit 1
fi
echo "  PASS  commands/spec-review.md exists"
PASS=$((PASS + 1))

# Test 1: Phase 0c heading present.
assert_grep \
  "Phase 0c heading present" \
  "Phase 0c: Gate Mode Resolution" \
  "$CMD_FILE"

# Test 2: sources the gate helpers script.
assert_grep \
  "sources scripts/_gate_helpers.sh" \
  "_gate_helpers.sh" \
  "$CMD_FILE"

# Test 3: invokes gate_mode_resolve.
assert_grep \
  "calls gate_mode_resolve" \
  "gate_mode_resolve" \
  "$CMD_FILE"

# Test 4: invokes gate_max_recycles_clamp.
assert_grep \
  "calls gate_max_recycles_clamp" \
  "gate_max_recycles_clamp" \
  "$CMD_FILE"

# Test 5: references commands/_gate-mode.md (single source of truth — does NOT
# duplicate the 24-cell table inline).
assert_grep \
  "references commands/_gate-mode.md" \
  "commands/_gate-mode.md" \
  "$CMD_FILE"

# Test 6: --force-permissive CLI flag handling appears.
assert_grep \
  "handles --force-permissive flag" \
  "--force-permissive" \
  "$CMD_FILE"

# Test 7: per-spec sentinel path appears.
assert_grep \
  "references per-spec .gate-mode-warned sentinel" \
  ".gate-mode-warned" \
  "$CMD_FILE"

echo ""
echo "  total: $((PASS + FAIL))    pass: $PASS    fail: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
