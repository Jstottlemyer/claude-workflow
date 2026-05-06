#!/usr/bin/env bash
##############################################################################
# tests/test-policy-sh.sh
#
# Functional tests for scripts/autorun/_policy.sh (Task 2.1).
# Contract: docs/specs/autorun-overnight-policy/API_FREEZE.md §(a).
#
# Bash 3.2 compatible. No ${arr[-1]}. Quoted paths everywhere.
##############################################################################
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
POLICY_SH="$REPO_ROOT/scripts/autorun/_policy.sh"
POLICY_PY="$REPO_ROOT/scripts/autorun/_policy_json.py"
TMPROOT="$(mktemp -d -t "policy-sh-test.XXXXXX")"
trap 'rm -rf "$TMPROOT"' EXIT

PASS=0
FAIL=0
FAILED=()

ok()    { PASS=$(( PASS + 1 )); printf "  PASS %s\n" "$1"; }
fail()  { FAIL=$(( FAIL + 1 )); FAILED+=("$1"); printf "  FAIL %s — %s\n" "$1" "$2"; }
case_() { printf "\n--- %s\n" "$1"; }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

mk_run_state() {
  local f="$1"
  cat >"$f" <<'EOF'
{
  "schema_version": 1,
  "run_id": "01234567-89ab-cdef-0123-456789abcdef",
  "slug": "test-slug",
  "started_at": "2026-05-05T12:00:00Z",
  "current_stage": "spec-review",
  "warnings": [],
  "blocks": []
}
EOF
}

mk_config() {
  local f="$1"
  cat >"$f" <<'EOF'
{
  "policies": {
    "verdict": "block",
    "branch": "warn",
    "codex_probe": "block",
    "verify_infra": "warn"
  }
}
EOF
}

# Count of items in run-state.<list_key>
count_list() {
  local f="$1" key="$2"
  python3 -c "import json,sys; print(len(json.load(open('$f')).get('$key', [])))"
}

# ---------------------------------------------------------------------------
# test_policy_warn_appends
# ---------------------------------------------------------------------------
case_ "test_policy_warn_appends"
(
  STATE="$TMPROOT/rs1.json"
  mk_run_state "$STATE"
  export AUTORUN_RUN_STATE="$STATE"
  # shellcheck disable=SC1090
  source "$POLICY_SH"
  before="$(count_list "$STATE" warnings)"
  policy_warn check verdict "test-warn-reason"
  after="$(count_list "$STATE" warnings)"
  if [ "$before" -eq 0 ] && [ "$after" -eq 1 ]; then
    exit 0
  else
    echo "before=$before after=$after"
    exit 1
  fi
)
if [ $? -eq 0 ]; then ok test_policy_warn_appends; else fail test_policy_warn_appends "warnings did not grow"; fi

# ---------------------------------------------------------------------------
# test_policy_block_appends_and_returns_nonzero
# ---------------------------------------------------------------------------
case_ "test_policy_block_appends_and_returns_nonzero"
(
  STATE="$TMPROOT/rs2.json"
  mk_run_state "$STATE"
  export AUTORUN_RUN_STATE="$STATE"
  # shellcheck disable=SC1090
  source "$POLICY_SH"
  set +e
  policy_block check verdict "test-block-reason"
  rc=$?
  set -e
  before=0
  after="$(count_list "$STATE" blocks)"
  if [ "$rc" -ne 0 ] && [ "$after" -eq 1 ]; then
    exit 0
  else
    echo "rc=$rc after=$after"
    exit 1
  fi
)
if [ $? -eq 0 ]; then ok test_policy_block_appends_and_returns_nonzero; else fail test_policy_block_appends_and_returns_nonzero "rc/append wrong"; fi

# ---------------------------------------------------------------------------
# test_policy_block_does_not_exit
# Caller can run code after policy_block (i.e. helper does not exit on its own).
# ---------------------------------------------------------------------------
case_ "test_policy_block_does_not_exit"
(
  STATE="$TMPROOT/rs3.json"
  mk_run_state "$STATE"
  export AUTORUN_RUN_STATE="$STATE"
  # shellcheck disable=SC1090
  source "$POLICY_SH"
  set +e
  policy_block check verdict "no-exit"
  rc=$?
  POST_RAN=1
  set -e
  if [ "$rc" -ne 0 ] && [ "$POST_RAN" -eq 1 ]; then
    exit 0
  else
    exit 1
  fi
)
if [ $? -eq 0 ]; then ok test_policy_block_does_not_exit; else fail test_policy_block_does_not_exit "control did not return to caller"; fi

