#!/usr/bin/env bash
##############################################################################
# tests/test-autorun-smoke.sh
#
# Task 3.10 — autorun-overnight-policy plan v6.
#
# Integration smoke against a hand-staged minimal fixture (NOT 5.1 fixtures).
# Stages 1-2 synthetic specs in a tmpdir, runs the v6 pipeline end-to-end in
# AUTORUN_DRY_RUN=1 mode, asserts:
#   (a) sidecar extracted (not fallback-logged): check-verdict.json exists +
#       check.md does NOT contain a fenced ```check-verdict block + no
#       "legacy grep fallback" log line.
#   (b) autorun-batch.sh against 2-spec inline queue → exactly 2 separate
#       queue/runs/<run-id>/ dirs (excluding .locks, current, index.md).
#   (c) STOP-file between iterations honored: touch STOP after slug-1
#       completes (via AUTORUN_BATCH_RUN_SH wrapper). slug-2 NOT processed;
#       only 1 run-dir from that batch.
#   (d) update_stage exports propagate to subshells: a stage-script wrapper
#       captures $AUTORUN_CURRENT_STAGE in a subshell and the value is
#       non-empty.
#
# No nonce assertions (v6 dropped the nonce mechanism).
#
# Bash 3.2 compatible. No ${arr[-1]}. Quoted expansions. BSD/Linux portable.
##############################################################################
set -uo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
FAILED_NAMES=()

ok() {
  echo "  ✓ $1"
  PASS=$(( PASS + 1 ))
}

bad() {
  echo "  ✗ $1"
  FAIL=$(( FAIL + 1 ))
  FAILED_NAMES+=("$1")
}

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
for need in git python3 uuidgen mktemp; do
  if ! command -v "$need" >/dev/null 2>&1; then
    echo "✗ setup: required tool '$need' not on PATH" >&2
    exit 2
  fi
done

# ---------------------------------------------------------------------------
# tmpdir setup helper — creates a self-contained PROJECT_DIR with a real git
# repo + queue/ + N spec files.
# ---------------------------------------------------------------------------
make_project() {
  local proj="$1"
  shift
  mkdir -p "$proj/queue"
  git -C "$proj" init -q -b main
  git -C "$proj" config user.email "smoke@local"
  git -C "$proj" config user.name "Smoke Test"
  echo "# smoke" > "$proj/README.md"
  git -C "$proj" add README.md
  git -C "$proj" commit -q -m "init"
  for slug in "$@"; do
    cat > "$proj/queue/$slug.spec.md" <<SPEC
# $slug

Hand-staged minimal fixture for tests/test-autorun-smoke.sh.

## Goal
Traverse the autorun pipeline end-to-end in AUTORUN_DRY_RUN=1 mode.

## Acceptance
- All stub artifacts land under queue/$slug/.
- run-state.json + morning-report.json land under queue/runs/<run-id>/.
SPEC
  done
}

# Count run-id directories under queue/runs/, excluding .locks / current /
# index.md per autorun-batch.sh:155.
count_run_dirs() {
  local runs="$1"
  [ -d "$runs" ] || { echo 0; return 0; }
  local n=0
  for entry in "$runs"/*; do
    [ -e "$entry" ] || continue
    local base
    base="$(basename "$entry")"
    case "$base" in
      .locks|current|index.md) continue ;;
    esac
    [ -d "$entry" ] || continue
    n=$(( n + 1 ))
  done
  echo "$n"
}

# ===========================================================================
# Test (a): sidecar extracted, no legacy fallback log line
# ===========================================================================
echo "=== (a) sidecar extracted (not fallback-logged) ==="

PROJ_A="$(mktemp -d -t autorun-smoke.XXXXXX)"
cleanup_a() { rm -rf "$PROJ_A" 2>/dev/null || true; }
trap cleanup_a EXIT
make_project "$PROJ_A" "feat-a"

LOG_A="$(mktemp -t autorun-smoke-a.XXXXXX)"
EXIT_A=0
PROJECT_DIR="$PROJ_A" ENGINE_DIR="$ENGINE_DIR" \
  bash "$ENGINE_DIR/scripts/autorun/run.sh" --mode=supervised --dry-run feat-a \
  >"$LOG_A" 2>&1 || EXIT_A=$?

# Find run dir
RUN_DIR_A=""
for d in "$PROJ_A/queue/runs"/*/; do
  [ -d "$d" ] || continue
  base="$(basename "${d%/}")"
  case "$base" in .locks|current) continue ;; esac
  RUN_DIR_A="${d%/}"
  break
