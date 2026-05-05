#!/bin/bash
# Probe 03 — uuidgen lowercase normalization (SF3, AC#13)
# macOS uuidgen emits UPPERCASE. AC#13 regex is lowercase-only. Verify tr 'A-Z' 'a-z' fixes it.
set -euo pipefail
trap 'echo FAIL: probe 03-uuidgen failed at line $LINENO' ERR

PROBE="03-uuidgen"
RAW="$(uuidgen)"
LC="$(printf '%s' "$RAW" | tr 'A-Z' 'a-z')"

# AC#13 regex per spec.
REGEX='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

# Verify raw is uppercase on macOS (sanity check).
case "$RAW" in
  *[A-Z]*) ;;  # expected on macOS
  *) echo "NOTE: uuidgen output not uppercase on this host: $RAW" ;;
esac

# Verify lowercased form matches regex.
if ! [[ "$LC" =~ $REGEX ]]; then
  echo "FAIL: lowercased uuid '$LC' does NOT match AC#13 regex"
  exit 1
fi

# Verify uppercased form does NOT match regex (proves the normalize step is load-bearing).
if [[ "$RAW" =~ $REGEX ]]; then
  echo "NOTE: raw uuid '$RAW' coincidentally matched regex (all-digit case); normalize-step still required defensively"
fi

echo "PASS: uuidgen='$RAW' → lc='$LC' matches AC#13 regex. Canonical: RUN_ID=\"\$(uuidgen | tr 'A-Z' 'a-z')\""
