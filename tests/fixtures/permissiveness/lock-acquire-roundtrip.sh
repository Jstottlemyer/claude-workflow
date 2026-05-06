#!/usr/bin/env bash
# lock-acquire-roundtrip.sh — proves scripts/_followups_lock.py acquires,
# writes audit metadata, and that kernel auto-cleanup releases the lock
# when the holding process is killed (per spec.md Edge Case 14 and plan
# §Cross-cutting decision #3 "Lock primitive").
#
# Steps:
#   1. Background-spawn an acquirer; capture its PID.
#   2. Wait for "acquired ..." stdout line so we know the lock is held.
#   3. Read the lock file and assert {pid, hostname, started_at} fields.
#   4. SIGKILL the holder.
#   5. Acquire again with a tight 5s timeout — if kernel auto-cleanup
#      worked, this returns quickly; if it didn't, this would time out.
#   6. Cleanup.
#
# Exit codes: 0 = pass, non-zero = fail (with diagnostic on stderr).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LOCK_PY="${REPO_ROOT}/scripts/_followups_lock.py"
LOCK_PATH="${TMPDIR:-/tmp}/mf-lock-roundtrip-$$.lock"
HOLDER_LOG="${TMPDIR:-/tmp}/mf-lock-roundtrip-$$.log"

cleanup() {
    if [[ -n "${HOLDER_PID:-}" ]] && kill -0 "$HOLDER_PID" 2>/dev/null; then
        kill -KILL "$HOLDER_PID" 2>/dev/null || true
    fi
    rm -f "$LOCK_PATH" "$HOLDER_LOG" || true
}
trap cleanup EXIT

if [[ ! -f "$LOCK_PY" ]]; then
    echo "FAIL: $LOCK_PY not found" >&2
    exit 1
fi

# Step 1: background-spawn acquirer.
python3 "$LOCK_PY" acquire "$LOCK_PATH" --blocking >"$HOLDER_LOG" 2>&1 &
HOLDER_PID=$!

# Step 2: wait up to 5s for the "acquired" line.
for _ in $(seq 1 50); do
    if grep -q "^acquired " "$HOLDER_LOG" 2>/dev/null; then
        break
    fi
    sleep 0.1
done
if ! grep -q "^acquired " "$HOLDER_LOG" 2>/dev/null; then
    echo "FAIL: acquirer did not report 'acquired' within 5s" >&2
    echo "--- holder log ---" >&2
    cat "$HOLDER_LOG" >&2 || true
    exit 1
fi

# Step 3: assert audit metadata fields.
python3 - "$LOCK_PATH" <<'PY'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    d = json.loads(f.read().strip())
for k in ("pid", "hostname", "started_at"):
    assert k in d, "missing field: %s; got %r" % (k, d)
assert isinstance(d["pid"], int) and d["pid"] > 0, "bad pid: %r" % d["pid"]
assert isinstance(d["hostname"], str) and d["hostname"], "bad hostname: %r" % d["hostname"]
assert d["started_at"].endswith("Z"), "started_at not ISO-8601 UTC: %r" % d["started_at"]
PY

# Step 4: SIGKILL the holder. Kernel must auto-release the flock.
kill -KILL "$HOLDER_PID"
wait "$HOLDER_PID" 2>/dev/null || true
HOLDER_PID=""

# Step 5: re-acquire with tight timeout. If kernel cleanup failed, this
# would block until the 5s deadline and exit non-zero.
python3 "$LOCK_PY" acquire "$LOCK_PATH" --timeout=5 >"$HOLDER_LOG" 2>&1 &
HOLDER_PID2=$!
for _ in $(seq 1 50); do
    if grep -q "^acquired " "$HOLDER_LOG" 2>/dev/null; then
        break
    fi
    sleep 0.1
done
if ! grep -q "^acquired " "$HOLDER_LOG" 2>/dev/null; then
    echo "FAIL: re-acquire after SIGKILL did not succeed within 5s" >&2
    echo "--- holder log ---" >&2
    cat "$HOLDER_LOG" >&2 || true
    kill -KILL "$HOLDER_PID2" 2>/dev/null || true
    exit 1
fi

# Tear down second holder.
kill -KILL "$HOLDER_PID2" 2>/dev/null || true
wait "$HOLDER_PID2" 2>/dev/null || true
HOLDER_PID=""

echo "PASS: lock-acquire-roundtrip"