done

if [ -z "$RUN_DIR_A" ]; then
  bad "(a) run-dir under queue/runs/ created"
  echo "    --- run log (last 30 lines) ---"
  tail -30 "$LOG_A" | sed 's/^/    /'
else
  ok "(a) run-dir created: $(basename "$RUN_DIR_A")"
fi

# In dry-run, check.sh writes the stub fence to ARTIFACT_DIR/check.md (legacy
# behavior — see check.sh:88-99). The Phase-3 extractor (extract_and_decide)
# is bypassed in DRY_RUN — so for this assertion the meaningful path is:
# verify the dry-run stub itself contains a check-verdict fence (proves the
# SF-O5 contract that downstream extractors WOULD hit the happy path), and
# verify no "legacy grep fallback" log line appeared in the run output.
#
# Note: in dry-run, the sidecar JSON at docs/specs/<slug>/check-verdict.json
# is NOT extracted (extractor is skipped), so we relax (a) to:
#   - check.md DRY-RUN stub contains the fenced check-verdict block
#     (proves SF-O5 emission)
#   - no "DEPRECATED" / "legacy grep fallback" warning fires
CHECK_MD_A="$PROJ_A/queue/feat-a/check.md"
if [ -f "$CHECK_MD_A" ]; then
  if grep -q '^```check-verdict$' "$CHECK_MD_A"; then
    ok "(a) check.md dry-run stub contains check-verdict fence (SF-O5)"
  else
    bad "(a) check.md missing check-verdict fence (SF-O5 contract broken)"
  fi
else
  bad "(a) check.md not produced under $PROJ_A/queue/feat-a/"
fi

if grep -qi "legacy grep fallback" "$LOG_A"; then
  bad "(a) run log contains 'legacy grep fallback' — should not fire on stub fence path"
else
  ok "(a) run log does NOT contain legacy grep fallback warning"
fi

# Bonus: confirm run-state.json + morning-report.json valid (sanity for d-prep).
if [ -n "$RUN_DIR_A" ] && python3 -c "import json; json.load(open('$RUN_DIR_A/run-state.json'))" 2>/dev/null; then
  ok "(a) run-state.json is valid JSON"
else
  bad "(a) run-state.json missing or invalid"
fi

# (a)-extractor: prove that in NON-dry-run paths, a synthesis stdout containing
# a single check-verdict fence makes check.sh produce the sidecar JSON AND
# strip the fence from check.md. CHECK_TEST_MODE bypasses claude -p + parallel
# reviewers and runs only extract_and_decide against a pre-baked log.
EXTRACT_PROJ="$PROJ_A/_extract"
mkdir -p "$EXTRACT_PROJ/queue/feat-a" "$EXTRACT_PROJ/docs/specs/feat-a"
SYNTH_LOG="$(mktemp -t autorun-smoke-synth.XXXXXX)"
STUB_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$SYNTH_LOG" <<EOF
OVERALL_VERDICT: GO

# Check synthesis (test fixture)

Reviewer Verdicts: all PASS.

