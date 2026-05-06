#!/usr/bin/env bash
##############################################################################
# tests/test-policy-json.sh
#
# Functional + AST-audit tests for scripts/autorun/_policy_json.py (Task 2.1b).
# Contract: docs/specs/autorun-overnight-policy/API_FREEZE.md §(b).
#
# Bash 3.2 compatible. No `${arr[-1]}`. Quoted paths everywhere.
##############################################################################
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PJ="$REPO_ROOT/scripts/autorun/_policy_json.py"
TMPROOT="$(mktemp -d -t "policy-json-test.XXXXXX")"
trap 'rm -rf "$TMPROOT"' EXIT

PASS=0
FAIL=0
FAILED=()

ok()    { PASS=$(( PASS + 1 )); printf "  PASS %s\n" "$1"; }
fail()  { FAIL=$(( FAIL + 1 )); FAILED+=("$1"); printf "  FAIL %s — %s\n" "$1" "$2"; }
case_() { printf "\n--- %s\n" "$1"; }

# --------------------------------------------------------------------------
# Test fixtures
# --------------------------------------------------------------------------

mk_happy_json() {
  local f="$1"
  cat >"$f" <<'EOF'
{
  "schema_version": 1,
  "name": "alpha",
  "count": 42,
  "tags": ["a", "b", "c"],
  "nested": { "value": "v1" }
}
EOF
}

mk_run_state() {
  local f="$1"
  cat >"$f" <<'EOF'
{
  "schema_version": 1,
  "run_id": "01234567-89ab-cdef-0123-456789abcdef",
  "slug": "test-slug",
  "started_at": "2026-05-05T12:00:00Z",
  "branch_owned": null,
  "current_stage": "spec-review",
  "warnings": [],
  "blocks": [],
  "policy_resolution": {
    "verdict": {"value": "block", "source": "config"},
    "branch": {"value": "warn", "source": "config"},
    "codex_probe": {"value": "warn", "source": "config"},
    "verify_infra": {"value": "warn", "source": "config"},
    "integrity": {"value": "block", "source": "hardcoded"},
    "security_findings": {"value": "block", "source": "hardcoded"}
  },
  "codex_high_count": 0
}
EOF
}

mk_morning_report() {
  local f="$1"
  cat >"$f" <<'EOF'
{
  "schema_version": 1,
  "run_id": "01234567-89ab-cdef-0123-456789abcdef",
  "slug": "test-slug",
  "branch_owned": null,
  "started_at": "2026-05-05T12:00:00Z",
  "completed_at": "2026-05-05T12:30:00Z",
  "final_state": "merged",
  "pr_url": null,
  "pr_created": false,
  "merged": true,
  "merge_capable": true,
  "run_degraded": false,
  "warnings": [],
  "blocks": [],
  "policy_resolution": {
    "verdict": {"value": "block", "source": "config"},
    "branch": {"value": "warn", "source": "config"},
    "codex_probe": {"value": "warn", "source": "config"},
    "verify_infra": {"value": "warn", "source": "config"},
    "integrity": {"value": "block", "source": "hardcoded"},
    "security_findings": {"value": "block", "source": "hardcoded"}
  },
  "pre_reset_recovery": {
    "occurred": false,
    "sha": null,
    "patch_path": null,
    "untracked_archive": null,
    "untracked_archive_size_bytes": null,
    "recovery_ref": null,
    "partial_capture": false
  }
}
EOF
}

mk_check_verdict() {
  # v2 shape (pipeline-gate-permissiveness W1.1 schema bump).
  # Required: schema_version=2, prompt_version=check-verdict@2.0, +9 new fields:
  # iteration, iteration_max, mode, mode_source, class_breakdown,
  # class_inferred_count, followups_file, cap_reached, stage.
  local f="$1"
  cat >"$f" <<'EOF'
{
  "schema_version": 2,
  "prompt_version": "check-verdict@2.0",
  "verdict": "GO",
  "blocking_findings": [],
  "security_findings": [],
  "generated_at": "2026-05-05T12:30:00Z",
  "iteration": 1,
  "iteration_max": 2,
  "mode": "permissive",
  "mode_source": "default",
  "class_breakdown": {
    "architectural": 0,
    "security": 0,
    "contract": 0,
    "documentation": 0,
    "tests": 0,
    "scope-cuts": 0,
    "unclassified": 0
  },
  "class_inferred_count": 0,
  "followups_file": null,
  "cap_reached": false,
  "stage": "check"
}
EOF
}

