#!/usr/bin/env bash
##############################################################################
# tests/test-render-followups.sh
#
# Functional tests for scripts/render-followups.py (Wave 1 Task 1.6).
# Spec: docs/specs/pipeline-gate-permissiveness/spec.md
# Plan: docs/specs/pipeline-gate-permissiveness/plan.md
#
# Bash 3.2 compatible. No `${arr[-1]}`. No process-substitution shenanigans.
##############################################################################
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RF="$REPO_ROOT/scripts/render-followups.py"
FIX="$REPO_ROOT/tests/fixtures/permissiveness"
TMPROOT="$(mktemp -d -t "render-followups-test.XXXXXX")"
trap 'rm -rf "$TMPROOT"' EXIT

PASS=0
FAIL=0
FAILED=""

ok()    { PASS=$(( PASS + 1 )); printf "  PASS %s\n" "$1"; }
fail()  { FAIL=$(( FAIL + 1 )); FAILED="$FAILED $1"; printf "  FAIL %s — %s\n" "$1" "$2"; }
case_() { printf "\n--- %s\n" "$1"; }

# ---------------------------------------------------------------------------
# 1. Empty followups.jsonl -> "No active follow-ups." body + sentinel
# ---------------------------------------------------------------------------
case_ "1. empty followups.jsonl -> empty body sentinel"
T1="$TMPROOT/empty"
mkdir -p "$T1"
: > "$T1/followups.jsonl"
if python3 "$RF" "$T1" >/dev/null 2>"$T1/stderr"; then
    if grep -q "generated from followups.jsonl" "$T1/followups.md" \
       && grep -q "_No active follow-ups._" "$T1/followups.md"; then
        ok "empty input rendered with sentinel"
    else
        fail "empty input" "expected sentinel and 'No active follow-ups' body"
        cat "$T1/followups.md"
    fi
else
    fail "empty input" "exited non-zero: $(cat "$T1/stderr")"
fi

# ---------------------------------------------------------------------------
# 2. Single open contract row -> build-inline section, single row
# ---------------------------------------------------------------------------
case_ "2. single open contract row from v1-followup-valid.jsonl"
T2="$TMPROOT/single"
mkdir -p "$T2"
cp "$FIX/v1-followup-valid.jsonl" "$T2/followups.jsonl"
if python3 "$RF" "$T2" >/dev/null 2>"$T2/stderr"; then
    OUT="$T2/followups.md"
    if grep -q "## build-inline (1)" "$OUT" \
       && grep -q "### contract (1)" "$OUT" \
       && grep -q "sr-a1b2c3d4e5" "$OUT" \
       && grep -q "from /spec-review iter 1" "$OUT" \
       && grep -q "Open:\*\* 1" "$OUT"; then
        ok "single row rendered correctly"
    else
        fail "single row" "missing expected section/row markers"
        cat "$OUT"
    fi
else
    fail "single row" "exited non-zero: $(cat "$T2/stderr")"
fi

# ---------------------------------------------------------------------------
# 3. Mixed states (open + addressed + superseded) -> only open shown; counts
# ---------------------------------------------------------------------------
case_ "3. mixed states: only open shown; counts reflect all three"
T3="$TMPROOT/mixed"
mkdir -p "$T3"
# Build a 3-row JSONL: 1 open, 1 addressed, 1 superseded.
cat "$FIX/v1-followup-valid.jsonl" > "$T3/followups.jsonl"
cat "$FIX/v1-followup-addressed.jsonl" >> "$T3/followups.jsonl"
# Synthesise a superseded row by mutating the addressed fixture's state.
python3 - "$T3/followups.jsonl" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fp:
    lines = [l for l in fp if l.strip()]
last = json.loads(lines[-1])
sup = dict(last)
sup["state"] = "superseded"
sup["finding_id"] = "sr-c0ffee0001"
sup["addressed_by"] = None
sup["superseded_by"] = "sr-deadbeef99"
with open(path, "a", encoding="utf-8") as fp:
    fp.write(json.dumps(sup) + "\n")
PYEOF

if python3 "$RF" "$T3" >/dev/null 2>"$T3/stderr"; then
    OUT="$T3/followups.md"
    # Only ONE finding-id should appear in body (the open row).
    # Use grep -q (boolean) rather than grep -c (count) — grep returns 1
    # on zero matches under set -uo pipefail, and `|| echo 0` produces
    # multi-line output that breaks `[ -eq ]` arithmetic on bash 3.2.
    if grep -q "sr-a1b2c3d4e5" "$OUT" \
       && ! grep -q "sr-c0ffee0001" "$OUT" \
       && grep -q "Open:\*\* 1" "$OUT" \
       && grep -q "Addressed:\*\* 1" "$OUT" \
       && grep -q "Superseded:\*\* 1" "$OUT"; then
        ok "only open rows in body; header counts cover all states"
    else
        fail "mixed states" "expected only open row visible + counts 1/1/1"
        cat "$OUT"
    fi
else
    fail "mixed states" "exited non-zero: $(cat "$T3/stderr")"
fi

