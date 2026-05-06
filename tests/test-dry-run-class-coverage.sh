#!/usr/bin/env bash
##############################################################################
# tests/test-dry-run-class-coverage.sh
#
# Validates scripts/dry-run-class-coverage.sh — the W2.5 deadlock mitigation
# for the W3 batch class-tagging splice. Confirms it correctly classifies
# personas as PASS / MISSING_BLOCK / STALE_BLOCK / NOT_APPLICABLE and emits
# valid JSONL on stdout.
#
# Asserts:
#   1. Live-tree run exits 1 (some MISSING_BLOCK) post-W2.2.
#   2. review/scope is reported PASS.
#   3. judge and synthesis are reported NOT_APPLICABLE.
#   4. Synthetic STALE_BLOCK fixture triggers exit 2.
#   5. stdout is valid JSONL (every line parseable as JSON).
#
# Bash 3.2 compatible. macOS-friendly.
##############################################################################
set -uo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ENGINE_DIR/scripts/dry-run-class-coverage.sh"

PASS=0
FAIL=0
FAILED=()

note_pass() {
  PASS=$(( PASS + 1 ))
  echo "  PASS — $1"
}

note_fail() {
  FAIL=$(( FAIL + 1 ))
  FAILED+=("$1")
  echo "  FAIL — $1"
}

if [ ! -x "$SCRIPT" ]; then
  echo "  FAIL — script missing or not executable: $SCRIPT"
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

##############################################################################
# Test 1: live-tree run reports MISSING_BLOCK and exits 1
##############################################################################
TMP_OUT="$(mktemp -t dryrun-cov-out.XXXXXX)"
TMP_ERR="$(mktemp -t dryrun-cov-err.XXXXXX)"
trap 'rm -f "$TMP_OUT" "$TMP_ERR"' EXIT

LIVE_EXIT=0
"$SCRIPT" >"$TMP_OUT" 2>"$TMP_ERR" || LIVE_EXIT=$?

# W3.2: post-splice the live tree should be 0 (all spliced or not-applicable).
# Pre-W3.2 (during W2 parallel waves) it would be 1. Accept either; what matters
# is that the script ran cleanly and produced JSONL output.
case "$LIVE_EXIT" in
  0) note_pass "live tree exits 0 (post-W3.2 splice complete; all PASS or NOT_APPLICABLE)" ;;
  1) note_pass "live tree exits 1 (pre-W3.2; some MISSING_BLOCK present)" ;;
  *) note_fail "live tree exited $LIVE_EXIT (expected 0 post-splice or 1 pre-splice)" ;;
esac

# Pre-/post-splice the script must always emit at least one record total; the
# breakdown depends on splice progress.
total_records="$(grep -c '"status":' "$TMP_OUT" || true)"
if [ "${total_records:-0}" -gt 0 ]; then
  note_pass "live tree produced $total_records persona status records"
else
  note_fail "no status records found in stdout"
fi

##############################################################################
# Test 2: review/scope appears in output (status depends on whether W2.2 has
# spliced it yet — accept either PASS post-W2.2 or MISSING_BLOCK pre-W2.2,
# since W2.2 and W2.5 run in parallel waves).
##############################################################################
scope_line="$(grep '"persona": "review/scope"' "$TMP_OUT" || true)"
if [ -z "$scope_line" ]; then
  note_fail "review/scope not present in output at all"
else
  case "$scope_line" in
    *'"status": "PASS"'*)
      note_pass "review/scope reported PASS (W2.2 splice present)"
      ;;
    *'"status": "MISSING_BLOCK"'*)
      note_pass "review/scope reported MISSING_BLOCK (W2.2 not yet merged in live tree; expected during parallel waves)"
      ;;
    *)
      note_fail "review/scope reported unexpected status: $scope_line"
      ;;
  esac
fi

##############################################################################
# Test 2b: dedicated PASS-case fixture — synthetic spliced persona that exactly
# matches the canonical template should report PASS and exit 0.
##############################################################################
PASSROOT="$(mktemp -d -t dryrun-cov-pass.XXXXXX)"
mkdir -p "$PASSROOT/scripts"
mkdir -p "$PASSROOT/personas/_templates"
mkdir -p "$PASSROOT/personas/review"
cp "$ENGINE_DIR/personas/_templates/class-tagging.md" \
   "$PASSROOT/personas/_templates/class-tagging.md"
cp "$SCRIPT" "$PASSROOT/scripts/dry-run-class-coverage.sh"
chmod +x "$PASSROOT/scripts/dry-run-class-coverage.sh"

# Synthetic persona: a header line + the canonical template body verbatim
{
  echo "# Synthetic Spliced Persona"
  echo ""
  cat "$ENGINE_DIR/personas/_templates/class-tagging.md"
  echo ""
} >"$PASSROOT/personas/review/scope.md"
echo "# Judge stub" >"$PASSROOT/personas/judge.md"
echo "# Synthesis stub" >"$PASSROOT/personas/synthesis.md"

