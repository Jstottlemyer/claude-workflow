#!/bin/bash
# Probe 09 — BSD stat (-f) vs GNU stat (-c)
# Probe extracts file size + mtime portably.
set -euo pipefail
trap 'echo FAIL: probe 09-stat failed at line $LINENO' ERR

PROBE="09-stat"
TMPDIR="$(mktemp -d -t "${PROBE}.XXXXXX")"
trap 'rm -rf "$TMPDIR"' EXIT

F="$TMPDIR/sample.bin"
printf 'hello world' > "$F"   # 11 bytes

# Detect flavor.
SIZE=""
MTIME=""
FLAVOR=""

if stat -f '%z' "$F" >/dev/null 2>&1; then
  SIZE="$(stat -f '%z' "$F")"
  MTIME="$(stat -f '%m' "$F")"
  FLAVOR="bsd"
elif stat -c '%s' "$F" >/dev/null 2>&1; then
  SIZE="$(stat -c '%s' "$F")"
  MTIME="$(stat -c '%Y' "$F")"
  FLAVOR="gnu"
else
  echo "FAIL: neither BSD (-f) nor GNU (-c) stat works"
  exit 1
fi

if [ "$SIZE" != "11" ]; then
  echo "FAIL: expected size 11, got $SIZE ($FLAVOR)"
  exit 1
fi

if ! [[ "$MTIME" =~ ^[0-9]+$ ]]; then
  echo "FAIL: mtime not numeric: '$MTIME' ($FLAVOR)"
  exit 1
fi

echo "PASS: stat flavor='$FLAVOR', size=$SIZE, mtime=$MTIME. Canonical: detect via 'stat -f %z FILE' first, fallback to 'stat -c %s FILE'."
