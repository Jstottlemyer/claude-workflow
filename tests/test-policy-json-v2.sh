#!/usr/bin/env bash
##############################################################################
# tests/test-policy-json-v2.sh
#
# Tests for the v2-schema additions to scripts/autorun/_policy_json.py
# (pipeline-gate-permissiveness Wave 1 Task 1.4):
#   - "followups" added to KNOWN_SCHEMAS
#   - JSONL row-loop validation for findings + followups
#   - _enforce_class_sev_parity() runtime check (one-way upgrade direction)
#
# Bash 3.2 compatible. No `${arr[-1]}` (per feedback_negative_array_subscript_bash32).
# Quoted paths everywhere.
##############################################################################
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PJ="$REPO_ROOT/scripts/autorun/_policy_json.py"
FIX="$REPO_ROOT/tests/fixtures/permissiveness"

PASS=0
FAIL=0
FAILED=()

ok()    { PASS=$(( PASS + 1 )); printf "  PASS %s\n" "$1"; }
fail()  { FAIL=$(( FAIL + 1 )); FAILED+=("$1"); printf "  FAIL %s — %s\n" "$1" "$2"; }
case_() { printf "\n--- %s\n" "$1"; }

# --------------------------------------------------------------------------
# 1. v2 check-verdict valid → exit 0
# --------------------------------------------------------------------------

case_ "v2 check-verdict round-trip"

test_v2_verdict_valid() {
  out="$(python3 "$PJ" validate "$FIX/v2-verdict-valid.json" check-verdict 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ]; then ok test_v2_verdict_valid
  else fail test_v2_verdict_valid "rc=$rc out=$out"; fi
}

test_v2_verdict_missing_iteration() {
  out="$(python3 "$PJ" validate "$FIX/v2-verdict-missing-iteration.json" check-verdict 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then ok test_v2_verdict_missing_iteration
  else fail test_v2_verdict_missing_iteration "rc=$rc out=$out (expected non-zero)"; fi
}

test_v2_verdict_valid
test_v2_verdict_missing_iteration

# --------------------------------------------------------------------------
# 2. v2 findings.jsonl validation
# --------------------------------------------------------------------------

case_ "v2 findings.jsonl row-loop validation"

test_v2_finding_valid() {
  out="$(python3 "$PJ" validate "$FIX/v2-finding-valid.jsonl" findings 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ]; then ok test_v2_finding_valid
  else fail test_v2_finding_valid "rc=$rc out=$out"; fi
}

test_v2_finding_missing_class() {
  out="$(python3 "$PJ" validate "$FIX/v2-finding-missing-class.jsonl" findings 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then ok test_v2_finding_missing_class
  else fail test_v2_finding_missing_class "rc=$rc (expected non-zero)"; fi
}

test_v2_finding_valid
test_v2_finding_missing_class

# --------------------------------------------------------------------------
# 3. v1 followups.jsonl validation (followups added to KNOWN_SCHEMAS)
# --------------------------------------------------------------------------

case_ "followups schema (KNOWN_SCHEMAS membership + class enum)"

test_followup_valid() {
  out="$(python3 "$PJ" validate "$FIX/v1-followup-valid.jsonl" followups 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ]; then ok test_followup_valid
  else fail test_followup_valid "rc=$rc out=$out"; fi
}

test_followup_architectural_rejected() {
  # Per followups.schema.json class enum: only contract/documentation/tests/scope-cuts allowed.
  # An architectural row in followups must fail validation.
  out="$(python3 "$PJ" validate "$FIX/v1-followup-architectural-rejected.jsonl" followups 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then ok test_followup_architectural_rejected
  else fail test_followup_architectural_rejected "rc=$rc (expected non-zero)"; fi
}

test_followup_valid
test_followup_architectural_rejected

# --------------------------------------------------------------------------
# 4. _enforce_class_sev_parity runtime check (one-way upgrade)
# --------------------------------------------------------------------------

case_ "class:security <-> sev:security parity (A28)"

test_parity_class_security_without_tag() {
  # class:security but tags omitted — expect repair-and-continue (rc=0) AND
  # stderr "parity-repair" line ("added missing sev:security tag").
  out="$(python3 "$PJ" validate "$FIX/v2-finding-class-security-without-tag.jsonl" findings 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ] && \
     printf '%s' "$out" | grep -q "parity-repair" && \
     printf '%s' "$out" | grep -q "added missing sev:security tag"; then
    ok test_parity_class_security_without_tag
  else
    fail test_parity_class_security_without_tag "rc=$rc out=$out"
  fi
}

test_parity_sevsecurity_without_class() {
  # tags:[sev:security] but class:contract — expect repair-and-continue (rc=0)
  # AND stderr contains "upgraded class".
  out="$(python3 "$PJ" validate "$FIX/v2-finding-sevsecurity-without-class.jsonl" findings 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "upgraded class"; then
    ok test_parity_sevsecurity_without_class
  else
    fail test_parity_sevsecurity_without_class "rc=$rc out=$out"
  fi
}

test_parity_class_security_without_tag
test_parity_sevsecurity_without_class

# --------------------------------------------------------------------------
# 5. AST audit — re-run the D34 ban-list audit on the modified script.
#     Hard constraint per Task 1.4: parity function must pass the audit.
# --------------------------------------------------------------------------

case_ "AST audit (D34 ban list, post-modification)"

test_ast_audit_after_v2() {
  out="$(python3 "$REPO_ROOT/tests/_policy_json_ast_audit.py" "$PJ" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ]; then ok test_ast_audit_after_v2
  else fail test_ast_audit_after_v2 "rc=$rc out=$out"; fi
}

test_ast_audit_after_v2

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------

echo ""
echo "=========================================="
echo "test-policy-json-v2.sh: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed cases:"
  for c in "${FAILED[@]}"; do
    echo "  - $c"
  done
  exit 1
fi
exit 0
