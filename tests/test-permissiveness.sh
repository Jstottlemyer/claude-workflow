#!/usr/bin/env bash
##############################################################################
# tests/test-permissiveness.sh
#
# A12 mode x class matrix — pipeline-gate-permissiveness Wave 5 Tasks 5.1+5.2.
#
# Pure deterministic schema validation: each (mode x class) fixture is fed
# through scripts/autorun/_policy_json.py validate, asserting v2 conformance
# AND class_breakdown shape consistency (target class count == 1; all others
# == 0). NO `claude -p` calls, NO LLM round-trips. Total budget < 15s.
#
# Bash 3.2 compatible. No `${arr[-1]}`, no `mapfile`, no `&>`. Uses `case` for
# class-name -> verdict-expectation mapping.
#
# AC coverage map (across the test suite — this file is the matrix; cross-refs
# point at the per-AC tests that ship in adjacent files):
#   - A1, A2, A3, A4, A5: this file (12-fixture matrix; verdict-shape asserts)
#   - A7: tests/test-build-followups-consumer.sh
#   - A8b: tests/test-autorun-policy.sh
#   - A9, A14, A16: this file (structural; LLM-driven branches manual)
#   - A10, A17: tests/test-policy-json-v2.sh
#   - A11, A11b, A13: tests/test-gate-helpers.sh
#   - A14b: tests/test-render-followups.sh
#   - A14c: tests/fixtures/permissiveness/lock-acquire-roundtrip.sh
#   - A14d: tests/test-build-mark-addressed.sh
#   - A15a: tests/test-docs-index-three-tier-verdict.sh
#           + tests/test-changelog-v0.9.0-entry.sh
#   - A18-A28: see /plan task tests
##############################################################################
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PJ="$REPO_ROOT/scripts/autorun/_policy_json.py"
MATRIX="$REPO_ROOT/tests/fixtures/permissiveness/matrix"

PASS=0
FAIL=0
FAILED=""

ok()    { PASS=$(( PASS + 1 )); printf "  PASS %s\n" "$1"; }
fail()  { FAIL=$(( FAIL + 1 )); FAILED="$FAILED $1"; printf "  FAIL %s -- %s\n" "$1" "$2"; }
case_() { printf "\n--- %s\n" "$1"; }

# --------------------------------------------------------------------------
# Helper: jq-free JSON field reader using python3 stdlib.
# Usage: get_field <file> <key> [<subkey>]
# --------------------------------------------------------------------------
get_field() {
  python3 -c "
import json,sys
with open(sys.argv[1]) as f:
    d=json.load(f)
keys=sys.argv[2:]
v=d
for k in keys:
    v=v[k]
print(v if not isinstance(v,bool) else ('true' if v else 'false'))
" "$@"
}

# --------------------------------------------------------------------------
# Helper: expected verdict for a given class.
# architectural / security / unclassified always block (NO_GO regardless of
# mode). The 4 mode-flippable classes (contract / documentation / tests /
# scope-cuts) warn-route in permissive (GO_WITH_FIXES) and block in strict
# (NO_GO).
# --------------------------------------------------------------------------
expected_verdict() {
  cls="$1"
  mode="$2"
  case "$cls" in
    architectural|security|unclassified)
      echo "NO_GO"
      ;;
    contract|documentation|tests|scope-cuts)
      if [ "$mode" = "permissive" ]; then
        echo "GO_WITH_FIXES"
      else
        echo "NO_GO"
      fi
      ;;
    *)
      echo "UNKNOWN"
      ;;
  esac
}