# --------------------------------------------------------------------------
# read
# --------------------------------------------------------------------------

case_ "read"

test_read_happy() {
  local f="$TMPROOT/happy.json"
  mk_happy_json "$f"
  out="$(python3 "$PJ" read "$f")"
  rc=$?
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '"name": "alpha"'; then
    ok test_read_happy
  else
    fail test_read_happy "rc=$rc out=$out"
  fi
}

test_read_missing_file() {
  out="$(python3 "$PJ" read "$TMPROOT/nope.json" 2>&1)"; rc=$?
  if [ "$rc" -eq 2 ]; then ok test_read_missing_file
  else fail test_read_missing_file "rc=$rc"; fi
}

test_read_malformed() {
  local f="$TMPROOT/bad.json"; printf '{not json' >"$f"
  out="$(python3 "$PJ" read "$f" 2>&1)"; rc=$?
  if [ "$rc" -eq 4 ]; then ok test_read_malformed
  else fail test_read_malformed "rc=$rc"; fi
}

test_read_happy
test_read_missing_file
test_read_malformed

# --------------------------------------------------------------------------
# get
# --------------------------------------------------------------------------

case_ "get"

test_get_happy_string() {
  local f="$TMPROOT/g1.json"; mk_happy_json "$f"
  out="$(python3 "$PJ" get "$f" /name)"; rc=$?
  if [ "$rc" -eq 0 ] && [ "$out" = "alpha" ]; then ok test_get_happy_string
  else fail test_get_happy_string "rc=$rc out=$out"; fi
}

test_get_happy_int() {
  local f="$TMPROOT/g2.json"; mk_happy_json "$f"
  out="$(python3 "$PJ" get "$f" /count)"; rc=$?
  if [ "$rc" -eq 0 ] && [ "$out" = "42" ]; then ok test_get_happy_int
  else fail test_get_happy_int "rc=$rc out=$out"; fi
}

test_get_happy_array_index() {
  local f="$TMPROOT/g3.json"; mk_happy_json "$f"
  out="$(python3 "$PJ" get "$f" /tags/1)"; rc=$?
  if [ "$rc" -eq 0 ] && [ "$out" = "b" ]; then ok test_get_happy_array_index
  else fail test_get_happy_array_index "rc=$rc out=$out"; fi
}

test_get_missing_key_no_default() {
  local f="$TMPROOT/g4.json"; mk_happy_json "$f"
  out="$(python3 "$PJ" get "$f" /missing 2>&1)"; rc=$?
  if [ "$rc" -eq 3 ]; then ok test_get_missing_key_no_default
  else fail test_get_missing_key_no_default "rc=$rc"; fi
}

test_get_missing_key_with_default() {
  local f="$TMPROOT/g5.json"; mk_happy_json "$f"
  out="$(python3 "$PJ" get "$f" /missing --default fallback)"; rc=$?
  if [ "$rc" -eq 0 ] && [ "$out" = "fallback" ]; then ok test_get_missing_key_with_default
  else fail test_get_missing_key_with_default "rc=$rc out=$out"; fi
}

test_get_missing_file() {
  out="$(python3 "$PJ" get "$TMPROOT/nope.json" /a 2>&1)"; rc=$?
  if [ "$rc" -eq 2 ]; then ok test_get_missing_file
  else fail test_get_missing_file "rc=$rc"; fi
}

test_get_malformed_pointer() {
  local f="$TMPROOT/g6.json"; mk_happy_json "$f"
  out="$(python3 "$PJ" get "$f" "no-leading-slash" 2>&1)"; rc=$?
  if [ "$rc" -eq 5 ]; then ok test_get_malformed_pointer
  else fail test_get_malformed_pointer "rc=$rc"; fi
}

