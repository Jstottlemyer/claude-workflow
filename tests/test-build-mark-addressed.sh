#!/usr/bin/env bash
##############################################################################
# tests/test-build-mark-addressed.sh
#
# Functional tests for scripts/build-mark-addressed.py (Wave 3 Task 3.8b).
# Spec: docs/specs/pipeline-gate-permissiveness/spec.md
# Plan: docs/specs/pipeline-gate-permissiveness/plan.md
#
# Bash 3.2 compatible. No `${arr[-1]}`. No process-substitution shenanigans.
##############################################################################
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BMA="$REPO_ROOT/scripts/build-mark-addressed.py"
FIX="$REPO_ROOT/tests/fixtures/permissiveness"
TMPROOT="$(mktemp -d -t "build-mark-addressed-test.XXXXXX")"
trap 'rm -rf "$TMPROOT"' EXIT

PASS=0
FAIL=0
FAILED=""

ok()    { PASS=$(( PASS + 1 )); printf "  PASS %s\n" "$1"; }
fail()  { FAIL=$(( FAIL + 1 )); FAILED="$FAILED $1"; printf "  FAIL %s -- %s\n" "$1" "$2"; }
case_() { printf "\n--- %s\n" "$1"; }

# Common feature slug used in tests; unrelated to live MonsterFlow features.
FEATURE="bma-test-feature"

# Helper: build a 3-row JSONL fixture (open, addressed, superseded) under
# the given fake repo-root.
setup_three_row_fixture() {
    local root="$1"
    local spec_dir="$root/docs/specs/$FEATURE"
    mkdir -p "$spec_dir"
    cat "$FIX/v1-followup-valid.jsonl" > "$spec_dir/followups.jsonl"
    cat "$FIX/v1-followup-addressed.jsonl" >> "$spec_dir/followups.jsonl"
    # Mutate the addressed fixture into a superseded row (different finding_id).
    python3 - "$spec_dir/followups.jsonl" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fp:
    lines = [l for l in fp if l.strip()]
# Patch row 2 to have a unique finding_id so it doesn't collide with row 1.
row2 = json.loads(lines[1])
row2["finding_id"] = "sr-add12345abcd"
lines[1] = json.dumps(row2) + "\n"
# Synthesise a superseded row from row 2.
sup = dict(row2)
sup["state"] = "superseded"
sup["finding_id"] = "sr-c0ffee0001"
sup["addressed_by"] = None
sup["superseded_by"] = "sr-deadbeef99"
lines.append(json.dumps(sup) + "\n")
with open(path, "w", encoding="utf-8") as fp:
    fp.writelines(lines)
PYEOF
}

# ---------------------------------------------------------------------------
# 1. Happy path: open row -> addressed; other rows untouched
# ---------------------------------------------------------------------------
case_ "1. open row marked addressed; other rows byte-identical"
T1="$TMPROOT/case1"
mkdir -p "$T1"
setup_three_row_fixture "$T1"
JSONL="$T1/docs/specs/$FEATURE/followups.jsonl"

# Snapshot rows 2 and 3 (the non-target rows) BEFORE the run.
ROW2_BEFORE="$(sed -n '2p' "$JSONL")"
ROW3_BEFORE="$(sed -n '3p' "$JSONL")"