\`\`\`check-verdict
{"schema_version":1,"prompt_version":"check-verdict@1.0","verdict":"GO","blocking_findings":[],"security_findings":[],"generated_at":"$STUB_TS"}
\`\`\`
EOF

EXTRACT_LOG="$(mktemp -t autorun-smoke-extract.XXXXXX)"
EXTRACT_EXIT=0
SLUG=feat-a \
  QUEUE_DIR="$EXTRACT_PROJ/queue" \
  ARTIFACT_DIR="$EXTRACT_PROJ/queue/feat-a" \
  SPEC_FILE="$PROJ_A/queue/feat-a.spec.md" \
  PROJECT_DIR="$EXTRACT_PROJ" \
  CHECK_TEST_MODE=1 \
  CHECK_TEST_SYNTHESIS_FILE="$SYNTH_LOG" \
  bash "$ENGINE_DIR/scripts/autorun/check.sh" >"$EXTRACT_LOG" 2>&1 || EXTRACT_EXIT=$?

if [ "$EXTRACT_EXIT" -eq 0 ]; then
  ok "(a) check.sh CHECK_TEST_MODE extractor exited 0"
else
  bad "(a) check.sh CHECK_TEST_MODE extractor exited $EXTRACT_EXIT"
  tail -20 "$EXTRACT_LOG" | sed 's/^/    /'
fi

SIDECAR_A="$EXTRACT_PROJ/docs/specs/feat-a/check-verdict.json"
if [ -f "$SIDECAR_A" ] && python3 -c "import json; json.load(open('$SIDECAR_A'))" 2>/dev/null; then
  ok "(a) check-verdict.json sidecar extracted (valid JSON)"
else
  bad "(a) check-verdict.json sidecar missing or invalid at $SIDECAR_A"
fi

CHECK_MD_EXTRACTED="$EXTRACT_PROJ/docs/specs/feat-a/check.md"
if [ -f "$CHECK_MD_EXTRACTED" ]; then
  if grep -q '^```check-verdict$' "$CHECK_MD_EXTRACTED"; then
    bad "(a) check.md still contains check-verdict fence (should have been stripped)"
  else
    ok "(a) check.md does NOT contain check-verdict fence (stripped per D33)"
  fi
else
  bad "(a) docs/specs/feat-a/check.md not produced by extractor"
fi

if grep -qi "legacy grep fallback" "$EXTRACT_LOG"; then
  bad "(a) extractor log mentions 'legacy grep fallback' — fence path should not hit fallback"
else
  ok "(a) extractor log does NOT mention legacy grep fallback (fence path taken)"
fi

rm -f "$LOG_A" "$SYNTH_LOG" "$EXTRACT_LOG"

# ===========================================================================
# Test (b): autorun-batch.sh against 2-spec queue → 2 run-dirs
# ===========================================================================
echo ""
echo "=== (b) autorun-batch.sh × 2 specs → 2 run-dirs ==="

PROJ_B="$(mktemp -d -t autorun-smoke.XXXXXX)"
cleanup_b() { rm -rf "$PROJ_A" "$PROJ_B" 2>/dev/null || true; }
trap cleanup_b EXIT
make_project "$PROJ_B" "feat-b1" "feat-b2"

LOG_B="$(mktemp -t autorun-smoke-b.XXXXXX)"
EXIT_B=0
PROJECT_DIR="$PROJ_B" ENGINE_DIR="$ENGINE_DIR" \
  bash "$ENGINE_DIR/scripts/autorun/autorun-batch.sh" --mode=supervised --dry-run \
  >"$LOG_B" 2>&1 || EXIT_B=$?

N_B="$(count_run_dirs "$PROJ_B/queue/runs")"
if [ "$N_B" -eq 2 ]; then
  ok "(b) exactly 2 run-dirs created (got $N_B)"
else
  bad "(b) expected 2 run-dirs, got $N_B"
  echo "    queue/runs/ contents:"
  ls -1 "$PROJ_B/queue/runs" 2>/dev/null | sed 's/^/      /'
  echo "    --- batch log (last 50 lines) ---"
  tail -50 "$LOG_B" | sed 's/^/    /'
fi

# Aggregate index.md should have been rendered.
if [ -f "$PROJ_B/queue/runs/index.md" ]; then
  ok "(b) queue/runs/index.md aggregate rendered"
else
  bad "(b) queue/runs/index.md not rendered"
fi

rm -f "$LOG_B"

# ===========================================================================
# Test (c): STOP file between iterations honored
#
# Strategy: AUTORUN_BATCH_RUN_SH points at a wrapper that calls the real run.sh
# then touches queue/STOP. autorun-batch.sh checks STOP at the iteration
# boundary BEFORE invoking run.sh for slug-2 (autorun-batch.sh:170), so slug-2
# never starts → only slug-1's run-dir exists.
# ===========================================================================
echo ""
echo "=== (c) STOP between iterations honored ==="

