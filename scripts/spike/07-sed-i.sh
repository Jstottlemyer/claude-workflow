#!/bin/bash
# Probe 07 — sed -i portability (BSD requires backup-extension argument; GNU does not)
# Canonical portable form: sed -i.bak 's/old/new/' file && rm file.bak
set -euo pipefail
trap 'echo FAIL: probe 07-sed-i failed at line $LINENO' ERR

PROBE="07-sed-i"
TMPDIR="$(mktemp -d -t "${PROBE}.XXXXXX")"
trap 'rm -rf "$TMPDIR"' EXIT

F="$TMPDIR/sample.txt"
echo "hello world" > "$F"

# Canonical portable form (works on BSD + GNU):
sed -i.bak 's/hello/HELLO/' "$F"

if ! grep -q '^HELLO world$' "$F"; then
  echo "FAIL: sed -i.bak did not edit file"
  exit 1
fi

if [ ! -f "${F}.bak" ]; then
  echo "FAIL: backup file not created (.bak)"
  exit 1
fi
rm -f "${F}.bak"

# Verify BSD-incompatible form (`sed -i` with no extension) fails or gives surprising behavior.
echo "hello world" > "$F"
if sed -i 's/hello/HELLO/' "$F" 2>/dev/null; then
  if grep -q '^HELLO world$' "$F"; then
    echo "NOTE: 'sed -i' (no ext) worked on this host (looks like GNU sed). On BSD this would fail."
  fi
else
  echo "NOTE: 'sed -i' (no ext) failed as expected on BSD."
fi

echo "PASS: portable form is 'sed -i.bak ... && rm \"\${F}.bak\"' — works on both BSD (macOS) and GNU."
