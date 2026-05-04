#!/usr/bin/env bash
##############################################################################
# tests/test-path-validation.sh — Wave 1 Task 1.11 (token-economics)
#
# Asserts validate_project_root() and the surrounding M6 confirmation flow
# in scripts/compute-persona-value.py reject unsafe inputs and accept safe
# ones. Subprocess-driven (no in-process import) — exercises the actual
# user-facing CLI surface.
#
# Asserts:
#   1. Non-absolute path rejected (output contains 'reject')
#   2. `..` segments rejected (output contains 'reject')
#   3. Path outside $HOME (and outside MONSTERFLOW_ALLOWED_ROOTS) rejected
#   4. .monsterflow-no-scan sentinel — a tmp project carrying the sentinel
#      is silently skipped from tier-3 cascade output (count stays 0)
#   5. (M6) --confirm-scan-roots accepts a valid path; scan-roots.confirmed
#      is updated; re-run is idempotent (file content unchanged)
#   6. (M6) Non-tty refusal: scan-projects-root with NOT-pre-confirmed path
#      surfaces 'non-interactive' in the output
#
# All state goes through a tmp XDG_CONFIG_HOME so the user's real
# ~/.config/monsterflow is NEVER touched. MONSTERFLOW_ALLOWED_ROOTS is set
# to /private/tmp:/tmp because tmp paths resolve outside $HOME on macOS.
#
# Spec: docs/specs/token-economics/spec.md (v4.2 §Project Discovery, §Privacy)
# Plan: docs/specs/token-economics/plan.md (v1.2 — Wave 1 task 1.11, M6, decision #15)
##############################################################################
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

SCRIPT="scripts/compute-persona-value.py"

# Isolated XDG_CONFIG_HOME and tmp workspace. We force TMPDIR=/tmp so
# mktemp produces paths under /tmp (resolves to /private/tmp on macOS),
# which we then add to MONSTERFLOW_ALLOWED_ROOTS — the default $HOME-only
# allowlist would otherwise reject every tmp path validate_project_root()
# sees in this test.
TMP_ROOT="$(TMPDIR=/tmp mktemp -d /tmp/test-pv-XXXXXX)"
# Resolve the realpath because /tmp -> /private/tmp on macOS and the script
# resolves symlinks before checking allowed roots.
TMP_ROOT_REAL="$(cd "$TMP_ROOT" && pwd -P)"
XDG_TMP="$TMP_ROOT/xdg"
SCAN_TMP="$TMP_ROOT/scan"
mkdir -p "$XDG_TMP" "$SCAN_TMP"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

# Permit both the symlink form (/tmp) and resolved form (/private/tmp + the
# realpath of TMP_ROOT) so paths under our sandbox pass validate_project_root.
export MONSTERFLOW_ALLOWED_ROOTS="/private/tmp:/tmp:$TMP_ROOT_REAL"
export XDG_CONFIG_HOME="$XDG_TMP"

PASS=0
FAIL=0
note_pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }
note_fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

