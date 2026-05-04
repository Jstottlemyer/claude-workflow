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
  # token-economics tests (cheapest first per code-review rec)
  test-no-raw-print.sh
  test-phase-0-artifact.sh
  test-allowlist.sh
  test-allowlist-inverted.sh        # M8: must exit non-zero (handled below)
  test-path-validation.sh
  test-finding-id-salt.sh
  test-scan-confirmation.sh
  test-wrap-insights-text.sh
  test-dashboard-render.sh
  test-compute-persona-value.sh
  test-build-final.sh
  autorun-dryrun.sh
  # install-rewrite W4 — supply-chain gate first (cheap), then full install harness
  test-config-content.sh
  test-install.sh
)

# Tests whose passing condition is exit non-zero (M8 inverted-assertion contract).
INVERTED_TESTS=(
  test-allowlist-inverted.sh
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

  # Determine if this is an inverted test (passes when exit is non-zero per M8)
  IS_INVERTED=0
  for inv in "${INVERTED_TESTS[@]}"; do
    if [ "$t" = "$inv" ]; then IS_INVERTED=1; break; fi
  done

  echo "=== $t ==="
  TEST_EXIT=0
  bash "$TESTS_DIR/$t" || TEST_EXIT=$?

  if [ "$IS_INVERTED" -eq 1 ]; then
    # Inverted contract: pass = non-zero exit
    if [ "$TEST_EXIT" -ne 0 ]; then
      echo "→ $t PASSED (inverted: exit $TEST_EXIT as designed)"
      PASS=$(( PASS + 1 ))
    else
      echo "→ $t FAILED (inverted: should have exited non-zero, got 0)"
      FAIL=$(( FAIL + 1 ))
      FAILED_TESTS+=("$t")
    fi
  else
    if [ "$TEST_EXIT" -eq 0 ]; then
      echo "→ $t PASSED"
      PASS=$(( PASS + 1 ))
    else
      echo "→ $t FAILED (exit $TEST_EXIT)"
      FAIL=$(( FAIL + 1 ))
      FAILED_TESTS+=("$t")
    fi
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
