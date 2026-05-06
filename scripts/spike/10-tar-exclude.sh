#!/bin/bash
# Probe 10 — BSD tar --exclude
# bsdtar (macOS default) supports --exclude=PATTERN. Verify.
set -euo pipefail
trap 'echo FAIL: probe 10-tar-exclude failed at line $LINENO' ERR

PROBE="10-tar-exclude"
TMPDIR="$(mktemp -d -t "${PROBE}.XXXXXX")"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/src/keep" "$TMPDIR/src/node_modules"
echo "keep me" > "$TMPDIR/src/keep/file.txt"
echo "exclude me" > "$TMPDIR/src/node_modules/junk.txt"
echo "top-level keep" > "$TMPDIR/src/top.txt"

cd "$TMPDIR"
tar --exclude='node_modules' -czf out.tgz -C "$TMPDIR/src" .

# Verify content.
LISTING="$(tar -tzf out.tgz)"
if echo "$LISTING" | grep -q 'node_modules'; then
  echo "FAIL: --exclude=node_modules did not exclude (found in listing)"
  echo "$LISTING"
  exit 1
fi
if ! echo "$LISTING" | grep -q 'keep/file.txt'; then
  echo "FAIL: 'keep/file.txt' missing from archive"
  echo "$LISTING"
  exit 1
fi
if ! echo "$LISTING" | grep -q 'top.txt'; then
  echo "FAIL: 'top.txt' missing from archive"
  echo "$LISTING"
  exit 1
fi

TAR_VER="$(tar --version 2>&1 | head -1)"
echo "PASS: tar --exclude=node_modules works on '$TAR_VER'. Canonical: tar --exclude='node_modules' -czf OUT -C SRC ."
