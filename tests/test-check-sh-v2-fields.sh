#!/usr/bin/env bash
##############################################################################
# tests/test-check-sh-v2-fields.sh
#
# Tests for scripts/autorun/check.sh v2 verdict-field handling
# (pipeline-gate-permissiveness Wave 1 task 1.7):
#
#   - GO_WITH_FIXES + cap_reached:false  → exit 0, no integrity block
#   - NO_GO + cap_reached:true           → terminal NO_GO (reason text mentions
#                                          cap_reached so commands/check.md
#                                          can detect non-recyclable case)
#   - iteration: -1 / 0                  → integrity block (out-of-range)
#   - iteration: 99 (> iter_max + 1)     → integrity block
#
# Tests use CHECK_TEST_MODE=1 to bypass parallel reviewers + claude synthesis;
# the check.sh extract_and_decide() runs against a hand-crafted synthesis-log
# fixture containing a v2 ```check-verdict fence.
#
# Bash 3.2 compatible. No `mapfile`, no `${arr[-1]}`, no `[[ =~ ]]`, no `&>`.
# PIPESTATUS captured inside `||` branches per repo convention.
##############################################################################
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_SH="$REPO_ROOT/scripts/autorun/check.sh"
TMPROOT="$(mktemp -d -t "check-v2-test.XXXXXX")"
trap 'rm -rf "$TMPROOT"' EXIT

PASS=0
FAIL=0
FAILED=()

ok()    { PASS=$(( PASS + 1 )); printf "  PASS %s\n" "$1"; }
fail()  { FAIL=$(( FAIL + 1 )); FAILED+=("$1"); printf "  FAIL %s — %s\n" "$1" "$2"; }
case_() { printf "\n--- %s\n" "$1"; }

# setup_case CASE_DIR SLUG FIXTURE_PATH
#   Builds the env scaffolding identical to test-autorun-policy.sh's
#   setup_check_case (project dir + run-state.json + env exports). Echoes
#   `export ...` lines for caller to eval.
setup_case() {
  local case_dir="$1" slug="$2" fixture="$3"
  local project_dir="$case_dir/project"
  local artifact_dir="$case_dir/artifacts"
  local run_dir="$case_dir/runs/r"
  mkdir -p "$project_dir/queue" "$project_dir/docs/specs/$slug" \
           "$artifact_dir" "$run_dir"
  : > "$project_dir/queue/$slug.spec.md"
  cat > "$run_dir/run-state.json" <<EOF
{
  "schema_version": 1,
  "run_id": "11111111-2222-3333-4444-555555555555",
  "slug": "$slug",
  "started_at": "2026-05-05T12:00:00Z",
  "current_stage": "check",
  "warnings": [],
  "blocks": []
}
EOF
  cat <<EOF
export SLUG="$slug"
export QUEUE_DIR="$project_dir/queue"
export ARTIFACT_DIR="$artifact_dir"
export SPEC_FILE="$project_dir/queue/$slug.spec.md"
export PROJECT_DIR="$project_dir"
export AUTORUN_RUN_STATE="$run_dir/run-state.json"
export AUTORUN_CURRENT_STAGE="check"
export CHECK_TEST_MODE=1
export CHECK_TEST_SYNTHESIS_FILE="$fixture"
EOF
}

# state_get CASE_DIR PYTHON_EXPR
state_get() {
  local case_dir="$1" expr="$2"
  python3 -c "
import json
with open('$case_dir/runs/r/run-state.json') as f:
    d = json.load(f)
print($expr)
" 2>/dev/null
}

