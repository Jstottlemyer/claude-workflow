#!/bin/bash
# tests/test-install-upgrade-banner.sh
#
# Validates the v0.9.0 one-time upgrade banner added to install.sh under
# Wave 4 Task 4.3 of the pipeline-gate-permissiveness spec.
#
# Bash 3.2 compat: no `${arr[-1]}`, no `mapfile`, no `&>`, no `[[ =~ ]]`.
# Tests are grep-based; we don't execute install.sh here (the harness does
# that elsewhere via tests/test-install.sh).

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
INSTALL_SH="$REPO_ROOT/install.sh"

PASS=0
FAIL=0
fail() {
    FAIL=$((FAIL + 1))
    echo "  FAIL: $1"
}
pass() {
    PASS=$((PASS + 1))
    echo "  PASS: $1"
}

echo "test-install-upgrade-banner.sh"

# --- Test 1: install.sh syntax-checks clean ---
if bash -n "$INSTALL_SH" 2>/dev/null; then
    pass "install.sh passes bash -n"
else
    fail "install.sh failed bash -n syntax check"
fi

# --- Test 2: v0.9.0 bullet text present ---
# Accept either canonical phrase as a substring match.
if grep -qF "Pipeline gates default to permissive" "$INSTALL_SH"; then
    pass "v0.9.0 bullet text present (Pipeline gates default to permissive)"
elif grep -qF "gate_mode: strict" "$INSTALL_SH"; then
    pass "v0.9.0 bullet text present (gate_mode: strict reference)"
else
    fail "v0.9.0 bullet text missing — neither 'Pipeline gates default to permissive' nor 'gate_mode: strict' found"
fi

# --- Test 3: sentinel path present (with HOME-expansion variants accepted) ---
# Accept the literal `~/.claude/...`, `$HOME/.claude/...`, or just the basename.
if grep -qF "gate-permissiveness-migration-shown" "$INSTALL_SH"; then
    pass "sentinel path present (.gate-permissiveness-migration-shown)"
else
    fail "sentinel path missing — '.gate-permissiveness-migration-shown' not found"
fi

# --- Test 4: first-run gating present (sentinel guard) ---
# Look for `if [ ! -f` or `if ! [ -f` near the new bullet — proves the guard exists.
# We grep the whole file because line-proximity testing is brittle in bash 3.2.
GATE_GUARD_LINES=$(grep -c -E '^\s*if \[ ! -f .*GATE_PERMISSIVENESS_SENTINEL|^\s*if ! \[ -f .*GATE_PERMISSIVENESS_SENTINEL' "$INSTALL_SH" 2>/dev/null || echo 0)
# Strip whitespace from grep -c output (some greps return "0\n")
GATE_GUARD_LINES="${GATE_GUARD_LINES//[[:space:]]/}"
if [ "${GATE_GUARD_LINES:-0}" -ge 1 ] 2>/dev/null; then
    pass "sentinel guard present (if [ ! -f ... ] / if ! [ -f ... ] near GATE_PERMISSIVENESS_SENTINEL)"
else
    # Fallback: any first-run-style guard reference to the sentinel variable.
    if grep -qE 'if \[ ! -f.*\$GATE_PERMISSIVENESS_SENTINEL|if \! \[ -f.*\$GATE_PERMISSIVENESS_SENTINEL' "$INSTALL_SH"; then
        pass "sentinel guard present (fallback regex)"
    else
        fail "sentinel guard missing — no 'if [ ! -f ... GATE_PERMISSIVENESS_SENTINEL ]' style first-run check found"
    fi
fi

# --- Test 5: PERSONA_METRICS_GITIGNORE block intact (W1.9 preserved) ---
PMG_COUNT=$(grep -c "BEGIN persona-metrics" "$INSTALL_SH" 2>/dev/null || echo 0)
PMG_COUNT="${PMG_COUNT//[[:space:]]/}"
if [ "${PMG_COUNT:-0}" -ge 1 ] 2>/dev/null; then
    pass "PERSONA_METRICS_GITIGNORE block intact (BEGIN persona-metrics found, $PMG_COUNT match(es))"
else
    fail "PERSONA_METRICS_GITIGNORE block missing — 'BEGIN persona-metrics' sentinel not found"
fi

# --- Summary ---
echo ""
echo "  passed: $PASS"
echo "  failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
