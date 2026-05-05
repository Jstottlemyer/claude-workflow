#!/bin/bash
##############################################################################
# tests/test-resolve-personas.sh
#
# Unit tests for scripts/resolve-personas.sh — the per-gate persona resolver
# introduced by docs/specs/account-type-agent-scaling/spec.md.
#
# Mocking model (per memory feedback_path_stub_over_export_f):
#   - PATH-stub for `codex` binary; export -f doesn't survive subshells.
#   - MONSTERFLOW_CODEX_AUTH={1,0} hard-overrides the probe for cases where
#     the cache state would interfere.
#   - Each subtest gets an isolated $HOME under $TMPDIR; ~/.config/monsterflow/
#     and ~/.cache/monsterflow/ are clean per case.
#   - MONSTERFLOW_REPO_DIR pin keeps disk discovery stable across cwd.
#
# Bash 3.2 portability:
#   - No ${array[-1]} (memory feedback_negative_array_subscript_bash32).
#   - Pin BASH=/bin/bash.
#   - Tilde expansion: always ${VAR/#\~/$HOME} before any write.
##############################################################################
set -uo pipefail

export BASH=/bin/bash

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
RESOLVER="$REPO_DIR/scripts/resolve-personas.sh"
RANKINGS="$REPO_DIR/dashboard/data/persona-rankings.jsonl"

PASS=0
FAIL=0
FAILED_CASES=()

# Per-case scratch
CASE_DIR=""
CASE_HOME=""
CASE_OUT=""
CASE_ERR=""

setup_case() {
    CASE_DIR="$(mktemp -d -t mf-resolve-test)"
    CASE_HOME="$CASE_DIR/home"
    CASE_OUT="$CASE_DIR/out"
    CASE_ERR="$CASE_DIR/err"
    mkdir -p "$CASE_HOME/.config/monsterflow"
    : > "$CASE_OUT"
    : > "$CASE_ERR"
    export HOME="$CASE_HOME"
    export MONSTERFLOW_REPO_DIR="$REPO_DIR"
    # Default: codex unauthenticated unless case overrides
    export MONSTERFLOW_CODEX_AUTH=0
    unset MONSTERFLOW_DISABLE_BUDGET
}

teardown_case() {
    [ -n "$CASE_DIR" ] && [ -d "$CASE_DIR" ] && rm -rf "$CASE_DIR"
    CASE_DIR=""
}

write_config() {
    # $1 = JSON content
    printf '%s' "$1" > "$CASE_HOME/.config/monsterflow/config.json"
}

# Run resolver, capture stdout/stderr/exit. Args: gate [extra...]
run_resolver() {
    local exit_code=0
    bash "$RESOLVER" "$@" >"$CASE_OUT" 2>"$CASE_ERR" || exit_code=$?
    echo "$exit_code"
}

# Assertion helpers
assert_exit() {
    # $1 = case name, $2 = expected exit, $3 = actual exit
    local name="$1" expected="$2" actual="$3"
    if [ "$actual" != "$expected" ]; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: expected exit=$expected got=$actual")
        echo "    ✗ exit=$actual (expected $expected)" >&2
        if [ -s "$CASE_ERR" ]; then
            echo "    --- stderr ---" >&2
            sed 's/^/      /' < "$CASE_ERR" >&2
        fi
        return 1
    fi
    return 0
}

assert_stdout_lines() {
    # $1 = case name, $2 = expected line count
    local name="$1" expected="$2"
    local actual
    actual=$(grep -c . "$CASE_OUT" 2>/dev/null || echo 0)
    if [ "$actual" != "$expected" ]; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: expected $expected stdout lines, got $actual")
        echo "    ✗ stdout lines=$actual (expected $expected)" >&2
        echo "    --- stdout ---" >&2
        sed 's/^/      /' < "$CASE_OUT" >&2
        return 1
    fi
    return 0
}

assert_stdout_contains() {
    # $1 = case name, $2 = literal line that must appear
    local name="$1" needle="$2"
    if ! grep -qxF "$needle" "$CASE_OUT" 2>/dev/null; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: stdout missing '$needle'")
        echo "    ✗ stdout missing '$needle'" >&2
        sed 's/^/      /' < "$CASE_OUT" >&2
        return 1
    fi
    return 0
}

