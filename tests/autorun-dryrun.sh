#!/usr/bin/env bash
##############################################################################
# tests/autorun-dryrun.sh
#
# Smoke test for the autorun pipeline in DRY_RUN mode.
# Stages a fixture spec, runs the pipeline against an isolated TMPDIR queue,
# asserts every expected artifact landed, then cleans up.
#
# Exit codes:
#   0 — all assertions passed
#   1 — at least one assertion failed
#   2 — setup failure (missing fixture, can't create temp dir, etc.)
##############################################################################
set -uo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="$ENGINE_DIR/tests/fixtures/autorun-dryrun/sample.spec.md"

if [ ! -f "$FIXTURE" ]; then
  echo "✗ setup: fixture not found at $FIXTURE" >&2
  exit 2
fi

# Isolated project dir so we don't pollute the engine's queue/.
PROJECT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/autorun-dryrun-XXXXXX")"
trap 'rm -rf "$PROJECT_DIR"' EXIT

# Initialize a real git repo so run.sh's branch operations work.
git -C "$PROJECT_DIR" init -q -b main
git -C "$PROJECT_DIR" config user.email "dryrun@local"
git -C "$PROJECT_DIR" config user.name "Dry Run"
echo "# dryrun" > "$PROJECT_DIR/README.md"
git -C "$PROJECT_DIR" add README.md
git -C "$PROJECT_DIR" commit -q -m "init"

mkdir -p "$PROJECT_DIR/queue"
cp "$FIXTURE" "$PROJECT_DIR/queue/sample.spec.md"

echo "[dryrun] running autorun in $PROJECT_DIR"

# Run the pipeline. AUTORUN_DRY_RUN=1 makes every stage write stub artifacts.
# We disable the codex review step's gh push by NOT having a remote configured.
START="$(date +%s)"
RUN_LOG="$(mktemp "${TMPDIR:-/tmp}/autorun-dryrun-log-XXXXXX.txt")"
export ENGINE_DIR PROJECT_DIR
RUN_EXIT=0
AUTORUN_DRY_RUN=1 bash "$ENGINE_DIR/scripts/autorun/run.sh" >"$RUN_LOG" 2>&1 || RUN_EXIT=$?
END="$(date +%s)"
ELAPSED=$(( END - START ))

# In DRY_RUN, the build/verify/notify/codex steps stub out — pipeline should
# proceed through review-findings, risk-findings, plan, check, build (stub
# wave), verify (stub COMPLIANT), and PR creation will fail because there's
# no remote. PR-creation failure is expected in dry-run; we just want to
# confirm the pre-PR artifacts all landed.

ART="$PROJECT_DIR/queue/sample"
PASS=0
FAIL=0

assert_file() {
  local path="$1" label="${2:-$1}"
  if [ -f "$path" ]; then
    echo "✓ $label"
    PASS=$(( PASS + 1 ))
  else
    echo "✗ missing: $label"
    FAIL=$(( FAIL + 1 ))
  fi
}

assert_grep() {
  local path="$1" pattern="$2" label="$3"
  if [ -f "$path" ] && grep -iq "$pattern" "$path" 2>/dev/null; then
    echo "✓ $label"
    PASS=$(( PASS + 1 ))
  else
    echo "✗ $label (pattern '$pattern' not found in $path)"
    FAIL=$(( FAIL + 1 ))
  fi
}

echo ""
echo "=== Asserting artifacts under $ART ==="
assert_file "$ART/review-findings.md"
assert_file "$ART/risk-findings.md"
assert_file "$ART/plan.md"
assert_file "$ART/check.md"
assert_file "$ART/build-log.md"
assert_file "$ART/verify-gaps.md"
assert_file "$ART/pre-build-sha.txt"
assert_file "$ART/state.json"
assert_grep "$ART/verify-gaps.md" "VERDICT: COMPLIANT" "verify-gaps.md contains VERDICT: COMPLIANT"

# state.json should be valid JSON
if [ -f "$ART/state.json" ]; then
  if python3 -c "import json; json.load(open('$ART/state.json'))" 2>/dev/null; then
    echo "✓ state.json is valid JSON"
    PASS=$(( PASS + 1 ))
  else
    echo "✗ state.json is not valid JSON"
    FAIL=$(( FAIL + 1 ))
  fi
fi

echo ""
echo "=== Summary ==="
echo "passed: $PASS"
echo "failed: $FAIL"
echo "elapsed: ${ELAPSED}s"
echo "run.sh exit code: $RUN_EXIT (PR creation failure expected in dry-run)"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "=== Run log (last 50 lines) ==="
  tail -50 "$RUN_LOG"
  rm -f "$RUN_LOG"
  echo ""
  echo "FAIL — $FAIL assertion(s) failed"
  exit 1
fi

rm -f "$RUN_LOG"
echo ""
echo "PASS — autorun dry-run complete in ${ELAPSED}s"
exit 0
