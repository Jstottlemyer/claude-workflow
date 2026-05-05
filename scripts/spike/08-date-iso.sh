#!/bin/bash
# Probe 08 — BSD date ISO-8601 UTC formatting
# `date -d` is GNU-only; `date -u +FMT` works on both.
set -euo pipefail
trap 'echo FAIL: probe 08-date-iso failed at line $LINENO' ERR

PROBE="08-date-iso"

# Canonical portable form:
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Validate format with a regex.
REGEX='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
if ! [[ "$NOW" =~ $REGEX ]]; then
  echo "FAIL: ISO-8601 UTC format wrong: $NOW"
  exit 1
fi

# Verify -d is GNU-only (BSD date treats -d as 'set kvm dump'):
if date -d "2026-01-01" +%s >/dev/null 2>&1; then
  echo "NOTE: date -d works on this host (GNU date or BSD with non-default flag handling)"
else
  echo "NOTE: date -d is GNU-only; BSD date rejects it. Implementation must NOT use -d. Use -j -f for BSD parsing if needed (separate probe path)."
fi

# BSD-friendly parsing alternative (informational):
# BSD: date -j -f "%Y-%m-%d" "2026-01-01" +%s
# GNU: date -d "2026-01-01" +%s
# For autorun's needs, only the formatting form (date -u +FMT) is required.

echo "PASS: 'date -u +%Y-%m-%dT%H:%M:%SZ' = $NOW (portable BSD + GNU). Implementation MUST NOT use 'date -d'."
