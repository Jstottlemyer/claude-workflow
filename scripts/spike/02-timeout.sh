#!/bin/bash
# Probe 02 — timeout (BSD via Homebrew gtimeout, vs GNU timeout)
# Stock macOS does NOT ship `timeout`. Homebrew coreutils provides gtimeout.
set -euo pipefail
trap 'echo FAIL: probe 02-timeout failed at line $LINENO' ERR

PROBE="02-timeout"
TIMEOUT_CMD=""
if command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD="gtimeout"
elif command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD="timeout"
fi

if [ -z "$TIMEOUT_CMD" ]; then
  echo "FAIL: no timeout command available on this host (need 'brew install coreutils' for gtimeout)"
  exit 1
fi

# Verify it returns 124 on expiry (GNU/coreutils convention).
# Use `if !` pattern to keep `set -e` happy and still capture the exit.
RC=0
if "$TIMEOUT_CMD" 0.2 sleep 5; then RC=0; else RC=$?; fi
if [ "$RC" -ne 124 ]; then
  echo "FAIL: expected exit 124 on timeout expiry, got $RC ($TIMEOUT_CMD)"
  exit 1
fi

# Verify normal exit pass-through.
RC=0
if "$TIMEOUT_CMD" 5 true; then RC=0; else RC=$?; fi
if [ "$RC" -ne 0 ]; then
  echo "FAIL: expected exit 0 on under-budget command, got $RC"
  exit 1
fi

echo "PASS: timeout via '$TIMEOUT_CMD' (124-on-expiry, 0-on-success). Adopter contract: prefer gtimeout; fall back to timeout; doctor.sh must warn if neither present."
