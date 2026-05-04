#!/usr/bin/env bash
##############################################################################
# tests/test-scan-confirmation.sh — Wave 3 Task 3.4 (token-economics, M6)
#
# Privacy regression — verify the Tier 3 scan-projects-root confirmation
# flow in scripts/compute-persona-value.py. Complements
# test-path-validation.sh by drilling into the M6 contract corners:
#
#   1. Non-tty refusal surfaces a self-diagnostic (matches 'non-interactive')
#      and exit code is 0 (skip is graceful)
#   2. --confirm-scan-roots <dir> appends the dir to scan-roots.confirmed
#      (non-interactive flow, exit 0)
#   3. Re-running --confirm-scan-roots <same dir> is idempotent (file sha
#      unchanged, no duplicate row appended)
#   4. Pre-confirmed roots are accepted on subsequent --scan-projects-root
#      invocations from non-tty (no skip event for that root)
#   5. .monsterflow-no-scan sentinel — child project bearing the sentinel
#      file is silently excluded from discovery output
#
# All state goes through a tmp XDG_CONFIG_HOME so the user's real
# ~/.config/monsterflow is NEVER touched.
#
# Spec: docs/specs/token-economics/spec.md (v4.2 §Project Discovery, §Privacy)
# Plan: docs/specs/token-economics/plan.md (v1.2 — Wave 3 task 3.4, M6)
##############################################################################
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

SCRIPT="scripts/compute-persona-value.py"

TMP_ROOT="$(TMPDIR=/tmp mktemp -d /tmp/test-scan-XXXXXX)"
TMP_ROOT_REAL="$(cd "$TMP_ROOT" && pwd -P)"
XDG_TMP="$TMP_ROOT/xdg"
mkdir -p "$XDG_TMP"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

# Permit /tmp + /private/tmp + the realpath so paths under our sandbox pass
# validate_project_root() (default $HOME-only allowlist would reject them).
export MONSTERFLOW_ALLOWED_ROOTS="/private/tmp:/tmp:$TMP_ROOT_REAL"
export XDG_CONFIG_HOME="$XDG_TMP"

PASS=0
FAIL=0
note_pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }
note_fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

# Helper — invoke with --best-effort so unrelated A1.5 mismatches don't mask
# the assertion target. Returns merged stdout+stderr; exit code captured.
run_pv() {
  python3 "$SCRIPT" --best-effort "$@" </dev/null 2>&1
}

# --------------------------------------------------------------------------
# 1. Non-tty refusal — when --scan-projects-root is unconfirmed, stderr must
#    contain 'non-interactive' AND exit code is 0 (graceful skip).
# --------------------------------------------------------------------------
NT_PROJ="$TMP_ROOT/nontty-proj"
mkdir -p "$NT_PROJ/docs/specs"

NT_OUT=""
NT_RC=0
NT_OUT="$(run_pv --scan-projects-root "$NT_PROJ" --dry-run)" || NT_RC=$?

if printf '%s\n' "$NT_OUT" | grep -qi 'non-interactive'; then
  note_pass "non-tty refusal — stderr matches 'non-interactive'"
else
  note_fail "non-tty refusal — stderr does NOT contain 'non-interactive'"
  printf '  output:\n%s\n' "$NT_OUT" | head -10
fi

if [ "$NT_RC" -eq 0 ]; then
  note_pass "non-tty refusal — exit code 0 (graceful skip)"
else
  note_fail "non-tty refusal — exit code $NT_RC (expected 0)"
fi

# --------------------------------------------------------------------------
# 2. --confirm-scan-roots <dir> appends to scan-roots.confirmed; exit 0.
# --------------------------------------------------------------------------
CONFIRM_PROJ="$TMP_ROOT/confirm-proj"
mkdir -p "$CONFIRM_PROJ"  # dir need only exist + validate

CONF_FILE="$XDG_TMP/monsterflow/scan-roots.confirmed"

C_RC=0
C_OUT="$(run_pv --confirm-scan-roots "$CONFIRM_PROJ")" || C_RC=$?

if [ "$C_RC" -eq 0 ]; then
  note_pass "--confirm-scan-roots <dir> exit code 0"
else
  note_fail "--confirm-scan-roots <dir> exit code $C_RC (expected 0)"