assert_stdout_lacks() {
    # $1 = case name, $2 = line that must NOT appear
    local name="$1" needle="$2"
    if grep -qxF "$needle" "$CASE_OUT" 2>/dev/null; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: stdout unexpectedly contains '$needle'")
        echo "    ✗ stdout has '$needle' (should be absent)" >&2
        return 1
    fi
    return 0
}

assert_first_line() {
    # $1 = case name, $2 = expected first line
    local name="$1" expected="$2"
    local actual
    actual=$(head -1 "$CASE_OUT" 2>/dev/null || echo "")
    if [ "$actual" != "$expected" ]; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: first line='$actual' (expected '$expected')")
        echo "    ✗ first line='$actual' (expected '$expected')" >&2
        return 1
    fi
    return 0
}

case_done() {
    local name="$1" status="$2"
    if [ "$status" = "ok" ]; then
        PASS=$(( PASS + 1 ))
        echo "  ✓ $name"
    fi
    teardown_case
}

##############################################################################
# Cases (numbered to match plan §10.1 where possible)
##############################################################################

case_1_no_config_full_roster() {
    setup_case
    local name="1: no config → full roster"
    local exit_code; exit_code=$(run_resolver check)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    # check has 5 personas on disk
    assert_stdout_lines "$name" 5 || status=fail
    assert_stdout_lacks "$name" "codex-adversary" || status=fail
    case_done "$name" "$status"
}

case_2_budget_absent_full_roster() {
    setup_case
    local name="2: agent_budget absent → full roster"
    write_config '{"persona_pins": {"check": ["risk"]}}'
    local exit_code; exit_code=$(run_resolver check)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    assert_stdout_lines "$name" 5 || status=fail
    case_done "$name" "$status"
}

case_3_budget_3_no_pins_no_rankings() {
    setup_case
    local name="3: budget=3, no pins, no rankings → seed[0:3]"
    write_config '{"agent_budget": 3}'
    # Move rankings file aside so resolver sees it absent
    local saved=""
    if [ -f "$RANKINGS" ]; then
        saved="$RANKINGS.test-$$.bak"
        mv "$RANKINGS" "$saved"
    fi
    local exit_code; exit_code=$(run_resolver check)
    local status=ok
    [ -n "$saved" ] && mv "$saved" "$RANKINGS"
    assert_exit "$name" 0 "$exit_code" || status=fail
    assert_stdout_lines "$name" 3 || status=fail
    assert_first_line "$name" "scope-discipline" || status=fail
    case_done "$name" "$status"
}

case_6_budget_1() {
    setup_case
    local name="6: budget=1 → exactly 1 persona"
    write_config '{"agent_budget": 1}'
    local exit_code; exit_code=$(run_resolver spec-review)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    assert_stdout_lines "$name" 1 || status=fail
    case_done "$name" "$status"
}

case_7_budget_8_plan_only_7() {
    setup_case
    local name="7: budget=8 plan (only 7 on disk) → 7 lines"
    write_config '{"agent_budget": 8}'
    local exit_code; exit_code=$(run_resolver plan)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    assert_stdout_lines "$name" 7 || status=fail
    case_done "$name" "$status"
}

case_8_pin_missing_persona() {
    setup_case
    local name="8: pin missing on disk → skipped + warned"
    write_config '{"agent_budget": 2, "persona_pins": {"check": ["nonexistent-persona", "risk"]}}'
    local exit_code; exit_code=$(run_resolver check)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    assert_stdout_contains "$name" "risk" || status=fail
    assert_stdout_lacks "$name" "nonexistent-persona" || status=fail
    if ! grep -q "nonexistent-persona" "$CASE_ERR"; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: stderr missing warning about missing pin")
        status=fail
    fi
    case_done "$name" "$status"
}