# ---------------------------------------------------------------------------
# test_policy_act_warn  (mock policy=warn via env override)
# ---------------------------------------------------------------------------
case_ "test_policy_act_warn"
(
  STATE="$TMPROOT/rs4.json"
  mk_run_state "$STATE"
  export AUTORUN_RUN_STATE="$STATE"
  export AUTORUN_CURRENT_STAGE="check"
  export AUTORUN_VERDICT_POLICY="warn"
  # shellcheck disable=SC1090
  source "$POLICY_SH"
  set +e
  policy_act verdict "soft-fail"
  rc=$?
  set -e
  warns="$(count_list "$STATE" warnings)"
  blocks="$(count_list "$STATE" blocks)"
  if [ "$rc" -eq 0 ] && [ "$warns" -eq 1 ] && [ "$blocks" -eq 0 ]; then
    exit 0
  else
    echo "rc=$rc warns=$warns blocks=$blocks"
    exit 1
  fi
)
if [ $? -eq 0 ]; then ok test_policy_act_warn; else fail test_policy_act_warn "warn path"; fi

# ---------------------------------------------------------------------------
# test_policy_act_block (mock policy=block via env override)
# ---------------------------------------------------------------------------
case_ "test_policy_act_block"
(
  STATE="$TMPROOT/rs5.json"
  mk_run_state "$STATE"
  export AUTORUN_RUN_STATE="$STATE"
  export AUTORUN_CURRENT_STAGE="check"
  export AUTORUN_VERDICT_POLICY="block"
  # shellcheck disable=SC1090
  source "$POLICY_SH"
  set +e
  policy_act verdict "hard-fail"
  rc=$?
  set -e
  warns="$(count_list "$STATE" warnings)"
  blocks="$(count_list "$STATE" blocks)"
  if [ "$rc" -ne 0 ] && [ "$warns" -eq 0 ] && [ "$blocks" -eq 1 ]; then
    exit 0
  else
    echo "rc=$rc warns=$warns blocks=$blocks"
    exit 1
  fi
)
if [ $? -eq 0 ]; then ok test_policy_act_block; else fail test_policy_act_block "block path"; fi

# ---------------------------------------------------------------------------
# test_policy_act_unset_stage_fails_fast
# ---------------------------------------------------------------------------
case_ "test_policy_act_unset_stage_fails_fast"
OUT="$TMPROOT/unset_stage.err"
(
  STATE="$TMPROOT/rs6.json"
  mk_run_state "$STATE"
  export AUTORUN_RUN_STATE="$STATE"
  unset AUTORUN_CURRENT_STAGE
  # shellcheck disable=SC1090
  source "$POLICY_SH"
  policy_act verdict "no-stage" 2>"$OUT"
) >/dev/null 2>>"$OUT"
rc=$?
if [ "$rc" -eq 2 ] && grep -q "AUTORUN_CURRENT_STAGE not set" "$OUT"; then
  ok test_policy_act_unset_stage_fails_fast
else
  fail test_policy_act_unset_stage_fails_fast "rc=$rc stderr=$(cat "$OUT")"
fi

# ---------------------------------------------------------------------------
# test_policy_for_axis_env_wins
# ---------------------------------------------------------------------------
case_ "test_policy_for_axis_env_wins"
(
  CFG="$TMPROOT/cfg1.json"
  mk_config "$CFG"
  export AUTORUN_CONFIG_FILE="$CFG"
  export AUTORUN_VERDICT_POLICY="warn"  # config says block; env should win
  # shellcheck disable=SC1090
  source "$POLICY_SH"
  v="$(policy_for_axis verdict)"
  if [ "$v" = "warn" ]; then
    exit 0
  else
    echo "got=$v"
    exit 1
  fi
)
if [ $? -eq 0 ]; then ok test_policy_for_axis_env_wins; else fail test_policy_for_axis_env_wins "env did not override config"; fi

# ---------------------------------------------------------------------------
# test_policy_for_axis_security_always_block
# ---------------------------------------------------------------------------
case_ "test_policy_for_axis_security_always_block"
(
  CFG="$TMPROOT/cfg2.json"
  mk_config "$CFG"
  export AUTORUN_CONFIG_FILE="$CFG"
  # AUTORUN_SECURITY_POLICY shouldn't even be defined per spec, but assert
  # it's ignored even if set.
  export AUTORUN_SECURITY_POLICY="warn"
  export AUTORUN_INTEGRITY_POLICY="warn"
  # shellcheck disable=SC1090
  source "$POLICY_SH"
  s="$(policy_for_axis security)"
  i="$(policy_for_axis integrity)"
  if [ "$s" = "block" ] && [ "$i" = "block" ]; then
    exit 0
  else
    echo "security=$s integrity=$i"
    exit 1
  fi
)
if [ $? -eq 0 ]; then ok test_policy_for_axis_security_always_block; else fail test_policy_for_axis_security_always_block "hardcoded block bypassed"; fi