# Helper — run the script with --best-effort so an A1.5 failure unrelated to
# what we're testing doesn't mask the real assertions. Exit code is captured
# but we mostly grep the merged stdout+stderr for the rejection signal.
run_pv() {
  python3 "$SCRIPT" --best-effort "$@" </dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# 1. Non-absolute path is rejected.
# ---------------------------------------------------------------------------
OUT="$(run_pv --scan-projects-root './rel/path')"
if printf '%s\n' "$OUT" | grep -qi 'reject'; then
  note_pass "non-absolute path rejected (rel/path)"
else
  note_fail "non-absolute path NOT rejected"
  printf '  output:\n%s\n' "$OUT" | head -10
fi

# ---------------------------------------------------------------------------
# 2. `..` segments rejected.
# ---------------------------------------------------------------------------
OUT="$(run_pv --scan-projects-root '/tmp/../etc')"
if printf '%s\n' "$OUT" | grep -qi 'reject'; then
  note_pass "path with .. segments rejected (/tmp/../etc)"
else
  note_fail "path with .. segments NOT rejected"
  printf '  output:\n%s\n' "$OUT" | head -10
fi

# ---------------------------------------------------------------------------
# 3. Path outside $HOME (and outside MONSTERFLOW_ALLOWED_ROOTS) rejected.
#    Override MONSTERFLOW_ALLOWED_ROOTS to a known-good harmless dir so /etc
#    is genuinely "outside" the allowed roots for this single check.
# ---------------------------------------------------------------------------
OUT="$(MONSTERFLOW_ALLOWED_ROOTS="$TMP_ROOT" run_pv --scan-projects-root '/etc')"
if printf '%s\n' "$OUT" | grep -qi 'reject'; then
  note_pass "path outside allowed roots rejected (/etc)"
else
  note_fail "path outside allowed roots NOT rejected"
  printf '  output:\n%s\n' "$OUT" | head -10
fi

# ---------------------------------------------------------------------------
# 4. .monsterflow-no-scan sentinel — confirmed scan root with TWO child
#    projects, one carrying the sentinel. Discovery should yield count=1
#    (not 2) for the scan tier.
# ---------------------------------------------------------------------------
SENT_ROOT="$SCAN_TMP/sentinel-root"
mkdir -p "$SENT_ROOT/proj-with-sentinel/docs/specs"
mkdir -p "$SENT_ROOT/proj-clean/docs/specs"
: > "$SENT_ROOT/proj-with-sentinel/.monsterflow-no-scan"

# Pre-confirm the scan root so tier 3 will actually walk it.
run_pv --confirm-scan-roots "$SENT_ROOT" >/dev/null

OUT="$(run_pv --scan-projects-root "$SENT_ROOT" --dry-run)"
# Look for the discovered_projects telemetry line; expect scan=1 (the clean
# project) — the sentinel-bearing one must be silently skipped.
if printf '%s\n' "$OUT" | grep -qE 'discovered_projects:.*\bscan=1\b'; then
  note_pass ".monsterflow-no-scan sentinel skipped (scan=1, sentinel project absent)"
else
  note_fail ".monsterflow-no-scan sentinel NOT honored — expected scan=1"
  printf '  output:\n%s\n' "$OUT" | head -20
fi

# ---------------------------------------------------------------------------
# 5. (M6) --confirm-scan-roots accepts a valid path under the allowed roots,
#         updates scan-roots.confirmed, and is idempotent on re-run.
# ---------------------------------------------------------------------------
M6_PROJ="$TMP_ROOT/m6-proj"
mkdir -p "$M6_PROJ/docs/specs"

# Fresh XDG dir for this isolated assertion so we can byte-compare contents.
M6_XDG="$TMP_ROOT/xdg-m6"
mkdir -p "$M6_XDG"

XDG_CONFIG_HOME="$M6_XDG" run_pv --confirm-scan-roots "$M6_PROJ" >/dev/null
CONF_FILE="$M6_XDG/monsterflow/scan-roots.confirmed"
if [ -f "$CONF_FILE" ]; then
  note_pass "--confirm-scan-roots created scan-roots.confirmed"
else
  note_fail "--confirm-scan-roots did NOT create scan-roots.confirmed"
fi

# Capture content + sha for idempotency check.
SHA_BEFORE="$(shasum "$CONF_FILE" 2>/dev/null | awk '{print $1}')"
XDG_CONFIG_HOME="$M6_XDG" run_pv --confirm-scan-roots "$M6_PROJ" >/dev/null
SHA_AFTER="$(shasum "$CONF_FILE" 2>/dev/null | awk '{print $1}')"
if [ -n "$SHA_BEFORE" ] && [ "$SHA_BEFORE" = "$SHA_AFTER" ]; then
  note_pass "--confirm-scan-roots idempotent (file sha unchanged on re-run)"
else
  note_fail "--confirm-scan-roots NOT idempotent (sha changed: $SHA_BEFORE -> $SHA_AFTER)"
fi

# ---------------------------------------------------------------------------
# 6. (M6) Non-tty refusal — when --scan-projects-root path is NOT pre-
#         confirmed and stdin is not a tty, the script must print the
#         'non-interactive' diagnostic.
# ---------------------------------------------------------------------------
NT_PROJ="$TMP_ROOT/nontty-proj"
mkdir -p "$NT_PROJ/docs/specs"
NT_XDG="$TMP_ROOT/xdg-nontty"
mkdir -p "$NT_XDG"

OUT="$(XDG_CONFIG_HOME="$NT_XDG" run_pv --scan-projects-root "$NT_PROJ")"
if printf '%s\n' "$OUT" | grep -qi 'non-interactive'; then
  note_pass "non-tty refusal surfaces 'non-interactive' diagnostic"
else
  note_fail "non-tty refusal did NOT surface 'non-interactive' diagnostic"
  printf '  output:\n%s\n' "$OUT" | head -10
fi

echo ""
echo "test-path-validation: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