case_12_budget_zero() {
    setup_case
    local name="12: agent_budget=0 → floor 1"
    write_config '{"agent_budget": 0}'
    local exit_code; exit_code=$(run_resolver check)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    assert_stdout_lines "$name" 1 || status=fail
    case_done "$name" "$status"
}

case_13_budget_99_clamp() {
    setup_case
    local name="13: agent_budget=99 → clamp to 8"
    write_config '{"agent_budget": 99}'
    local exit_code; exit_code=$(run_resolver plan)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    # plan only has 7 personas, so we get 7 lines (clamp doesn't add nonexistent)
    assert_stdout_lines "$name" 7 || status=fail
    case_done "$name" "$status"
}

case_14_malformed_json() {
    setup_case
    local name="14: malformed JSON → exit 2"
    write_config '{ this is not valid json'
    local exit_code; exit_code=$(run_resolver check)
    local status=ok
    assert_exit "$name" 2 "$exit_code" || status=fail
    case_done "$name" "$status"
}

case_17_codex_authenticated() {
    setup_case
    local name="17: codex authenticated → codex-adversary appended last"
    write_config '{"agent_budget": 2}'
    export MONSTERFLOW_CODEX_AUTH=1
    local exit_code; exit_code=$(run_resolver check)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    # 2 Claude personas + 1 codex line = 3
    assert_stdout_lines "$name" 3 || status=fail
    # codex must be the last line
    local last_line; last_line=$(tail -1 "$CASE_OUT" 2>/dev/null)
    if [ "$last_line" != "codex-adversary" ]; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: last line='$last_line' (expected 'codex-adversary')")
        status=fail
    fi
    case_done "$name" "$status"
}

case_18_codex_not_authenticated() {
    setup_case
    local name="18: codex not authenticated → no codex line"
    write_config '{"agent_budget": 2}'
    export MONSTERFLOW_CODEX_AUTH=0
    local exit_code; exit_code=$(run_resolver check)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    assert_stdout_lines "$name" 2 || status=fail
    assert_stdout_lacks "$name" "codex-adversary" || status=fail
    case_done "$name" "$status"
}

case_20_codex_disabled_in_config() {
    setup_case
    local name="20: codex_disabled=true → codex never appears"
    write_config '{"agent_budget": 2, "codex_disabled": true}'
    export MONSTERFLOW_CODEX_AUTH=1   # would be appended without flag
    local exit_code; exit_code=$(run_resolver check)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    assert_stdout_lines "$name" 2 || status=fail
    assert_stdout_lacks "$name" "codex-adversary" || status=fail
    case_done "$name" "$status"
}

case_22_lock_honored() {
    setup_case
    local name="22: .budget-lock.json honored over live config"
    write_config '{"agent_budget": 5}'
    # Pre-create lock with budget=2 for a synthetic feature; need a real
    # docs/specs/<slug>/ dir for the lock writer path, but here we're testing
    # READ behavior so the parent must exist.
    local feature="test-lock-feature-$$"
    local fdir="$REPO_DIR/docs/specs/$feature"
    mkdir -p "$fdir"
    cat > "$fdir/.budget-lock.json" <<EOF
{
  "schema_version": 1,
  "agent_budget": 2,
  "persona_pins": {},
  "codex_disabled": false,
  "locked_at": "2026-05-04T00:00:00Z"
}
EOF
    local exit_code; exit_code=$(run_resolver check --feature "$feature")
    local status=ok
    rm -rf "$fdir"
    assert_exit "$name" 0 "$exit_code" || status=fail
    assert_stdout_lines "$name" 2 || status=fail
    case_done "$name" "$status"
}

case_24_unlock_budget() {
    setup_case
    local name="24: --unlock-budget removes lock"
    local feature="test-unlock-$$"
    local fdir="$REPO_DIR/docs/specs/$feature"
    mkdir -p "$fdir"
    echo '{"schema_version":1,"agent_budget":2,"persona_pins":{},"codex_disabled":false,"locked_at":"2026-05-04T00:00:00Z"}' \
        > "$fdir/.budget-lock.json"
    local exit_code; exit_code=$(run_resolver check --feature "$feature" --unlock-budget)
    local status=ok
    if [ -f "$fdir/.budget-lock.json" ]; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: lock file still present after --unlock-budget")
        status=fail
    fi
    rm -rf "$fdir"
    assert_exit "$name" 0 "$exit_code" || status=fail
    case_done "$name" "$status"
}