if python3 "$BMA" --feature "$FEATURE" \
    --finding-ids "sr-a1b2c3d4e5" \
    --commit-sha "abcdef0" \
    --repo-root "$T1" >"$T1/stdout" 2>"$T1/stderr"; then

    ROW1_AFTER="$(sed -n '1p' "$JSONL")"
    ROW2_AFTER="$(sed -n '2p' "$JSONL")"
    ROW3_AFTER="$(sed -n '3p' "$JSONL")"

    if echo "$ROW1_AFTER" | grep -q '"state": "addressed"\|"state":"addressed"' \
       && echo "$ROW1_AFTER" | grep -q '"addressed_by": "abcdef0"\|"addressed_by":"abcdef0"'; then
        ok "row1 transitioned to addressed with commit SHA"
    else
        fail "row1 transition" "row1 not transitioned: $ROW1_AFTER"
    fi

    if [ "$ROW2_BEFORE" = "$ROW2_AFTER" ]; then
        ok "row2 byte-identical"
    else
        fail "row2 untouched" "row2 changed:\nBEFORE: $ROW2_BEFORE\nAFTER:  $ROW2_AFTER"
    fi

    if [ "$ROW3_BEFORE" = "$ROW3_AFTER" ]; then
        ok "row3 byte-identical"
    else
        fail "row3 untouched" "row3 changed:\nBEFORE: $ROW3_BEFORE\nAFTER:  $ROW3_AFTER"
    fi

    if grep -q "addressed: sr-a1b2c3d4e5 by abcdef0" "$T1/stdout"; then
        ok "stdout reports addressed"
    else
        fail "stdout reports addressed" "$(cat "$T1/stdout")"
    fi

    # updated_at should be different from created_at (NEW timestamp written).
    UPDATED_AT="$(python3 -c '
import json,sys
with open(sys.argv[1]) as f: row=json.loads(f.readline())
print(row["updated_at"])
' "$JSONL")"
    CREATED_AT="$(python3 -c '
import json,sys
with open(sys.argv[1]) as f: row=json.loads(f.readline())
print(row["created_at"])
' "$JSONL")"
    if [ "$UPDATED_AT" != "$CREATED_AT" ]; then
        ok "updated_at refreshed (was $CREATED_AT, now $UPDATED_AT)"
    else
        fail "updated_at refreshed" "updated_at == created_at == $UPDATED_AT"
    fi
else
    fail "happy path" "exited non-zero: $(cat "$T1/stderr")"
fi

# ---------------------------------------------------------------------------
# 2. Idempotency: re-run with same args -> exit 0, "already addressed" stderr
# ---------------------------------------------------------------------------
case_ "2. idempotency: second run on already-addressed row"
if python3 "$BMA" --feature "$FEATURE" \
    --finding-ids "sr-a1b2c3d4e5" \
    --commit-sha "abcdef0" \
    --repo-root "$T1" >"$T1/stdout2" 2>"$T1/stderr2"; then

    if grep -q "already addressed: sr-a1b2c3d4e5" "$T1/stderr2"; then
        ok "second run emits 'already addressed' to stderr"
    else
        fail "idempotency stderr" "stderr did not contain 'already addressed': $(cat "$T1/stderr2")"
    fi

    if grep -q "skip: sr-a1b2c3d4e5 (already addressed)" "$T1/stdout2"; then
        ok "second run emits skip line"
    else
        fail "idempotency stdout" "stdout missing skip line: $(cat "$T1/stdout2")"
    fi

    # addressed_by must still be the FIRST writer (abcdef0), not overwritten.
    AB="$(python3 -c '
import json,sys
with open(sys.argv[1]) as f: row=json.loads(f.readline())
print(row["addressed_by"])
' "$JSONL")"
    if [ "$AB" = "abcdef0" ]; then
        ok "addressed_by preserved across idempotent runs"
    else
        fail "addressed_by preservation" "addressed_by mutated to: $AB"
    fi
else
    fail "idempotency" "second run exited non-zero: $(cat "$T1/stderr2")"
fi

# ---------------------------------------------------------------------------
# 3. Refuse: targeting a superseded row -> exit 1
# ---------------------------------------------------------------------------
case_ "3. refuse: cannot mark superseded row addressed"
T3="$TMPROOT/case3"
mkdir -p "$T3"
setup_three_row_fixture "$T3"
SUP_ID="sr-c0ffee0001"
python3 "$BMA" --feature "$FEATURE" \
    --finding-ids "$SUP_ID" \
    --commit-sha "1234567" \
    --repo-root "$T3" >"$T3/stdout" 2>"$T3/stderr"
RC=$?
if [ "$RC" -eq 1 ]; then
    ok "exit code 1 (refuse)"
else
    fail "refuse exit code" "expected 1, got $RC"
fi
if grep -q "cannot mark superseded row addressed: $SUP_ID" "$T3/stderr"; then
    ok "stderr explains refusal"