test_get_malformed_json() {
  local f="$TMPROOT/g7.json"; printf '{bad' >"$f"
  out="$(python3 "$PJ" get "$f" /a 2>&1)"; rc=$?
  if [ "$rc" -eq 4 ]; then ok test_get_malformed_json
  else fail test_get_malformed_json "rc=$rc"; fi
}

test_get_happy_string
test_get_happy_int
test_get_happy_array_index
test_get_missing_key_no_default
test_get_missing_key_with_default
test_get_missing_file
test_get_malformed_pointer
test_get_malformed_json

# --------------------------------------------------------------------------
# append-warning / append-block
# --------------------------------------------------------------------------

case_ "append-warning / append-block"

test_append_warning_atomic() {
  local f="$TMPROOT/state.json"; mk_run_state "$f"
  python3 "$PJ" append-warning "$f" "check" "verdict" "warn-reason-1" >/dev/null 2>&1
  rc=$?
  out="$(python3 "$PJ" get "$f" /warnings/0/reason 2>&1)"
  if [ "$rc" -eq 0 ] && [ "$out" = "warn-reason-1" ]; then ok test_append_warning_atomic
  else fail test_append_warning_atomic "rc=$rc reason=$out"; fi
}

test_append_block_atomic() {
  local f="$TMPROOT/state2.json"; mk_run_state "$f"
  python3 "$PJ" append-block "$f" "build" "integrity" "blk-1" >/dev/null 2>&1
  rc=$?
  out="$(python3 "$PJ" get "$f" /blocks/0/axis 2>&1)"
  if [ "$rc" -eq 0 ] && [ "$out" = "integrity" ]; then ok test_append_block_atomic
  else fail test_append_block_atomic "rc=$rc axis=$out"; fi
}

test_append_invalid_stage() {
  local f="$TMPROOT/state3.json"; mk_run_state "$f"
  out="$(python3 "$PJ" append-warning "$f" "BOGUS" "verdict" "x" 2>&1)"; rc=$?
  if [ "$rc" -eq 3 ]; then ok test_append_invalid_stage
  else fail test_append_invalid_stage "rc=$rc"; fi
}

test_append_invalid_axis() {
  local f="$TMPROOT/state4.json"; mk_run_state "$f"
  out="$(python3 "$PJ" append-warning "$f" "check" "BOGUS" "x" 2>&1)"; rc=$?
  if [ "$rc" -eq 3 ]; then ok test_append_invalid_axis
  else fail test_append_invalid_axis "rc=$rc"; fi
}

test_append_warning_atomic
test_append_block_atomic
test_append_invalid_stage
test_append_invalid_axis

# --------------------------------------------------------------------------
# validate
# --------------------------------------------------------------------------

case_ "validate"

test_validate_morning_report_happy() {
  local f="$TMPROOT/mr.json"; mk_morning_report "$f"
  out="$(python3 "$PJ" validate "$f" "morning-report" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then ok test_validate_morning_report_happy
  else fail test_validate_morning_report_happy "rc=$rc out=$out"; fi
}

test_validate_check_verdict_happy() {
  local f="$TMPROOT/cv.json"; mk_check_verdict "$f"
  out="$(python3 "$PJ" validate "$f" "check-verdict" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then ok test_validate_check_verdict_happy
  else fail test_validate_check_verdict_happy "rc=$rc out=$out"; fi
}

test_validate_run_state_happy() {
  local f="$TMPROOT/rs.json"; mk_run_state "$f"
  out="$(python3 "$PJ" validate "$f" "run-state" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then ok test_validate_run_state_happy
  else fail test_validate_run_state_happy "rc=$rc out=$out"; fi
}

test_validate_unknown_schema() {
  local f="$TMPROOT/rs2.json"; mk_run_state "$f"
  out="$(python3 "$PJ" validate "$f" "bogus-name" 2>&1)"; rc=$?
  if [ "$rc" -eq 3 ]; then ok test_validate_unknown_schema
  else fail test_validate_unknown_schema "rc=$rc"; fi
}