PROJ_C="$(mktemp -d -t autorun-smoke.XXXXXX)"
cleanup_c() { rm -rf "$PROJ_A" "$PROJ_B" "$PROJ_C" 2>/dev/null || true; }
trap cleanup_c EXIT
make_project "$PROJ_C" "feat-c1" "feat-c2"

WRAPPER_C="$PROJ_C/run-wrapper.sh"
cat > "$WRAPPER_C" <<WRAP
#!/bin/bash
# Test wrapper: call real run.sh, then drop STOP after slug-c1 completes.
set -uo pipefail
RC=0
bash "$ENGINE_DIR/scripts/autorun/run.sh" "\$@" || RC=\$?
# Find the slug arg (last positional arg).
SLUG=""
for a in "\$@"; do
  case "\$a" in
    --*) : ;;
    *) SLUG="\$a" ;;
  esac
done
if [ "\$SLUG" = "feat-c1" ]; then
  touch "$PROJ_C/queue/STOP"
fi
exit \$RC
WRAP
chmod +x "$WRAPPER_C"

LOG_C="$(mktemp -t autorun-smoke-c.XXXXXX)"
EXIT_C=0
PROJECT_DIR="$PROJ_C" ENGINE_DIR="$ENGINE_DIR" \
  AUTORUN_BATCH_RUN_SH="$WRAPPER_C" \
  bash "$ENGINE_DIR/scripts/autorun/autorun-batch.sh" --mode=supervised --dry-run \
  >"$LOG_C" 2>&1 || EXIT_C=$?

N_C="$(count_run_dirs "$PROJ_C/queue/runs")"
if [ "$N_C" -eq 1 ]; then
  ok "(c) exactly 1 run-dir created (slug-c2 suppressed by STOP)"
else
  bad "(c) expected 1 run-dir (STOP suppresses slug-c2), got $N_C"
  echo "    queue/runs/ contents:"
  ls -1 "$PROJ_C/queue/runs" 2>/dev/null | sed 's/^/      /'
fi

# autorun-batch.sh should exit 3 on STOP halt.
if [ "$EXIT_C" -eq 3 ]; then
  ok "(c) autorun-batch.sh exited 3 (STOP halt)"
else
  bad "(c) expected exit 3 (STOP), got $EXIT_C"
  echo "    --- batch log (last 40 lines) ---"
  tail -40 "$LOG_C" | sed 's/^/    /'
fi

# Log should mention STOP halt at iteration boundary.
if grep -q "STOP file detected at iteration boundary" "$LOG_C"; then
  ok "(c) batch log records iteration-boundary STOP detection"
else
  bad "(c) batch log missing iteration-boundary STOP detection message"
fi

rm -f "$LOG_C"

# ===========================================================================
# Test (d): update_stage exports propagate to subshells
#
# Strategy: build a fake ENGINE_DIR with all real files symlinked EXCEPT
# scripts/autorun/risk-analysis.sh, which we override with a stub that
# captures $AUTORUN_CURRENT_STAGE in a subshell and writes it to a sentinel
# file. risk-analysis runs under the "spec-review" stage marker (see
# run.sh:740 — risk-analysis stays under spec-review umbrella) so the
# captured value should be "spec-review".
#
# This proves that update_stage()'s export traversed the
#   bash "$ENGINE_DIR/scripts/autorun/risk-analysis.sh"
# subshell hop from run.sh.
# ===========================================================================
echo ""
echo "=== (d) update_stage exports propagate to subshells ==="

PROJ_D="$(mktemp -d -t autorun-smoke.XXXXXX)"
cleanup_d() { rm -rf "$PROJ_A" "$PROJ_B" "$PROJ_C" "$PROJ_D" 2>/dev/null || true; }
trap cleanup_d EXIT
make_project "$PROJ_D" "feat-d"

SENTINEL_D="$PROJ_D/.subshell-stage.txt"