PASS_OUT="$(mktemp -t dryrun-cov-pass-out.XXXXXX)"
PASS_ERR="$(mktemp -t dryrun-cov-pass-err.XXXXXX)"
PASS_EXIT=0
"$PASSROOT/scripts/dry-run-class-coverage.sh" --gate spec-review \
  >"$PASS_OUT" 2>"$PASS_ERR" || PASS_EXIT=$?

if [ "$PASS_EXIT" -eq 0 ]; then
  note_pass "synthetic PASS fixture exits 0"
else
  note_fail "synthetic PASS fixture expected exit 0, got $PASS_EXIT"
  echo "  --- stdout ---" >&2; cat "$PASS_OUT" >&2
  echo "  --- stderr ---" >&2; cat "$PASS_ERR" >&2
fi

if grep -q '"persona": "review/scope", "status": "PASS"' "$PASS_OUT"; then
  note_pass "synthetic spliced persona reported PASS"
else
  note_fail "synthetic spliced persona not reported PASS"
fi

rm -f "$PASS_OUT" "$PASS_ERR"
rm -rf "$PASSROOT"

##############################################################################
# Test 3: judge and synthesis are NOT_APPLICABLE
##############################################################################
if grep -q '"persona": "judge", "status": "NOT_APPLICABLE"' "$TMP_OUT"; then
  note_pass "judge reported NOT_APPLICABLE"
else
  note_fail "judge not reported NOT_APPLICABLE"
fi

if grep -q '"persona": "synthesis", "status": "NOT_APPLICABLE"' "$TMP_OUT"; then
  note_pass "synthesis reported NOT_APPLICABLE"
else
  note_fail "synthesis not reported NOT_APPLICABLE"
fi

##############################################################################
# Test 4: synthetic STALE_BLOCK fixture triggers exit 2
#
# Strategy: build an isolated PERSONAS_DIR mirror that contains:
#   - _templates/class-tagging.md (real template)
#   - review/scope.md (a synthetic spliced persona with MUTATED block content)
#   - judge.md, synthesis.md (so NOT_APPLICABLE accounting still works)
# Then point the script at it via a shim — the script reads PERSONAS_DIR
# relative to its own location, so we copy the script into the tmpdir as well.
##############################################################################
TMPROOT="$(mktemp -d -t dryrun-cov-stale.XXXXXX)"
mkdir -p "$TMPROOT/scripts"
mkdir -p "$TMPROOT/personas/_templates"
mkdir -p "$TMPROOT/personas/review"

# Copy the real template
cp "$ENGINE_DIR/personas/_templates/class-tagging.md" \
   "$TMPROOT/personas/_templates/class-tagging.md"

# Copy the script
cp "$SCRIPT" "$TMPROOT/scripts/dry-run-class-coverage.sh"
chmod +x "$TMPROOT/scripts/dry-run-class-coverage.sh"

# Synthetic persona: BEGIN/END sentinels present but content mutated
cat >"$TMPROOT/personas/review/scope.md" <<'STALE_PERSONA'
# Synthetic Stale Persona

Some persona body.

<!-- BEGIN class-tagging -->
This is mutated stale content that does NOT match the canonical template.
It just contains a few words instead of the real instruction body.
<!-- END class-tagging -->

More body.
STALE_PERSONA

# NOT_APPLICABLE stubs so the script has at least one NA case
echo "# Judge stub" >"$TMPROOT/personas/judge.md"
echo "# Synthesis stub" >"$TMPROOT/personas/synthesis.md"

STALE_OUT="$(mktemp -t dryrun-cov-stale-out.XXXXXX)"
STALE_ERR="$(mktemp -t dryrun-cov-stale-err.XXXXXX)"
STALE_EXIT=0
"$TMPROOT/scripts/dry-run-class-coverage.sh" --gate spec-review \
  >"$STALE_OUT" 2>"$STALE_ERR" || STALE_EXIT=$?

if [ "$STALE_EXIT" -eq 2 ]; then
  note_pass "synthetic STALE fixture exits 2"
else
  note_fail "synthetic STALE fixture expected exit 2, got $STALE_EXIT"
  echo "  --- stdout ---" >&2
  cat "$STALE_OUT" >&2
  echo "  --- stderr ---" >&2
  cat "$STALE_ERR" >&2
fi

if grep -q '"persona": "review/scope", "status": "STALE_BLOCK"' "$STALE_OUT"; then
  note_pass "synthetic persona reported STALE_BLOCK with reason"
else
  note_fail "synthetic persona not reported STALE_BLOCK"
fi

rm -f "$STALE_OUT" "$STALE_ERR"
rm -rf "$TMPROOT"

##############################################################################
# Test 5: stdout is valid JSONL
##############################################################################
if python3 -c "import json,sys
ok = 0
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    json.loads(line)
    ok += 1
print(ok)" <"$TMP_OUT" >/dev/null 2>&1; then
  note_pass "stdout is valid JSONL (every line parses as JSON)"
else
  note_fail "stdout failed JSONL parse"
  echo "  --- offending stdout ---" >&2
  cat "$TMP_OUT" >&2
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed:"
  for f in "${FAILED[@]}"; do
    echo "  - $f"
  done
  exit 1
fi
exit 0