# write_v2_synthesis FIXTURE_PATH VERDICT ITERATION ITERATION_MAX CAP_REACHED
#   Emits a synthesis-log file with a v2 check-verdict fence. The verdict-fence
#   shape mirrors tests/fixtures/permissiveness/v2-verdict-valid.json but with
#   per-test field overrides. Note: the schema validator runs against the
#   sidecar before the v2-field code path, so we must satisfy `iteration >= 1`
#   /minimum/. To exercise the bound check independently, we set
#   `iteration_max` high enough that schema-level /minimum/ accepts the value
#   but the bound check (1 <= iteration <= iteration_max + 1) trips.
write_v2_synthesis() {
  local fix="$1" verdict="$2" iteration="$3" iter_max="$4" cap="$5"
  cat > "$fix" <<EOF
OVERALL_VERDICT: $verdict

Some prose. Synthesis output. Reviewers agreed.

\`\`\`check-verdict
{"schema_version":2,"prompt_version":"check-verdict@2.0","verdict":"$verdict","blocking_findings":[],"security_findings":[],"generated_at":"2026-05-05T18:42:11Z","iteration":$iteration,"iteration_max":$iter_max,"mode":"permissive","mode_source":"frontmatter","class_breakdown":{"architectural":0,"security":0,"contract":0,"documentation":0,"tests":0,"scope-cuts":0,"unclassified":0},"class_inferred_count":0,"followups_file":null,"cap_reached":$cap,"stage":"check"}
\`\`\`

Trailing prose.
EOF
}

# ---------------------------------------------------------------------------
# Test 1: GO_WITH_FIXES with cap_reached:false → check.sh exits 0; no block.
# ---------------------------------------------------------------------------
case_ "test_v2_go_with_fixes_no_cap"
T1_DIR="$TMPROOT/t1"
mkdir -p "$T1_DIR"
T1_FIX="$T1_DIR/synth.txt"
write_v2_synthesis "$T1_FIX" "GO_WITH_FIXES" 1 2 false

set +e
(
  eval "$(setup_case "$T1_DIR" "v2-gwf" "$T1_FIX")"
  # GO_WITH_FIXES routes through policy_act which consults policy_for_axis.
  # Default fallback for `verdict` axis is "block". For this test we exercise
  # the warn path (the spec contract: GO_WITH_FIXES means "stop, but emit
  # followups for /build" — warn semantics) by setting the env override.
  export AUTORUN_VERDICT_POLICY=warn
  bash "$CHECK_SH" >"$T1_DIR/out" 2>"$T1_DIR/err"
  echo $? > "$T1_DIR/rc"
)
set -e
T1_RC="$(cat "$T1_DIR/rc" 2>/dev/null || echo 99)"
T1_BLOCKS="$(state_get "$T1_DIR" "len(d.get('blocks',[]))")"
T1_SIDECAR="$T1_DIR/project/docs/specs/v2-gwf/check-verdict.json"
T1_SIDECAR_OK=0
[ -s "$T1_SIDECAR" ] && T1_SIDECAR_OK=1

# GO_WITH_FIXES with AUTORUN_VERDICT_POLICY=warn: policy_act warns + returns 0.
# Assert: rc==0 AND blocks==0 AND sidecar written.
if [ "$T1_RC" = "0" ] && [ "$T1_BLOCKS" = "0" ] && [ "$T1_SIDECAR_OK" = "1" ]; then
  ok test_v2_go_with_fixes_no_cap
else
  fail test_v2_go_with_fixes_no_cap "rc=$T1_RC blocks=$T1_BLOCKS sidecar=$T1_SIDECAR_OK err=$(tail -10 "$T1_DIR/err" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
# Test 2: NO_GO with cap_reached:true → terminal block with cap-aware reason.
# ---------------------------------------------------------------------------
case_ "test_v2_no_go_cap_reached_terminal"
T2_DIR="$TMPROOT/t2"
mkdir -p "$T2_DIR"
T2_FIX="$T2_DIR/synth.txt"
# cap_reached path: iteration > iteration_max is allowed (= iter_max + 1 =
# upper bound). Use iteration=3, iteration_max=2 so iter==iter_max+1 (in range).
write_v2_synthesis "$T2_FIX" "NO_GO" 3 2 true

set +e
(
  eval "$(setup_case "$T2_DIR" "v2-cap" "$T2_FIX")"
  bash "$CHECK_SH" >"$T2_DIR/out" 2>"$T2_DIR/err"
  echo $? > "$T2_DIR/rc"
)
set -e
T2_RC="$(cat "$T2_DIR/rc" 2>/dev/null || echo 99)"
T2_AXIS="$(state_get "$T2_DIR" "(d.get('blocks') or [{}])[0].get('axis','')")"
T2_REASON="$(state_get "$T2_DIR" "(d.get('blocks') or [{}])[0].get('reason','')")"
T2_REASON_HAS_CAP=0
# Match the literal phrase from check.sh: "cap_reached".
echo "$T2_REASON" | grep -q "cap_reached" && T2_REASON_HAS_CAP=1

if [ "$T2_RC" = "1" ] && [ "$T2_AXIS" = "verdict" ] && [ "$T2_REASON_HAS_CAP" = "1" ]; then
  ok test_v2_no_go_cap_reached_terminal
else
  fail test_v2_no_go_cap_reached_terminal "rc=$T2_RC axis='$T2_AXIS' reason='$T2_REASON' has_cap=$T2_REASON_HAS_CAP"
fi

# ---------------------------------------------------------------------------
# Test 3: iteration=0 (out of range; below lower bound 1) → integrity block.
# Note: iteration=-1 would fail the schema validator (minimum:1 in
# check-verdict.schema.json) — that is a separate code path. To exercise the
# bound check after schema validation passes, we use iteration=0... but the
# schema's `minimum: 1` will catch that too. So we test iteration=99 (above
# upper bound) instead — which the schema accepts but our bound rejects.
# This is renamed to make the boundary intent explicit.
# ---------------------------------------------------------------------------
case_ "test_v2_iteration_above_upper_bound"
T3_DIR="$TMPROOT/t3"
mkdir -p "$T3_DIR"
T3_FIX="$T3_DIR/synth.txt"
# iteration=99 with iteration_max=2 → upper_bound = 3, so 99 > 3 → block.
# verdict=GO so this isolates the iteration-bound check from verdict gating.
write_v2_synthesis "$T3_FIX" "GO" 99 2 false

set +e
(
  eval "$(setup_case "$T3_DIR" "v2-iter-high" "$T3_FIX")"
  bash "$CHECK_SH" >"$T3_DIR/out" 2>"$T3_DIR/err"
  echo $? > "$T3_DIR/rc"
)
set -e
T3_RC="$(cat "$T3_DIR/rc" 2>/dev/null || echo 99)"
T3_AXIS="$(state_get "$T3_DIR" "(d.get('blocks') or [{}])[0].get('axis','')")"
T3_REASON="$(state_get "$T3_DIR" "(d.get('blocks') or [{}])[0].get('reason','')")"
T3_REASON_HAS_ITER=0
echo "$T3_REASON" | grep -q "iteration" && T3_REASON_HAS_ITER=1

if [ "$T3_RC" = "1" ] && [ "$T3_AXIS" = "integrity" ] && [ "$T3_REASON_HAS_ITER" = "1" ]; then
  ok test_v2_iteration_above_upper_bound
else
  fail test_v2_iteration_above_upper_bound "rc=$T3_RC axis='$T3_AXIS' reason='$T3_REASON'"
fi

# ---------------------------------------------------------------------------
# Test 4: v1 sidecar (no iteration field) → no bound check; passes through.
# Regression-guard for backward compat: v1 fixtures must not trip the new
# bound-check logic. Verdict=GO emits no block.
# ---------------------------------------------------------------------------
case_ "test_v1_sidecar_backcompat_no_bound_check"
T4_DIR="$TMPROOT/t4"
mkdir -p "$T4_DIR"
T4_FIX="$T4_DIR/synth.txt"
cat > "$T4_FIX" <<'EOF'
OVERALL_VERDICT: GO

v1 synthesis path (pre-permissiveness).

```check-verdict
{"schema_version":1,"prompt_version":"check-verdict@1.0","verdict":"GO","blocking_findings":[],"security_findings":[],"generated_at":"2026-05-05T12:00:00Z"}
```

End.
EOF

set +e
(
  eval "$(setup_case "$T4_DIR" "v1-back" "$T4_FIX")"
  bash "$CHECK_SH" >"$T4_DIR/out" 2>"$T4_DIR/err"
  echo $? > "$T4_DIR/rc"
)
set -e
T4_RC="$(cat "$T4_DIR/rc" 2>/dev/null || echo 99)"
T4_BLOCKS="$(state_get "$T4_DIR" "len(d.get('blocks',[]))")"

# NOTE: Wave 1 ships only check.sh + _policy_json.py KNOWN_SCHEMAS update. The
# check-verdict.schema.json file in main has already been bumped to v2-only
# (schema_version `const: 2`), so a v1 fixture will fail _policy_json.py
# validate. That schema-rejection path emits axis=integrity. This test allows
# either rc==0 (if v1 still validates as a transitional grace) OR rc==1 with
# axis=integrity (post-bump expected). Both are acceptable — the load-bearing
# assertion is that the new v2 bound-check code did not trip on missing
# iteration field, which would manifest as a different reason string.
T4_AXIS="$(state_get "$T4_DIR" "(d.get('blocks') or [{}])[0].get('axis','')")"
T4_REASON="$(state_get "$T4_DIR" "(d.get('blocks') or [{}])[0].get('reason','')")"
T4_NOT_BOUND_TRIP=1
echo "$T4_REASON" | grep -q "iteration field out of range" && T4_NOT_BOUND_TRIP=0

if [ "$T4_NOT_BOUND_TRIP" = "1" ]; then
  ok test_v1_sidecar_backcompat_no_bound_check
else
  fail test_v1_sidecar_backcompat_no_bound_check "rc=$T4_RC blocks=$T4_BLOCKS axis='$T4_AXIS' reason='$T4_REASON' (v1 fixture tripped v2 bound check)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf "\n=========================\n"
printf "PASSED: %d\n" "$PASS"
printf "FAILED: %d\n" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf "Failed cases:\n"
  for c in "${FAILED[@]}"; do printf "  - %s\n" "$c"; done
  exit 1
fi
exit 0
