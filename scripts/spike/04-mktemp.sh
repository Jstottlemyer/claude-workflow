#!/bin/bash
# Probe 04 — mktemp portability (BSD vs GNU)
# BSD: mktemp -t <prefix> creates in $TMPDIR with prefix.XXXXXX
# GNU: mktemp --tmpdir -t <template>
# Portable form: mktemp -t "${prefix}.XXXXXX" works on BOTH (mac BSD requires the X-template).
set -euo pipefail
trap 'echo FAIL: probe 04-mktemp failed at line $LINENO' ERR

PROBE="04-mktemp"
PREFIX="autorun-spike"

# Form 1: portable -t with X-template (works on BSD + GNU)
F1="$(mktemp -t "${PREFIX}.XXXXXX")"
if [ ! -f "$F1" ]; then
  echo "FAIL: mktemp -t with X-template failed: $F1"
  exit 1
fi
rm -f "$F1"

# Form 2: directory variant
D1="$(mktemp -d -t "${PREFIX}.XXXXXX")"
if [ ! -d "$D1" ]; then
  echo "FAIL: mktemp -d -t failed: $D1"
  exit 1
fi
rmdir "$D1"

# BSD-specific: confirm that bare `mktemp -t prefix` (no XXXXXX) works on BSD but not GNU.
# Skip — we standardize on the X-template form which works everywhere.

# GNU-specific check: --tmpdir flag (will fail on BSD; informational only)
if mktemp --tmpdir -t "${PREFIX}-gnu.XXXXXX" 2>/dev/null >/tmp/.spike-gnu-mktemp; then
  rm -f "$(cat /tmp/.spike-gnu-mktemp)" /tmp/.spike-gnu-mktemp
  echo "NOTE: GNU mktemp --tmpdir works on this host"
else
  rm -f /tmp/.spike-gnu-mktemp
  echo "NOTE: --tmpdir not supported (BSD mktemp); use 'mktemp -t prefix.XXXXXX' canonical form"
fi

echo "PASS: mktemp -t '${PREFIX}.XXXXXX' is the portable canonical form (BSD + GNU)"