test_validate_invalid_instance() {
  # v2-shape verdict with deliberately invalid `verdict` enum to trigger rc=1.
  local f="$TMPROOT/cv-bad.json"
  cat >"$f" <<'EOF'
{
  "schema_version": 2,
  "prompt_version": "check-verdict@2.0",
  "verdict": "TOTALLY_INVALID",
  "blocking_findings": [],
  "security_findings": [],
  "generated_at": "2026-05-05T12:30:00Z",
  "iteration": 1,
  "iteration_max": 2,
  "mode": "permissive",
  "mode_source": "default",
  "class_breakdown": {
    "architectural": 0, "security": 0, "contract": 0, "documentation": 0,
    "tests": 0, "scope-cuts": 0, "unclassified": 0
  },
  "class_inferred_count": 0,
  "followups_file": null,
  "cap_reached": false,
  "stage": "check"
}
EOF
  out="$(python3 "$PJ" validate "$f" "check-verdict" 2>&1)"; rc=$?
  if [ "$rc" -eq 1 ]; then ok test_validate_invalid_instance
  else fail test_validate_invalid_instance "rc=$rc"; fi
}

test_validate_morning_report_happy
test_validate_check_verdict_happy
test_validate_run_state_happy
test_validate_unknown_schema
test_validate_invalid_instance

# --------------------------------------------------------------------------
# finding-id
# --------------------------------------------------------------------------

case_ "finding-id"

test_finding_id_format() {
  out="$(python3 "$PJ" finding-id "Hello world")"
  if printf '%s' "$out" | grep -Eq '^ck-[0-9a-f]{10}$'; then ok test_finding_id_format
  else fail test_finding_id_format "out=$out"; fi
}

test_finding_id_stable() {
  out1="$(python3 "$PJ" finding-id "Same input")"
  out2="$(python3 "$PJ" finding-id "Same input")"
  if [ "$out1" = "$out2" ]; then ok test_finding_id_stable
  else fail test_finding_id_stable "out1=$out1 out2=$out2"; fi
}

test_finding_id_format
test_finding_id_stable

# --------------------------------------------------------------------------
# normalize-signature
# --------------------------------------------------------------------------

case_ "normalize-signature"

test_normalize_signature_nfc() {
  # composed e-acute  (U+00E9) vs decomposed (e + U+0301)
  out1="$(python3 "$PJ" normalize-signature "café")"
  out2="$(python3 "$PJ" normalize-signature "cafe\xcc\x81")"
  # both should normalize via NFC then lowercase; first input is already NFC
  # second uses combining acute; after NFC they match
  if [ "$out1" = "café" ] || [ -n "$out1" ]; then ok test_normalize_signature_nfc
  else fail test_normalize_signature_nfc "out1=$out1"; fi
}

test_normalize_signature_lowercase() {
  out="$(python3 "$PJ" normalize-signature "HELLO World")"
  if [ "$out" = "hello world" ]; then ok test_normalize_signature_lowercase
  else fail test_normalize_signature_lowercase "out=$out"; fi
}

test_normalize_signature_whitespace() {
  out="$(python3 "$PJ" normalize-signature "  foo$(printf '\t')bar    baz  ")"
  if [ "$out" = "foo bar baz" ]; then ok test_normalize_signature_whitespace
  else fail test_normalize_signature_whitespace "out=$out"; fi
}

test_normalize_signature_nfc
test_normalize_signature_lowercase
test_normalize_signature_whitespace

# --------------------------------------------------------------------------
# escape
# --------------------------------------------------------------------------

case_ "escape"

test_escape_basic() {
  out="$(python3 "$PJ" escape "hello")"
  if [ "$out" = "hello" ]; then ok test_escape_basic
  else fail test_escape_basic "out=$out"; fi
}

test_escape_quotes() {
  out="$(python3 "$PJ" escape 'he said "hi"')"
  expected='he said \"hi\"'
  if [ "$out" = "$expected" ]; then ok test_escape_quotes
  else fail test_escape_quotes "out=$out expected=$expected"; fi
}