# --------------------------------------------------------------------------
# Validate one fixture: schema-validate, then assert class_breakdown shape
# (target class == 1, others == 0) AND verdict matches mode/class policy.
# --------------------------------------------------------------------------
validate_fixture() {
  fixture="$1"
  mode="$2"
  cls="$3"
  base="$(basename "$fixture" .json)"

  # 1) schema validation
  out="$(python3 "$PJ" validate "$fixture" check-verdict 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "schema:$base" "rc=$rc out=$out"
    return
  fi
  ok "schema:$base"

  # 2) class_breakdown shape: target class == 1; all other 6 classes == 0
  for k in architectural security contract documentation tests scope-cuts unclassified; do
    actual="$(get_field "$fixture" class_breakdown "$k" 2>/dev/null)"
    if [ "$k" = "$cls" ]; then
      expected=1
    else
      expected=0
    fi
    if [ "$actual" != "$expected" ]; then
      fail "shape:$base:$k" "expected=$expected actual=$actual"
      return
    fi
  done
  ok "shape:$base"

  # 3) verdict matches the mode-x-class policy table
  actual_verdict="$(get_field "$fixture" verdict 2>/dev/null)"
  exp_verdict="$(expected_verdict "$cls" "$mode")"
  if [ "$actual_verdict" != "$exp_verdict" ]; then
    fail "verdict:$base" "expected=$exp_verdict actual=$actual_verdict"
    return
  fi
  ok "verdict:$base"

  # 4) mode field matches filename
  actual_mode="$(get_field "$fixture" mode 2>/dev/null)"
  if [ "$actual_mode" != "$mode" ]; then
    fail "mode:$base" "expected=$mode actual=$actual_mode"
    return
  fi
  ok "mode:$base"
}

# --------------------------------------------------------------------------
# 12-fixture matrix walk (2 modes x 6 classes).
# Class order matches schema's class_breakdown enum order, minus
# `unclassified` (which is hardcoded-block and does not flip on mode, so it
# is covered by tests/test-policy-json-v2.sh A10 parity tests instead).
# --------------------------------------------------------------------------

case_ "A12 mode x class matrix (12 fixtures)"

MATRIX_COUNT=0
for mode in permissive strict; do
  for cls in architectural security contract documentation tests scope-cuts; do
    fixture="$MATRIX/mode-${mode}-class-${cls}.json"
    if [ ! -f "$fixture" ]; then
      fail "exists:mode-${mode}-class-${cls}" "fixture not found at $fixture"
      continue
    fi
    validate_fixture "$fixture" "$mode" "$cls"
    MATRIX_COUNT=$(( MATRIX_COUNT + 1 ))
  done
done

# --------------------------------------------------------------------------
# Summary-table assertion: 12 fixtures walked, each contributing 4 sub-asserts
# (schema + shape + verdict + mode-field). Total successful sub-asserts on a
# clean run = 12 * 4 = 48. Anything less and at least one fixture failed.
# --------------------------------------------------------------------------

case_ "matrix completeness"

if [ "$MATRIX_COUNT" -eq 12 ]; then
  ok "matrix:12-fixtures-walked"
else
  fail "matrix:12-fixtures-walked" "walked $MATRIX_COUNT, expected 12"
fi

EXPECTED_PASSES=$(( 12 * 4 + 1 ))   # 48 sub-asserts + 1 completeness assert
if [ "$FAIL" -eq 0 ] && [ "$PASS" -eq "$EXPECTED_PASSES" ]; then
  ok "matrix:all-12-fixtures-pass-cleanly"
else
  # Don't fail the run for this — diagnostic only when something else already
  # failed (otherwise it's a count-drift signal worth surfacing).
  if [ "$FAIL" -eq 0 ]; then
    fail "matrix:pass-count" "expected $EXPECTED_PASSES PASSes, got $PASS"
  fi
fi

# --------------------------------------------------------------------------
# Final tally
# --------------------------------------------------------------------------

printf "\n=========================================\n"
printf "test-permissiveness.sh: PASS=%d FAIL=%d\n" "$PASS" "$FAIL"
if [ "$FAIL" -ne 0 ]; then
  printf "FAILED:%s\n" "$FAILED"
  exit 1
fi
exit 0