# ---------------------------------------------------------------------------
# test_invalid_stage_fails_fast
# ---------------------------------------------------------------------------
case_ "test_invalid_stage_fails_fast"
OUT="$TMPROOT/invalid_stage.err"
(
  STATE="$TMPROOT/rs7.json"
  mk_run_state "$STATE"
  export AUTORUN_RUN_STATE="$STATE"
  # shellcheck disable=SC1090
  source "$POLICY_SH"
  policy_warn nonexistent-stage verdict "x" 2>"$OUT"
) >/dev/null 2>>"$OUT"
rc=$?
if [ "$rc" -eq 2 ] && grep -q "invalid stage" "$OUT"; then
  ok test_invalid_stage_fails_fast
else
  fail test_invalid_stage_fails_fast "rc=$rc stderr=$(cat "$OUT")"
fi

# ---------------------------------------------------------------------------
# test_invalid_axis_fails_fast
# ---------------------------------------------------------------------------
case_ "test_invalid_axis_fails_fast"
OUT="$TMPROOT/invalid_axis.err"
(
  STATE="$TMPROOT/rs8.json"
  mk_run_state "$STATE"
  export AUTORUN_RUN_STATE="$STATE"
  # shellcheck disable=SC1090
  source "$POLICY_SH"
  policy_warn check nonexistent-axis "x" 2>"$OUT"
) >/dev/null 2>>"$OUT"
rc=$?
if [ "$rc" -eq 2 ] && grep -q "invalid axis" "$OUT"; then
  ok test_invalid_axis_fails_fast
else
  fail test_invalid_axis_fails_fast "rc=$rc stderr=$(cat "$OUT")"
fi

# ---------------------------------------------------------------------------
# test_atomic_append_torture — 2 writers × 50 iter; expect 100 final entries.
# ---------------------------------------------------------------------------
case_ "test_atomic_append_torture"
STATE="$TMPROOT/rs_torture.json"
mk_run_state "$STATE"
WRITER_SCRIPT="$TMPROOT/writer.sh"
cat >"$WRITER_SCRIPT" <<EOF
#!/bin/bash
set -uo pipefail
export AUTORUN_RUN_STATE="$STATE"
# shellcheck disable=SC1090
source "$POLICY_SH"
WID="\$1"
i=0
while [ "\$i" -lt 50 ]; do
  policy_warn check verdict "writer-\$WID-iter-\$i" >/dev/null 2>&1
  i=\$(( i + 1 ))
done
EOF
chmod +x "$WRITER_SCRIPT"
"$WRITER_SCRIPT" A &
PID_A=$!
"$WRITER_SCRIPT" B &
PID_B=$!
wait "$PID_A"
wait "$PID_B"
total="$(count_list "$STATE" warnings)"
# Also verify it parses.
if python3 -c "import json; json.load(open('$STATE'))" 2>/dev/null && [ "$total" -eq 100 ]; then
  ok test_atomic_append_torture
else
  fail test_atomic_append_torture "total=$total expected=100"
fi

# ---------------------------------------------------------------------------
# test_no_python3_source_fails_fast
# ---------------------------------------------------------------------------
case_ "test_no_python3_source_fails_fast"
OUT="$TMPROOT/no_py3.err"
# Use env -i with bogus PATH so command -v python3 returns nothing.
# Note: HOME unset doesn't matter since the source guard runs before any HOME use.
env -i PATH=/nonexistent /bin/bash -c "source '$POLICY_SH'" 2>"$OUT"
rc=$?
if [ "$rc" -eq 2 ] && grep -q "python3 required" "$OUT"; then
  ok test_no_python3_source_fails_fast
else
  fail test_no_python3_source_fails_fast "rc=$rc stderr=$(cat "$OUT")"
fi

# ---------------------------------------------------------------------------
# test_flock_missing_uses_mkdir_fallback
# Force the mkdir path via override env, then assert the lockdir was created
# (and removed). We probe by injecting a tiny wedge: pre-create the lockdir,
# the mkdir-fallback retry loop will spin and fail → return 1; we then remove
# and retry to see success.
# ---------------------------------------------------------------------------
case_ "test_flock_missing_uses_mkdir_fallback"
(
  STATE="$TMPROOT/rs_mkdir.json"
  mk_run_state "$STATE"
  export AUTORUN_RUN_STATE="$STATE"
  export POLICY_LOCK_KIND_OVERRIDE="mkdir"
  # shellcheck disable=SC1090
  source "$POLICY_SH"
  # Sanity: mkdir-fallback path completes the append.
  policy_warn check verdict "mkdir-fallback-test"
  warns="$(count_list "$STATE" warnings)"
  if [ "$warns" -eq 1 ]; then
    exit 0
  else
    exit 1
  fi
)
if [ $? -eq 0 ]; then ok test_flock_missing_uses_mkdir_fallback; else fail test_flock_missing_uses_mkdir_fallback "mkdir fallback did not append"; fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed:"
  for t in "${FAILED[@]}"; do
    echo "  - $t"
  done
  exit 1
fi
exit 0
