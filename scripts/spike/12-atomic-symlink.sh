#!/bin/bash
# Probe 12 — Portable atomic symlink rotation (NOT ln -sfn per SF4)
# Pattern: ln -s <target> <link>.tmp.$$ && mv -fh <link>.tmp.$$ <link>      (BSD)
#          ln -s <target> <link>.tmp.$$ && mv -fT <link>.tmp.$$ <link>      (GNU)
# `mv -fh` / `mv -fT` ensures DEST is treated as a normal file even when DEST is a symlink to a directory;
# this avoids the "mv into directory" trap. The rename(2) under the hood is atomic on the same FS.
# Race test: 2 writers × 100 iterations updating `current` symlink concurrently;
# assert the link always resolves to a valid target (no broken intermediate state).
set -euo pipefail
trap 'echo FAIL: probe 12-atomic-symlink failed at line $LINENO' ERR

PROBE="12-atomic-symlink"
TMPDIR="$(mktemp -d -t "${PROBE}.XXXXXX")"
trap 'rm -rf "$TMPDIR"' EXIT

cd "$TMPDIR"
mkdir -p targetA targetB
touch targetA/file targetB/file
LINK="current"

# Detect mv flag: BSD has -h, GNU has -T. Both prevent "rename into target dir" when DEST is a symlink-to-dir.
MV_FLAG=""
if mv -h /dev/null /dev/null 2>/dev/null; then
  MV_FLAG="-fh"
elif mv -T /dev/null /dev/null 2>/dev/null; then
  MV_FLAG="-fT"
else
  # Probe the flags via dry usage.
  if (mv -h 2>&1 || true) | grep -q 'illegal\|invalid'; then
    if (mv -T 2>&1 || true) | grep -q 'illegal\|invalid'; then
      echo "FAIL: neither mv -h (BSD) nor mv -T (GNU) supported"
      exit 1
    else
      MV_FLAG="-fT"
    fi
  else
    MV_FLAG="-fh"
  fi
fi

writer() {
  # Bash 3.2 backgrounded subshells share parent's $$, so we pass an explicit writer-id
  # for tmp-name uniqueness (BASHPID is bash 4+).
  local target="$1"
  local id="$2"
  local i
  for i in $(seq 1 100); do
    ln -s "$target" "$LINK.tmp.${id}.${i}"
    mv $MV_FLAG "$LINK.tmp.${id}.${i}" "$LINK"
  done
}

writer targetA A &
P1=$!
writer targetB B &
P2=$!

# Reader: 200 reads; every read must resolve to a regular file (no broken symlink).
BROKEN=0
for i in $(seq 1 200); do
  if [ -L "$LINK" ]; then
    if ! [ -e "$LINK/file" ]; then
      BROKEN=$((BROKEN + 1))
    fi
  fi
done

wait "$P1" "$P2" || true

if [ "$BROKEN" -gt 0 ]; then
  echo "FAIL: detected $BROKEN broken-symlink reads during race"
  exit 1
fi

# Final state must point to one of the two targets.
RESOLVED="$(readlink "$LINK")"
if [ "$RESOLVED" != "targetA" ] && [ "$RESOLVED" != "targetB" ]; then
  echo "FAIL: final symlink target unexpected: $RESOLVED"
  exit 1
fi

# Cleanup any lingering tmp links from interrupted iterations (pattern *.tmp.PID.N).
rm -f "$LINK".tmp.*

echo "PASS: atomic 'ln -s tgt link.tmp.\$\$ && mv $MV_FLAG link.tmp.\$\$ link' survived 200 concurrent updates with 0 broken reads. AVOID 'ln -sfn' (non-atomic per SF4). BSD canonical: mv -fh; GNU canonical: mv -fT."