case_25_why_to_stderr() {
    setup_case
    local name="25: --why prints to stderr; stdout still strict"
    write_config '{"agent_budget": 2}'
    local exit_code; exit_code=$(run_resolver check --why)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    assert_stdout_lines "$name" 2 || status=fail
    if ! grep -q "selected:" "$CASE_ERR"; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: --why didn't write reasoning to stderr")
        status=fail
    fi
    case_done "$name" "$status"
}

case_26_print_schema() {
    setup_case
    local name="26: --print-schema emits valid JSON"
    local exit_code; exit_code=$(run_resolver --print-schema)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    if ! python3 -c "import json,sys; json.load(open('$CASE_OUT'))" 2>/dev/null; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: --print-schema output is not valid JSON")
        status=fail
    fi
    case_done "$name" "$status"
}

case_29_disable_budget_kill_switch() {
    setup_case
    local name="29: MONSTERFLOW_DISABLE_BUDGET=1 → full roster"
    write_config '{"agent_budget": 1}'
    export MONSTERFLOW_DISABLE_BUDGET=1
    local exit_code; exit_code=$(run_resolver check)
    local status=ok
    unset MONSTERFLOW_DISABLE_BUDGET
    assert_exit "$name" 0 "$exit_code" || status=fail
    assert_stdout_lines "$name" 5 || status=fail
    case_done "$name" "$status"
}

case_30_emit_selection_json() {
    setup_case
    local name="30: --emit-selection-json writes audit row"
    write_config '{"agent_budget": 2}'
    local feature="test-emit-$$"
    local fdir="$REPO_DIR/docs/specs/$feature"
    mkdir -p "$fdir"
    local exit_code; exit_code=$(run_resolver check --feature "$feature" --emit-selection-json)
    local status=ok
    if [ ! -f "$fdir/check/selection.json" ]; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: selection.json not written")
        status=fail
    else
        # Validate schema
        if ! python3 -c "
import json, sys
d = json.load(open('$fdir/check/selection.json'))
required = ['schema_version','feature','gate','ran_at','selection_method','selected','dropped','codex_status','budget_used','budget_source','locked_from','resolver_exit']
missing = [k for k in required if k not in d]
sys.exit(1 if missing else 0)
" 2>/dev/null; then
            FAIL=$(( FAIL + 1 ))
            FAILED_CASES+=("$name: selection.json missing required keys")
            status=fail
        fi
    fi
    rm -rf "$fdir"
    assert_exit "$name" 0 "$exit_code" || status=fail
    case_done "$name" "$status"
}

case_31_invalid_gate() {
    setup_case
    local name="31: invalid gate → exit 5"
    local exit_code; exit_code=$(run_resolver bogus-gate)
    local status=ok
    assert_exit "$name" 5 "$exit_code" || status=fail
    case_done "$name" "$status"
}

case_32_emit_json_no_feature() {
    setup_case
    local name="32: --emit-selection-json without --feature → exit 4"
    local exit_code; exit_code=$(run_resolver check --emit-selection-json)
    local status=ok
    assert_exit "$name" 4 "$exit_code" || status=fail
    case_done "$name" "$status"
}

# AC #7 — recovery prompt support: --print-seed lets the recovery fragment's
# "(2) continue with seed" option fetch the canonical per-gate seed list
# without re-implementing it in shell. Coverage:
#   - happy path: each gate emits its full seed list (newline-separated)
#   - exit code: 0 on success, 4 on missing/invalid gate
#   - codex never appears (Codex is owned by the resolver's auth probe)

case_33_print_seed_spec_review() {
    setup_case
    local name="33: --print-seed spec-review emits 6 names"
    local exit_code; exit_code=$(run_resolver spec-review --print-seed)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    assert_stdout_lines "$name" 6 || status=fail
    assert_first_line "$name" "requirements" || status=fail
    assert_stdout_lacks "$name" "codex-adversary" || status=fail
    case_done "$name" "$status"
}

