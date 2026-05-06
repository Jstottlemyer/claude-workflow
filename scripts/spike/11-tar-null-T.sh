#!/bin/bash
# Probe 11 — BSD tar --null -T - (NUL-delimited file list from stdin)
# Critical: this is task 3.3's untracked-archive primitive (Codex L12).
# Emit the canonical command to queue/.spike-output/tar-untracked.cmd for 3.3 to consume.
set -euo pipefail
trap 'echo FAIL: probe 11-tar-null-T failed at line $LINENO' ERR

PROBE="11-tar-null-T"
TMPDIR="$(mktemp -d -t "${PROBE}.XXXXXX")"
SPIKE_OUT_DIR=""
# Resolve repo root (script may be invoked from anywhere).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SPIKE_OUT_DIR="$REPO_ROOT/queue/.spike-output"
mkdir -p "$SPIKE_OUT_DIR"
trap 'rm -rf "$TMPDIR"' EXIT

# Build a fixture with a newline-in-path filename (SF5 robustness).
mkdir -p "$TMPDIR/src"
printf 'plain\n' > "$TMPDIR/src/plain.txt"
# Filename containing a literal newline (SF5: git ls-files -z must round-trip).
NL_NAME="$(printf 'weird\nname.txt')"
printf 'newline-in-path\n' > "$TMPDIR/src/$NL_NAME"

cd "$TMPDIR/src"
# Build a NUL-delimited file list (mimicking `git ls-files -z`).
{
  printf 'plain.txt\0'
  printf '%s\0' "$NL_NAME"
} > "$TMPDIR/files.z"

# Canonical command form (stdin):
tar --null -T - -czf "$TMPDIR/out.tgz" < "$TMPDIR/files.z"

LISTING="$(tar -tzf "$TMPDIR/out.tgz")"
COUNT="$(printf '%s\n' "$LISTING" | grep -c '.' || true)"
# Expect 2 entries.
if [ "$COUNT" -ne 2 ]; then
  echo "FAIL: expected 2 archive entries, got $COUNT"
  printf '%s\n' "$LISTING"
  exit 1
fi
if ! printf '%s\n' "$LISTING" | grep -q '^plain.txt$'; then
  echo "FAIL: plain.txt missing from archive"; exit 1
fi

# Emit the canonical command to spike-output for task 3.3 to consume per Codex L12.
cat > "$SPIKE_OUT_DIR/tar-untracked.cmd" <<'CANONICAL'
git ls-files -z --others --exclude-standard | tar --null -T - -czf "$ARCHIVE" --exclude='node_modules' --exclude='.git'
CANONICAL

echo "PASS: tar --null -T - accepts NUL-delimited file list (verified with newline-in-path fixture). Canonical command written to queue/.spike-output/tar-untracked.cmd"