# ---------------------------------------------------------------------------
# 4. Regression row -> ⚠ regressed (was addressed in <SHA[:7]>)
# ---------------------------------------------------------------------------
case_ "4. regression row renders the ⚠ regressed marker"
T4="$TMPROOT/regression"
mkdir -p "$T4"
cp "$FIX/v1-followup-regressed.jsonl" "$T4/followups.jsonl"
if python3 "$RF" "$T4" >/dev/null 2>"$T4/stderr"; then
    OUT="$T4/followups.md"
    # SHA in fixture: deadbeefcafe1234567890abcdef1234567890ab -> deadbee
    if grep -q "regressed (was addressed in deadbee)" "$OUT"; then
        ok "regression marker rendered with 7-char SHA"
    else
        fail "regression" "missing or malformed regressed marker"
        cat "$OUT"
    fi
else
    fail "regression" "exited non-zero: $(cat "$T4/stderr")"
fi

# ---------------------------------------------------------------------------
# 5. Determinism: render twice, byte-identical
# ---------------------------------------------------------------------------
case_ "5. determinism: two consecutive renders are byte-identical"
T5="$TMPROOT/determinism"
mkdir -p "$T5"
cp "$FIX/v1-followup-valid.jsonl" "$T5/followups.jsonl"
python3 "$RF" "$T5" >/dev/null 2>"$T5/stderr1" || true
cp "$T5/followups.md" "$T5/run1.md"
# Sleep a hair so any hidden wall-clock dependency would diverge.
sleep 1
python3 "$RF" "$T5" >/dev/null 2>"$T5/stderr2" || true
cp "$T5/followups.md" "$T5/run2.md"
if cmp -s "$T5/run1.md" "$T5/run2.md"; then
    ok "two renders produced byte-identical output"
else
    fail "determinism" "diff between run1 and run2"
    diff "$T5/run1.md" "$T5/run2.md" || true
fi

# ---------------------------------------------------------------------------
# 6. Architectural row (negative) -> renderer must not crash
# ---------------------------------------------------------------------------
case_ "6. architectural row hand-injected -> renderer does not crash"
T6="$TMPROOT/architectural"
mkdir -p "$T6"
cp "$FIX/v1-followup-architectural-rejected.jsonl" "$T6/followups.jsonl"
if python3 "$RF" "$T6" >/dev/null 2>"$T6/stderr"; then
    OUT="$T6/followups.md"
    # Renderer is permissive on unknown class -> sorts after known classes.
    # Acceptance: file exists, sentinel present, finding_id appears.
    if grep -q "generated from followups.jsonl" "$OUT" \
       && grep -q "sr-bad1234567" "$OUT"; then
        ok "renderer tolerated architectural-class row without crashing"
    else
        fail "architectural" "expected output content missing"
        cat "$OUT"
    fi
else
    fail "architectural" "exited non-zero: $(cat "$T6/stderr")"
fi

# ---------------------------------------------------------------------------
# 7. Missing followups.jsonl -> exit 4
# ---------------------------------------------------------------------------
case_ "7. missing followups.jsonl -> exit 4"
T7="$TMPROOT/missing"
mkdir -p "$T7"
# No followups.jsonl in T7.
python3 "$RF" "$T7" >/dev/null 2>"$T7/stderr"
RC=$?
if [ "$RC" -eq 4 ]; then
    if grep -q "no followups.jsonl" "$T7/stderr"; then
        ok "missing JSONL -> exit 4 with stderr message"
    else
        fail "missing JSONL" "exit 4 but stderr missing 'no followups.jsonl'"
    fi
else
    fail "missing JSONL" "expected exit 4, got $RC"
fi

# ---------------------------------------------------------------------------
# 7b. Missing spec-dir entirely -> exit 4
# ---------------------------------------------------------------------------
case_ "7b. nonexistent spec-dir -> exit 4"
python3 "$RF" "$TMPROOT/does-not-exist" >/dev/null 2>"$TMPROOT/stderr-nx"
RC=$?
if [ "$RC" -eq 4 ]; then
    ok "nonexistent spec-dir -> exit 4"
else
    fail "nonexistent spec-dir" "expected exit 4, got $RC"
fi

# ---------------------------------------------------------------------------
# 8. Malformed JSON -> exit 2 with stderr line-number
# ---------------------------------------------------------------------------
case_ "8. malformed JSONL row -> exit 2"
T8="$TMPROOT/malformed"
mkdir -p "$T8"
printf '%s\n' "{not valid json" > "$T8/followups.jsonl"
python3 "$RF" "$T8" >/dev/null 2>"$T8/stderr"
RC=$?
if [ "$RC" -eq 2 ] && grep -q "line 1" "$T8/stderr"; then
    ok "malformed JSON -> exit 2 with line number"
else
    fail "malformed JSON" "expected exit 2 with line-number stderr, got rc=$RC stderr=$(cat "$T8/stderr")"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf "\n=== test-render-followups.sh: %d passed, %d failed ===\n" "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
    printf "Failed:%s\n" "$FAILED"
    exit 1
fi
exit 0