else
    fail "refuse stderr" "stderr: $(cat "$T3/stderr")"
fi

# ---------------------------------------------------------------------------
# 4. Bad input: --commit-sha not a SHA -> exit 2
# ---------------------------------------------------------------------------
case_ "4. bad --commit-sha rejected"
T4="$TMPROOT/case4"
mkdir -p "$T4"
setup_three_row_fixture "$T4"
python3 "$BMA" --feature "$FEATURE" \
    --finding-ids "sr-a1b2c3d4e5" \
    --commit-sha "not-a-sha" \
    --repo-root "$T4" >"$T4/stdout" 2>"$T4/stderr"
RC=$?
if [ "$RC" -eq 2 ]; then
    ok "exit code 2 (bad input)"
else
    fail "bad sha exit code" "expected 2, got $RC; stderr=$(cat "$T4/stderr")"
fi
if grep -q "invalid --commit-sha" "$T4/stderr"; then
    ok "stderr explains bad SHA"
else
    fail "bad sha stderr" "stderr: $(cat "$T4/stderr")"
fi

# ---------------------------------------------------------------------------
# 5. Missing followups.jsonl: --feature points to a non-existent slug -> exit 4
# ---------------------------------------------------------------------------
case_ "5. missing followups.jsonl -> exit 4"
T5="$TMPROOT/case5"
mkdir -p "$T5"
# Note: NO docs/specs/<feature>/followups.jsonl created.
python3 "$BMA" --feature "no-such-feature" \
    --finding-ids "sr-a1b2c3d4e5" \
    --commit-sha "abcdef0" \
    --repo-root "$T5" >"$T5/stdout" 2>"$T5/stderr"
RC=$?
if [ "$RC" -eq 4 ]; then
    ok "exit code 4 (no followups)"
else
    fail "missing-jsonl exit code" "expected 4, got $RC"
fi
if grep -q "no followups.jsonl at" "$T5/stderr"; then
    ok "stderr explains missing path"
else
    fail "missing-jsonl stderr" "stderr: $(cat "$T5/stderr")"
fi

# ---------------------------------------------------------------------------
# 6. PR-ref accepted as --commit-sha
# ---------------------------------------------------------------------------
case_ "6. --commit-sha PR#123 accepted"
T6="$TMPROOT/case6"
mkdir -p "$T6"
setup_three_row_fixture "$T6"
JSONL6="$T6/docs/specs/$FEATURE/followups.jsonl"
if python3 "$BMA" --feature "$FEATURE" \
    --finding-ids "sr-a1b2c3d4e5" \
    --commit-sha "PR#123" \
    --repo-root "$T6" >"$T6/stdout" 2>"$T6/stderr"; then
    AB6="$(python3 -c '
import json,sys
with open(sys.argv[1]) as f: row=json.loads(f.readline())
print(row["addressed_by"])
' "$JSONL6")"
    if [ "$AB6" = "PR#123" ]; then
        ok "PR-ref accepted and stored"
    else
        fail "pr-ref accepted" "addressed_by=$AB6 (expected PR#123)"
    fi
else
    fail "pr-ref accepted" "exited non-zero: $(cat "$T6/stderr")"
fi

# ---------------------------------------------------------------------------
# 7. Bad finding_id format -> exit 2
# ---------------------------------------------------------------------------
case_ "7. bad --finding-ids rejected"
T7="$TMPROOT/case7"
mkdir -p "$T7"
setup_three_row_fixture "$T7"
python3 "$BMA" --feature "$FEATURE" \
    --finding-ids "not-a-finding-id" \
    --commit-sha "abcdef0" \
    --repo-root "$T7" >"$T7/stdout" 2>"$T7/stderr"
RC=$?
if [ "$RC" -eq 2 ]; then
    ok "exit code 2 (bad finding-id)"
else
    fail "bad finding-id exit code" "expected 2, got $RC"
fi

# ---------------------------------------------------------------------------
# Final tally
# ---------------------------------------------------------------------------
printf "\n=== %d passed, %d failed ===\n" "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
    printf "FAILED:%s\n" "$FAILED"
    exit 1
fi
exit 0
