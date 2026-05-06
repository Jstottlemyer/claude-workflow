#!/bin/bash
# Probe 01 — flock non-blocking exclusive lock
# IMPORTANT macOS finding: stock macOS does NOT ship flock; Homebrew flock IS available but the
# fd-form (`flock -nx 9` with `9>"$LOCKFILE"`) does NOT enforce mutual exclusion across processes
# on macOS in our testing — both contenders acquire fd-9 against the same inode and both succeed.
# The FILE-FORM (`flock -nx "$LOCKFILE" -c CMD`) DOES enforce mutual exclusion correctly.
# Implementation contract: use the file-form, OR use the mkdir-fallback. Avoid the fd-form.
set -euo pipefail
trap 'echo FAIL: probe 01-flock failed at line $LINENO' ERR

PROBE="01-flock"
TMPDIR="$(mktemp -d -t "${PROBE}.XXXXXX")"
trap 'rm -rf "$TMPDIR"' EXIT
LOCKFILE="$TMPDIR/lockfile"

if ! command -v flock >/dev/null 2>&1; then
  # Fallback: mkdir is atomic on local FS. Verify two-process exclusion via mkdir.
  ( mkdir "$TMPDIR/mkd.lock" && sleep 0.5 ) &
  P1=$!
  sleep 0.1
  RC=0
  if mkdir "$TMPDIR/mkd.lock" 2>/dev/null; then RC=0; else RC=$?; fi
  wait "$P1" || true
  rmdir "$TMPDIR/mkd.lock" 2>/dev/null || true
  if [ "$RC" -eq 0 ]; then
    echo "FAIL: mkdir fallback did not provide mutual exclusion"
    exit 1
  fi
  echo "PASS: flock absent on stock macOS; mkdir-as-lock fallback verified (atomic mutual exclusion)"
  exit 0
fi

# Homebrew flock present — verify FILE-FORM behavior.
flock -nx "$LOCKFILE" -c "sleep 0.5" &
P1=$!
sleep 0.1
RC=0
if flock -nx "$LOCKFILE" -c true; then RC=0; else RC=$?; fi
wait "$P1" || true

if [ "$RC" -eq 0 ]; then
  echo "FAIL: file-form flock should have failed nonblocking while first held the lock (got $RC)"
  exit 1
fi

# After P1 released, lock should be acquirable.
flock -nx "$LOCKFILE" -c true

# Cross-check: confirm the fd-form macOS gotcha is real (informational; not a fail).
( flock -nx 9 && sleep 0.5 ) 9>"$LOCKFILE" &
P2=$!
sleep 0.1
FD_RC=0
if ( flock -nx 9 -c true ) 9>"$LOCKFILE"; then FD_RC=0; else FD_RC=$?; fi
wait "$P2" || true
if [ "$FD_RC" -eq 0 ]; then
  echo "NOTE: confirmed macOS gotcha — fd-form 'flock -nx 9 ... 9>FILE' does NOT enforce exclusion (contender acquired). Implementation MUST use file-form 'flock -nx FILE -c CMD'."
fi

echo "PASS: flock file-form 'flock -nx \"\$LOCKFILE\" -c CMD' enforces mutual exclusion. Adopter contract: file-form OR mkdir-fallback; never fd-form on macOS."