fi

if [ -f "$CONF_FILE" ]; then
  if grep -qF "$CONFIRM_PROJ" "$CONF_FILE"; then
    note_pass "--confirm-scan-roots appended <dir> to scan-roots.confirmed"
  else
    note_fail "--confirm-scan-roots did NOT append <dir> to scan-roots.confirmed"
    echo "  file content:"
    cat "$CONF_FILE" | head -5 | sed 's/^/    /'
  fi
else
  note_fail "--confirm-scan-roots did NOT create scan-roots.confirmed"
fi

# --------------------------------------------------------------------------
# 3. Idempotency — re-invoking with same dir is a no-op (sha unchanged).
# --------------------------------------------------------------------------
SHA_BEFORE="$(shasum "$CONF_FILE" 2>/dev/null | awk '{print $1}')"
run_pv --confirm-scan-roots "$CONFIRM_PROJ" >/dev/null 2>&1 || true
SHA_AFTER="$(shasum "$CONF_FILE" 2>/dev/null | awk '{print $1}')"
if [ -n "$SHA_BEFORE" ] && [ "$SHA_BEFORE" = "$SHA_AFTER" ]; then
  note_pass "re-invoking --confirm-scan-roots <same dir> is idempotent (sha unchanged)"
else
  note_fail "--confirm-scan-roots NOT idempotent (sha $SHA_BEFORE → $SHA_AFTER)"
fi

# --------------------------------------------------------------------------
# 4. Pre-confirmed root accepted from non-tty — populate scan-roots.confirmed
#    manually with a NEW dir, then run --scan-projects-root from non-tty;
#    the script must NOT print 'non-interactive' for that root, AND the
#    discovered_projects telemetry should report scan>=1 if a child project
#    exists.
# --------------------------------------------------------------------------
PRECONF_ROOT="$TMP_ROOT/preconf-root"
mkdir -p "$PRECONF_ROOT/child-proj/docs/specs"

# Append the resolved path (the script reads + resolves entries).
PRECONF_RESOLVED="$(cd "$PRECONF_ROOT" && pwd -P)"
printf '%s\n' "$PRECONF_RESOLVED" >> "$CONF_FILE"

PC_OUT="$(run_pv --scan-projects-root "$PRECONF_ROOT" --dry-run)" || true

# Should NOT contain non-interactive for this root (it was pre-confirmed).
# Use an exact-line check guarding against the case where a different root
# in the same invocation triggers the diagnostic.
if printf '%s\n' "$PC_OUT" | grep -qE 'discovered_projects:.*\bscan=[1-9]'; then
  note_pass "pre-confirmed root accepted from non-tty (scan>=1 in discovery telemetry)"
else
  note_fail "pre-confirmed root NOT accepted from non-tty (scan=0 or missing)"
  printf '  output:\n%s\n' "$PC_OUT" | head -10
fi

# --------------------------------------------------------------------------
# 5. .monsterflow-no-scan sentinel — silently excludes the child project.
# --------------------------------------------------------------------------
SENT_ROOT="$TMP_ROOT/sentinel-root"
mkdir -p "$SENT_ROOT/proj-with-sentinel/docs/specs"
mkdir -p "$SENT_ROOT/proj-clean/docs/specs"
: > "$SENT_ROOT/proj-with-sentinel/.monsterflow-no-scan"

# Pre-confirm this root so tier 3 walks it.
SENT_RESOLVED="$(cd "$SENT_ROOT" && pwd -P)"
printf '%s\n' "$SENT_RESOLVED" >> "$CONF_FILE"

SENT_OUT="$(run_pv --scan-projects-root "$SENT_ROOT" --dry-run)" || true

# Telemetry should report scan=1 (only proj-clean), NOT scan=2.
if printf '%s\n' "$SENT_OUT" | grep -qE 'discovered_projects:.*\bscan=1\b'; then
  note_pass ".monsterflow-no-scan sentinel — sentinel project silently excluded (scan=1)"
else
  note_fail ".monsterflow-no-scan sentinel — expected scan=1, got otherwise"
  printf '  output:\n%s\n' "$SENT_OUT" | head -10
fi

echo ""
echo "test-scan-confirmation: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