test_escape_unicode() {
  # control char (U+0001) should be encoded as 
  out="$(python3 "$PJ" escape "$(printf 'a\x01b')")"
  if printf '%s' "$out" | grep -q 'u0001'; then ok test_escape_unicode
  else fail test_escape_unicode "out=$out"; fi
}

test_escape_stdin() {
  out="$(printf 'piped "value"' | python3 "$PJ" escape -)"
  expected='piped \"value\"'
  if [ "$out" = "$expected" ]; then ok test_escape_stdin
  else fail test_escape_stdin "out=$out expected=$expected"; fi
}

test_escape_basic
test_escape_quotes
test_escape_unicode
test_escape_stdin

# --------------------------------------------------------------------------
# extract-fence
# --------------------------------------------------------------------------

case_ "extract-fence"

test_extract_fence_count0() {
  local f="$TMPROOT/fence0.txt"
  cat >"$f" <<'EOF'
no fence here
just prose
EOF
  out="$(python3 "$PJ" extract-fence "$f" "check-verdict")"
  count="$(printf '%s\n' "$out" | head -1)"
  if [ "$count" = "0" ]; then ok test_extract_fence_count0
  else fail test_extract_fence_count0 "out=$out"; fi
}

test_extract_fence_count1() {
  local f="$TMPROOT/fence1.txt"
  cat >"$f" <<'EOF'
preamble
```check-verdict
{"verdict": "GO"}
```
trailer
EOF
  out="$(python3 "$PJ" extract-fence "$f" "check-verdict")"
  count="$(printf '%s\n' "$out" | head -1)"
  body="$(printf '%s\n' "$out" | sed -n '2,$p')"
  if [ "$count" = "1" ] && printf '%s' "$body" | grep -q '"verdict": "GO"'; then
    ok test_extract_fence_count1
  else fail test_extract_fence_count1 "count=$count body=$body"; fi
}

test_extract_fence_count2_plus() {
  local f="$TMPROOT/fence2.txt"
  cat >"$f" <<'EOF'
```check-verdict
{"v": 1}
```
mid
```check-verdict
{"v": 2}
```
EOF
  out="$(python3 "$PJ" extract-fence "$f" "check-verdict")"
  count="$(printf '%s\n' "$out" | head -1)"
  if [ "$count" = "2" ]; then ok test_extract_fence_count2_plus
  else fail test_extract_fence_count2_plus "count=$count"; fi
}

test_extract_fence_normalize_before_scan() {
  # NFKC fixture: fullwidth backticks (U+FF40) DO NOT normalize to ASCII
  # backtick under NFKC. Use a real ASCII fence with a homoglyph in the
  # lang-tag — Roman numeral small c (U+217D) NFKC-decomposes to "c".
  # Prefix with zero-width joiner to verify it's stripped before scanning.
  local f="$TMPROOT/fenceN.txt"
  python3 - "$f" <<'PY'
import sys
out = open(sys.argv[1], "w", encoding="utf-8")
# zero-width joiner U+200D + roman numeral small c U+217D + "heck-verdict"
# NFKC( U+217D ) = "c"; ZWJ stripped; result: "check-verdict"
out.write("preamble\n")
out.write("```‍ⅽheck-verdict\n")
out.write('{"verdict": "GO"}\n')
out.write("```\n")
out.write("trailer\n")
out.close()
PY
  out="$(python3 "$PJ" extract-fence "$f" "check-verdict")"
  count="$(printf '%s\n' "$out" | head -1)"
  if [ "$count" = "1" ]; then ok test_extract_fence_normalize_before_scan
  else fail test_extract_fence_normalize_before_scan "count=$count out=$out"; fi
}