# Build fake engine dir as a sibling of the project tmpdir.
FAKE_ENGINE="$PROJ_D/_engine"
mkdir -p "$FAKE_ENGINE/scripts/autorun"
mkdir -p "$FAKE_ENGINE/personas"
mkdir -p "$FAKE_ENGINE/commands"

# Symlink all top-level engine entries into FAKE_ENGINE EXCEPT we'll override
# scripts/autorun/risk-analysis.sh below. Symlinks for VERSION + personas/ +
# commands/ are needed by run.sh + downstream scripts.
for entry in "$ENGINE_DIR"/*; do
  base="$(basename "$entry")"
  case "$base" in
    scripts) continue ;;        # rebuilt below
    queue) continue ;;          # don't shadow project queue
    .git|.claude) continue ;;
  esac
  ln -sf "$entry" "$FAKE_ENGINE/$base" 2>/dev/null || true
done

# Mirror scripts/ — symlink everything except scripts/autorun/risk-analysis.sh.
mkdir -p "$FAKE_ENGINE/scripts"
for entry in "$ENGINE_DIR/scripts"/*; do
  base="$(basename "$entry")"
  case "$base" in
    autorun) continue ;;
  esac
  ln -sf "$entry" "$FAKE_ENGINE/scripts/$base" 2>/dev/null || true
done
for entry in "$ENGINE_DIR/scripts/autorun"/*; do
  base="$(basename "$entry")"
  case "$base" in
    risk-analysis.sh) continue ;;
  esac
  ln -sf "$entry" "$FAKE_ENGINE/scripts/autorun/$base" 2>/dev/null || true
done

# Override risk-analysis.sh with a stub that captures the env in a subshell.
cat > "$FAKE_ENGINE/scripts/autorun/risk-analysis.sh" <<STUB
#!/bin/bash
# Test stub for tests/test-autorun-smoke.sh assertion (d).
# Capture \$AUTORUN_CURRENT_STAGE inside an explicit subshell — proves that
# update_stage()'s export propagated across the bash-script invocation hop.
set -uo pipefail
( echo "\${AUTORUN_CURRENT_STAGE:-<unset>}" > "$SENTINEL_D" )
# Still emit the artifact run.sh expects so the pipeline continues.
mkdir -p "\$ARTIFACT_DIR"
printf '# Risk Analysis (test stub)\n' > "\$ARTIFACT_DIR/risk-findings.md"
exit 0
STUB
chmod +x "$FAKE_ENGINE/scripts/autorun/risk-analysis.sh"

LOG_D="$(mktemp -t autorun-smoke-d.XXXXXX)"
EXIT_D=0
PROJECT_DIR="$PROJ_D" ENGINE_DIR="$FAKE_ENGINE" \
  bash "$FAKE_ENGINE/scripts/autorun/run.sh" --mode=supervised --dry-run feat-d \
  >"$LOG_D" 2>&1 || EXIT_D=$?

if [ -f "$SENTINEL_D" ]; then
  CAPTURED="$(cat "$SENTINEL_D" 2>/dev/null || echo "")"
  case "$CAPTURED" in
    spec-review)
      ok "(d) subshell saw AUTORUN_CURRENT_STAGE=spec-review"
      ;;
    "<unset>"|"")
      bad "(d) subshell saw AUTORUN_CURRENT_STAGE unset (export did not propagate)"
      ;;
    *)
      # Any non-empty stage value still proves propagation, just not the
      # specific stage we expected — record as pass with a note.
      ok "(d) subshell saw AUTORUN_CURRENT_STAGE='$CAPTURED' (export propagated)"
      ;;
  esac
else
  bad "(d) sentinel file not written — risk-analysis stub did not run"
  echo "    --- run log (last 40 lines) ---"
  tail -40 "$LOG_D" | sed 's/^/    /'
fi

rm -f "$LOG_D"

# ===========================================================================
# Final summary
# ===========================================================================
echo ""
echo "=========================================="
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed assertions:"
  for n in "${FAILED_NAMES[@]}"; do
    echo "  - $n"
  done
  exit 1
fi
exit 0
