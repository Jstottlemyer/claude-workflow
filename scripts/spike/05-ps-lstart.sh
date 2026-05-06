#!/bin/bash
# Probe 05 — ps -o lstart for lockfile staleness (PID + start-time invariant per D20)
# A bare PID can collide after pid wraparound; pairing with start-time uniquely identifies a process.
set -euo pipefail
trap 'echo FAIL: probe 05-ps-lstart failed at line $LINENO' ERR

PROBE="05-ps-lstart"

# Spawn a background sleep, capture its lstart, then verify ps reports the same lstart for that PID.
sleep 30 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT

# BSD ps: -o lstart= (no header) returns "Mon May  5 13:26:01 2026"
LSTART="$(ps -o lstart= -p "$PID" 2>/dev/null | sed 's/^ *//;s/ *$//')"

if [ -z "$LSTART" ]; then
  echo "FAIL: ps -o lstart returned empty for PID $PID"
  exit 1
fi

# Re-read; must be stable for the same process.
LSTART2="$(ps -o lstart= -p "$PID" 2>/dev/null | sed 's/^ *//;s/ *$//')"
if [ "$LSTART" != "$LSTART2" ]; then
  echo "FAIL: ps -o lstart not stable across reads: '$LSTART' vs '$LSTART2'"
  exit 1
fi

# Now query a non-existent PID (PID 1 always exists; pick a high one likely absent).
GHOST=99991
GHOST_LSTART="$(ps -o lstart= -p "$GHOST" 2>/dev/null | sed 's/^ *//;s/ *$//' || true)"
# Non-existent PID returns empty (or non-zero exit); either way the staleness check works.

echo "PASS: ps -o lstart for PID $PID = '$LSTART' (stable across reads). Canonical staleness check: read PID+lstart from lockfile; ps -o lstart -p <pid> matches → live; else stale."
