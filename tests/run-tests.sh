#!/usr/bin/env bash
##############################################################################
# tests/run-tests.sh
#
# Top-level test runner for MonsterFlow. Runs every test script under tests/,
# captures their pass/fail, and reports a summary. CI-friendly: exits non-zero
# if any test failed.
#
# Usage:
#   bash tests/run-tests.sh [test-name]
#
# Without args, runs all tests. With a name (e.g. "hooks"), runs just
# tests/test-hooks.sh.
##############################################################################
set -uo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TESTS_DIR="$ENGINE_DIR/tests"
ONLY="${1:-}"

# Tests in execution order. Cheapest first so failures surface fast.
TESTS=(
  test-hooks.sh
  test-agents.sh
  test-skills.sh
  test-bump-version.sh
  autorun-dryrun.sh
)

PASS=0
FAIL=0
FAILED_TESTS=()

for t in "${TESTS[@]}"; do
  # Filter if user passed a name fragment
  if [ -n "$ONLY" ] && [[ "$t" != *"$ONLY"* ]]; then
    continue
  fi

  if [ ! -x "$TESTS_DIR/$t" ]; then
    echo "✗ $t — not executable or missing"
    FAIL=$(( FAIL + 1 ))
    FAILED_TESTS+=("$t")
    continue
  fi

  echo "=== $t ==="
  TEST_EXIT=0
  bash "$TESTS_DIR/$t" || TEST_EXIT=$?

  if [ "$TEST_EXIT" -eq 0 ]; then
    echo "→ $t PASSED"
    PASS=$(( PASS + 1 ))
  else
    echo "→ $t FAILED (exit $TEST_EXIT)"
    FAIL=$(( FAIL + 1 ))
    FAILED_TESTS+=("$t")
  fi
  echo ""
done

echo "=========================================="
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed:"
  for t in "${FAILED_TESTS[@]}"; do
    echo "  - $t"
  done
  exit 1
fi
exit 0
