#!/usr/bin/env bash
##############################################################################
# scripts/autorun/_codex_probe.sh
#
# Autorun-shell-only Codex availability + auth probe (Task 2.2 of
# autorun-overnight-policy plan v6). Replaces the inline `command -v codex`
# check at run.sh:394 (consolidation lands in Task 3.5).
#
# Contract:
#   Exit 0 — codex on PATH and `codex login status` returns 0 (authed)
#   Exit 1 — codex binary not on PATH (unavailable)
#   Exit 2 — codex present but `codex login status` returned non-zero (auth-failed)
#
# Stdout: nothing.
# Stderr: silent unless --verbose, in which case one line:
#         [codex_probe] available
#         [codex_probe] unavailable
#         [codex_probe] auth-failed
#
# No tmp files, so the ERR trap is just a defensive no-op for future-proofing.
#
# Bash 3.2 compatible. Tested on macOS Darwin 24.6.0.
##############################################################################
set -euo pipefail

# Defensive cleanup hook (no tmp files today; here so future edits inherit
# the discipline without forgetting to add an ERR trap).
_codex_probe_cleanup() {
  : # no-op
}
trap _codex_probe_cleanup ERR EXIT

VERBOSE=0
for arg in "$@"; do
  case "$arg" in
    --verbose|-v) VERBOSE=1 ;;
    *) ;; # ignore unknown flags — keep probe trivially callable
  esac
done

_emit() {
  if [ "$VERBOSE" -eq 1 ]; then
    printf '[codex_probe] %s\n' "$1" >&2
  fi
}

# Step 1: binary on PATH?
if ! command -v codex >/dev/null 2>&1; then
  _emit "unavailable"
  exit 1
fi

# Step 2: authenticated? `codex login status` exits non-zero when not logged in.
if ! codex login status >/dev/null 2>&1; then
  _emit "auth-failed"
  exit 2
fi

_emit "available"
exit 0