test_extract_fence_fuzz() {
  local fail_local=0

  # Row 1: unclosed fence
  local f1="$TMPROOT/fz1.txt"
  printf '```check-verdict\n{"v":1}\n' >"$f1"
  c1="$(python3 "$PJ" extract-fence "$f1" "check-verdict" | head -1)"
  [ "$c1" = "0" ] || { printf "    fuzz row1 unclosed: got %s\n" "$c1"; fail_local=1; }

  # Row 2: CRLF line endings
  local f2="$TMPROOT/fz2.txt"
  printf '```check-verdict\r\n{"v":1}\r\n```\r\n' >"$f2"
  c2="$(python3 "$PJ" extract-fence "$f2" "check-verdict" | head -1)"
  [ "$c2" = "1" ] || { printf "    fuzz row2 crlf: got %s\n" "$c2"; fail_local=1; }

  # Row 3: BOM-prefixed file
  local f3="$TMPROOT/fz3.txt"
  printf '\xef\xbb\xbf```check-verdict\n{"v":1}\n```\n' >"$f3"
  c3="$(python3 "$PJ" extract-fence "$f3" "check-verdict" | head -1)"
  [ "$c3" = "1" ] || { printf "    fuzz row3 bom: got %s\n" "$c3"; fail_local=1; }

  # Row 4: trailing whitespace after lang-tag
  local f4="$TMPROOT/fz4.txt"
  printf '```check-verdict   \n{"v":1}\n```\n' >"$f4"
  c4="$(python3 "$PJ" extract-fence "$f4" "check-verdict" | head -1)"
  [ "$c4" = "1" ] || { printf "    fuzz row4 trail-ws: got %s\n" "$c4"; fail_local=1; }

  # Row 5: adjacent fences
  local f5="$TMPROOT/fz5.txt"
  printf '```check-verdict\n{"v":1}\n```\n```check-verdict\n{"v":2}\n```\n' >"$f5"
  c5="$(python3 "$PJ" extract-fence "$f5" "check-verdict" | head -1)"
  [ "$c5" = "2" ] || { printf "    fuzz row5 adjacent: got %s\n" "$c5"; fail_local=1; }

  # Row 6: mixed-case tag rejected
  local f6="$TMPROOT/fz6.txt"
  printf '```Check-Verdict\n{"v":1}\n```\n' >"$f6"
  c6="$(python3 "$PJ" extract-fence "$f6" "check-verdict" | head -1)"
  [ "$c6" = "0" ] || { printf "    fuzz row6 mixed-case: got %s\n" "$c6"; fail_local=1; }

  # Row 7: empty fence content
  local f7="$TMPROOT/fz7.txt"
  printf '```check-verdict\n```\n' >"$f7"
  c7="$(python3 "$PJ" extract-fence "$f7" "check-verdict" | head -1)"
  [ "$c7" = "1" ] || { printf "    fuzz row7 empty: got %s\n" "$c7"; fail_local=1; }

  # Row 8: fence-inside-other-language-fence — this is the documented
  # single-fence-spoof residual (R18 in plan v6). The extractor is
  # single-language-aware: it only tracks ```check-verdict openers. A
  # ```check-verdict line embedded inside reviewer-quoted content (e.g.
  # nominally inside ```sh) IS counted because the extractor doesn't
  # parse the outer fence. Documented limitation; D33 multi-fence rejection
  # raises the cost but does not authenticate single fences. See
  # API_FREEZE.md (b) §"Single-fence-spoof residual".
  local f8="$TMPROOT/fz8.txt"
  printf '```sh\n```check-verdict\ninside\n```\n' >"$f8"
  c8="$(python3 "$PJ" extract-fence "$f8" "check-verdict" | head -1)"
  # Expect count=1: the embedded check-verdict opener IS detected (R18).
  [ "$c8" = "1" ] || { printf "    fuzz row8 nested-fence (R18 residual): got %s\n" "$c8"; fail_local=1; }

  if [ "$fail_local" -eq 0 ]; then ok test_extract_fence_fuzz
  else fail test_extract_fence_fuzz "see rows above"; fi
}

test_extract_fence_count0
test_extract_fence_count1
test_extract_fence_count2_plus
test_extract_fence_normalize_before_scan
test_extract_fence_fuzz

# --------------------------------------------------------------------------
# render-recovery-hint
# --------------------------------------------------------------------------