case_34_print_seed_plan() {
    setup_case
    local name="34: --print-seed plan emits 7 names (wave-sequencer present)"
    local exit_code; exit_code=$(run_resolver plan --print-seed)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    assert_stdout_lines "$name" 7 || status=fail
    assert_stdout_contains "$name" "wave-sequencer" || status=fail
    case_done "$name" "$status"
}

case_35_print_seed_check() {
    setup_case
    local name="35: --print-seed check emits 5 names"
    local exit_code; exit_code=$(run_resolver check --print-seed)
    local status=ok
    assert_exit "$name" 0 "$exit_code" || status=fail
    assert_stdout_lines "$name" 5 || status=fail
    assert_first_line "$name" "scope-discipline" || status=fail
    case_done "$name" "$status"
}

case_36_print_seed_invalid_gate() {
    setup_case
    local name="36: --print-seed without gate → exit 4"
    local exit_code; exit_code=$(run_resolver --print-seed)
    local status=ok
    assert_exit "$name" 4 "$exit_code" || status=fail
    case_done "$name" "$status"
}

case_37_print_seed_unknown_gate() {
    setup_case
    local name="37: --print-seed bogus-gate → exit 4"
    local exit_code; exit_code=$(run_resolver bogus-gate --print-seed)
    local status=ok
    assert_exit "$name" 4 "$exit_code" || status=fail
    case_done "$name" "$status"
}

# AC #7 — recovery-fragment wiring: the canonical fragment file exists and is
# referenced by all three gate command files. Without these references, AC #7
# has no callable surface in interactive mode.
case_38_recovery_fragment_exists() {
    setup_case
    local name="38: _resolver-recovery.md fragment exists and is referenced"
    local fragment="$REPO_DIR/commands/_prompts/_resolver-recovery.md"
    local status=ok
    if [ ! -f "$fragment" ]; then
        FAIL=$(( FAIL + 1 ))
        FAILED_CASES+=("$name: fragment $fragment missing")
        status=fail
    fi
    for cmd in spec-review plan check; do
        if ! grep -q "_resolver-recovery.md" "$REPO_DIR/commands/$cmd.md"; then
            FAIL=$(( FAIL + 1 ))
            FAILED_CASES+=("$name: commands/$cmd.md does not reference _resolver-recovery.md")
            status=fail
        fi
    done
    # Fragment must enumerate the three options and explicitly forbid silent
    # full-roster restoration (per AC #7 + plan D6 / SP3).
    for needle in "reconfigure now" "continue with seed" "abort gate"; do
        if ! grep -qF "$needle" "$fragment"; then
            FAIL=$(( FAIL + 1 ))
            FAILED_CASES+=("$name: fragment missing recovery option text '$needle'")
            status=fail
        fi
    done
    case_done "$name" "$status"
}

##############################################################################
# Main
##############################################################################

echo "=== test-resolve-personas.sh ==="
echo "REPO_DIR=$REPO_DIR"
echo ""

case_1_no_config_full_roster
case_2_budget_absent_full_roster
case_3_budget_3_no_pins_no_rankings
case_6_budget_1
case_7_budget_8_plan_only_7
case_8_pin_missing_persona
case_12_budget_zero
case_13_budget_99_clamp
case_14_malformed_json
case_17_codex_authenticated
case_18_codex_not_authenticated
case_20_codex_disabled_in_config
case_22_lock_honored
case_24_unlock_budget
case_25_why_to_stderr
case_26_print_schema
case_29_disable_budget_kill_switch
case_30_emit_selection_json
case_31_invalid_gate
case_32_emit_json_no_feature
case_33_print_seed_spec_review
case_34_print_seed_plan
case_35_print_seed_check
case_36_print_seed_invalid_gate
case_37_print_seed_unknown_gate
case_38_recovery_fragment_exists

echo ""
echo "=========================================="
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    echo "Failed cases:"
    for c in "${FAILED_CASES[@]}"; do
        echo "  - $c"
    done
    exit 1
fi
exit 0
