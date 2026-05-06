#!/bin/bash
# Atomic-append torture test — 2 writers × 100 iterations against a JSON-lines file
# under flock (or mkdir fallback). Assert all 200 entries present in final file; no JSON corruption.
# Validates the _policy.sh atomic-append pattern from spec lines 334-343.
set -euo pipefail
trap 'echo FAIL: atomic-append-torture failed at line $LINENO' ERR

PROBE="atomic-append-torture"
TMPDIR="$(mktemp -d -t "${PROBE}.XXXXXX")"
trap 'rm -rf "$TMPDIR"' EXIT

TARGET="$TMPDIR/findings.jsonl"
LOCK="$TMPDIR/findings.lock"
: > "$TARGET"

# Choose lock primitive: prefer flock, fall back to mkdir.
HAVE_FLOCK=0
if command -v flock >/dev/null 2>&1; then
  HAVE_FLOCK=1
fi

append_with_flock() {
  # macOS gotcha: fd-form flock does not enforce exclusion across processes.
  # Use file-form: `flock -x FILE -c CMD`.
  local writer_id="$1"
  local i
  for i in $(seq 1 100); do
    flock -x "$LOCK" -c "printf '{\"writer\":\"%s\",\"seq\":%d}\n' \"$writer_id\" \"$i\" >> \"$TARGET\""
  done
}

append_with_mkdir() {
  local writer_id="$1"
  local i
  local guard="$LOCK.d"
  for i in $(seq 1 100); do
    while ! mkdir "$guard" 2>/dev/null; do
      sleep 0.001
    done
    printf '{"writer":"%s","seq":%d}\n' "$writer_id" "$i" >> "$TARGET"
    rmdir "$guard"
  done
}

if [ "$HAVE_FLOCK" -eq 1 ]; then
  append_with_flock A &
  P1=$!
  append_with_flock B &
  P2=$!
  PRIMITIVE="flock"
else
  append_with_mkdir A &
  P1=$!
  append_with_mkdir B &
  P2=$!
  PRIMITIVE="mkdir-fallback"
fi

wait "$P1"
wait "$P2"

# Verify line count.
LINES="$(wc -l < "$TARGET" | tr -d ' ')"
if [ "$LINES" -ne 200 ]; then
  echo "FAIL: expected 200 lines, got $LINES (primitive=$PRIMITIVE)"
  exit 1
fi

# Verify every line is valid JSON (Python stdlib).
python3 - "$TARGET" <<'PY'
import sys, json
bad = 0
counts = {"A": 0, "B": 0}
with open(sys.argv[1]) as f:
    for i, line in enumerate(f, 1):
        line = line.rstrip("\n")
        try:
            obj = json.loads(line)
            counts[obj["writer"]] = counts.get(obj["writer"], 0) + 1
        except Exception as e:
            print(f"line {i} invalid: {e}: {line!r}")
            bad += 1
if bad:
    sys.exit(1)
if counts.get("A", 0) != 100 or counts.get("B", 0) != 100:
    print(f"FAIL counts: {counts}")
    sys.exit(1)
PY

echo "PASS: 2 writers × 100 atomic appends = 200 valid JSONL lines, balanced (A=100, B=100). Primitive: $PRIMITIVE"