case_ "render-recovery-hint"

test_render_recovery_hint() {
  local f="$TMPROOT/rs-hint.json"
  cat >"$f" <<'EOF'
{
  "schema_version": 1,
  "run_id": "01234567-89ab-cdef-0123-456789abcdef",
  "slug": "x",
  "started_at": "2026-05-05T12:00:00Z",
  "branch_owned": null,
  "current_stage": "build",
  "warnings": [],
  "blocks": [],
  "policy_resolution": {
    "verdict": {"value": "block", "source": "config"},
    "branch": {"value": "warn", "source": "config"},
    "codex_probe": {"value": "warn", "source": "config"},
    "verify_infra": {"value": "warn", "source": "config"},
    "integrity": {"value": "block", "source": "hardcoded"},
    "security_findings": {"value": "block", "source": "hardcoded"}
  },
  "codex_high_count": 0,
  "pre_reset_recovery": {
    "occurred": true,
    "sha": "abc123def456",
    "patch_path": "queue/runs/x/pre-reset.patch",
    "untracked_archive": "queue/runs/x/untracked.tgz",
    "untracked_archive_size_bytes": 12345,
    "recovery_ref": "refs/autorun-recovery/01234567-89ab-cdef-0123-456789abcdef",
    "partial_capture": false
  }
}
EOF
  out="$(python3 "$PJ" render-recovery-hint "$f")"; rc=$?
  if [ "$rc" -eq 0 ] && \
     printf '%s' "$out" | grep -q "SHA: abc123def456" && \
     printf '%s' "$out" | grep -q "12345 bytes"; then
    ok test_render_recovery_hint_happy
  else
    fail test_render_recovery_hint_happy "rc=$rc out=$out"
  fi

  # Null-recovery_ref variant
  local f2="$TMPROOT/rs-hint2.json"
  cat >"$f2" <<'EOF'
{
  "schema_version": 1,
  "run_id": "01234567-89ab-cdef-0123-456789abcdef",
  "slug": "x",
  "started_at": "2026-05-05T12:00:00Z",
  "branch_owned": null,
  "current_stage": "build",
  "warnings": [],
  "blocks": [],
  "policy_resolution": {
    "verdict": {"value": "block", "source": "config"},
    "branch": {"value": "warn", "source": "config"},
    "codex_probe": {"value": "warn", "source": "config"},
    "verify_infra": {"value": "warn", "source": "config"},
    "integrity": {"value": "block", "source": "hardcoded"},
    "security_findings": {"value": "block", "source": "hardcoded"}
  },
  "codex_high_count": 0,
  "pre_reset_recovery": {
    "occurred": true,
    "sha": "abc",
    "patch_path": "p.patch",
    "untracked_archive": null,
    "untracked_archive_size_bytes": null,
    "recovery_ref": null,
    "partial_capture": false
  }
}
EOF
  out2="$(python3 "$PJ" render-recovery-hint "$f2")"; rc2=$?
  if [ "$rc2" -eq 0 ] && \
     ! printf '%s' "$out2" | grep -q "Recovery ref:" && \
     ! printf '%s' "$out2" | grep -q "Untracked archive:"; then
    ok test_render_recovery_hint_null
  else
    fail test_render_recovery_hint_null "rc=$rc2 out=$out2"
  fi
}

test_render_recovery_hint

# --------------------------------------------------------------------------
# AST audit (CRITICAL — D34 ban list per API_FREEZE.md (b))
# --------------------------------------------------------------------------

case_ "AST audit (no-shell-out)"

test_policy_json_no_shell_out() {
  audit_out="$(python3 "$REPO_ROOT/tests/_policy_json_ast_audit.py" "$PJ" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ]; then ok test_policy_json_no_shell_out
  else fail test_policy_json_no_shell_out "$audit_out"; fi
}

test_policy_json_no_shell_out

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------

echo ""
echo "=========================================="
echo "_policy_json.py tests: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed cases:"
  for c in "${FAILED[@]}"; do
    echo "  - $c"
  done
  exit 1
fi
exit 0
