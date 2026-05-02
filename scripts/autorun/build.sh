#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$REPO_DIR}"
source "$REPO_DIR/scripts/autorun/defaults.sh"

# ---------------------------------------------------------------------------
# Validate required env vars (set by run.sh before calling this script)
# ---------------------------------------------------------------------------
: "${SLUG:?SLUG must be set by run.sh}"
: "${QUEUE_DIR:?QUEUE_DIR must be set by run.sh}"
: "${ARTIFACT_DIR:?ARTIFACT_DIR must be set by run.sh}"
: "${SPEC_FILE:?SPEC_FILE must be set by run.sh}"

mkdir -p "$ARTIFACT_DIR"

# ---------------------------------------------------------------------------
# AUTORUN_DRY_RUN stub mode
# ---------------------------------------------------------------------------
if [ "${AUTORUN_DRY_RUN:-0}" = "1" ]; then
  echo "[autorun] build: DRY RUN mode — skipping claude -p invocation"

  {
    echo "## Wave 1 — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    echo "Build wave 1 (DRY RUN) — stub commit"
    echo ""
  } > "$ARTIFACT_DIR/build-log.md"

  echo "[autorun] build: dry-run stub artifact written; exiting 0"
  exit 0
fi

# ---------------------------------------------------------------------------
# Autonomy directive (injected via --system-prompt)
# ---------------------------------------------------------------------------
AUTONOMY_DIRECTIVE="You are running in fully autonomous overnight mode. At every decision point, pick the safest reversible option and execute. Do not ask for approval. Do not pause for user input. Implement all tasks from the plan and commit each wave."

# ---------------------------------------------------------------------------
# Pre-build SHA capture (write-once invariant)
# ---------------------------------------------------------------------------
PRE_BUILD_SHA_FILE="$ARTIFACT_DIR/pre-build-sha.txt"
if [ ! -f "$PRE_BUILD_SHA_FILE" ]; then
  git -C "$PROJECT_DIR" rev-parse HEAD > "$PRE_BUILD_SHA_FILE"
fi
PRE_BUILD_SHA="$(cat "$PRE_BUILD_SHA_FILE")"

echo "[autorun] build: pre-build SHA = $PRE_BUILD_SHA"

# ---------------------------------------------------------------------------
# Timestamps and paths
# ---------------------------------------------------------------------------
BUILD_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STDERR_LOG="$(mktemp "${TMPDIR:-/tmp}/autorun-build-XXXXXX.log")"
trap 'rm -f "$STDERR_LOG"' EXIT

# ---------------------------------------------------------------------------
# State JSON helper (atomic write)
# ---------------------------------------------------------------------------
update_state() {
  local stage="$1" wave="$2"
  local tmp
  tmp="$(mktemp "$ARTIFACT_DIR/state.XXXXXX.json")"
  cat > "$tmp" << STATE_EOF
{"stage": "$stage", "wave": $wave, "pre_build_sha": "$PRE_BUILD_SHA", "started_at": "$BUILD_STARTED_AT", "pid": $$}
STATE_EOF
  mv "$tmp" "$ARTIFACT_DIR/state.json"
}

# ---------------------------------------------------------------------------
# failure.md writer
# ---------------------------------------------------------------------------
write_failure_md() {
  local exit_code="${1:-1}"
  cat > "$ARTIFACT_DIR/failure.md" << FAIL_EOF
<!-- autorun:stage=build slug=$SLUG wave=$ATTEMPT exit_code=$exit_code -->
# Failure: $SLUG

**Stage:** build (attempt $ATTEMPT of $BUILD_MAX_RETRIES)
**Branch:** autorun/$SLUG
**Pre-build SHA:** $PRE_BUILD_SHA
**Retry count:** $ATTEMPT of $BUILD_MAX_RETRIES
**Timestamp:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Error
$(tail -n 50 "$STDERR_LOG" 2>/dev/null || echo "(no stderr captured)")

## Re-queue
\`\`\`
rm $ARTIFACT_DIR/failure.md && cp docs/specs/$SLUG/spec.md queue/$SLUG.spec.md
\`\`\`
FAIL_EOF
}

# ---------------------------------------------------------------------------
# Build retry loop
# ---------------------------------------------------------------------------
ATTEMPT=1
BUILD_SUCCESS=0

while [ "$ATTEMPT" -le "$BUILD_MAX_RETRIES" ]; do

  # -- STOP file check (before each attempt) ---------------------------------
  if [ -f "$QUEUE_DIR/STOP" ]; then
    echo "[autorun] build: STOP file detected — halting after clean state"
    exit 3
  fi

  # -- State update ----------------------------------------------------------
  update_state "build" "$ATTEMPT"

  # -- Wave header in build-log.md ------------------------------------------
  {
    echo "## Wave $ATTEMPT — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
  } >> "$ARTIFACT_DIR/build-log.md"

  echo "[autorun] build: starting attempt $ATTEMPT of $BUILD_MAX_RETRIES (timeout=${TIMEOUT_STAGE}s, slug=$SLUG)"

  # -- Build prompt ----------------------------------------------------------
  BUILD_PROMPT="$(cat "$REPO_DIR/commands/build.md")

---
AUTORUN_CONTEXT:
- SLUG: $SLUG
- SPEC_FILE: $SPEC_FILE
- PLAN_FILE: $ARTIFACT_DIR/plan.md
- CHECK_FILE: $ARTIFACT_DIR/check.md
- AUTORUN: 1
- BUILD_ATTEMPT: $ATTEMPT of $BUILD_MAX_RETRIES
- MODE: headless autonomous — implement all tasks and commit each wave. Do not ask for approval.

$(cat "$ARTIFACT_DIR/check.md" 2>/dev/null || echo "(no check.md found)")"

  # -- Invoke claude -p -------------------------------------------------------
  # Clear stderr log before each attempt so failure.md shows the latest errors.
  > "$STDERR_LOG"

  CLAUDE_EXIT=0
  printf '%s' "$BUILD_PROMPT" | timeout "$TIMEOUT_STAGE" claude -p \
    --dangerously-skip-permissions \
    --system-prompt "$AUTONOMY_DIRECTIVE" \
    --add-dir "$PROJECT_DIR" \
    2>"$STDERR_LOG" | tee -a "$ARTIFACT_DIR/build-log.md" || CLAUDE_EXIT=${PIPESTATUS[0]}

  if [ "$CLAUDE_EXIT" -ne 0 ]; then
    echo "[autorun] build: claude -p exited $CLAUDE_EXIT on attempt $ATTEMPT"
    ATTEMPT=$(( ATTEMPT + 1 ))
    continue
  fi

  echo "[autorun] build: claude -p exited 0 on attempt $ATTEMPT"

  # -- Test command (if configured) ------------------------------------------
  TESTS_PASSED=1
  TEST_CMD="${TEST_CMD:-}"
  if [ -n "$TEST_CMD" ]; then
    echo "[autorun] build: running test_cmd: $TEST_CMD"
    if eval "$TEST_CMD"; then
      echo "[autorun] build: tests PASSED"
      TESTS_PASSED=1
    else
      echo "[autorun] build: tests FAILED (attempt $ATTEMPT)"
      TESTS_PASSED=0
    fi
  else
    echo "[autorun] build: no test_cmd configured — skipping tests"
    TESTS_PASSED=1
  fi

  if [ "$TESTS_PASSED" -eq 1 ]; then
    BUILD_SUCCESS=1
    break
  fi

  ATTEMPT=$(( ATTEMPT + 1 ))

done

# ---------------------------------------------------------------------------
# Handle exhausted retries
# ---------------------------------------------------------------------------
if [ "$BUILD_SUCCESS" -ne 1 ]; then
  echo "[autorun] build: exhausted $BUILD_MAX_RETRIES retries — rolling back to pre-build SHA $PRE_BUILD_SHA"

  git -C "$PROJECT_DIR" reset --hard "$PRE_BUILD_SHA"

  # Remote cleanup — close any open PR
  if [ -f "$ARTIFACT_DIR/pr-url.txt" ]; then
    PR_URL="$(cat "$ARTIFACT_DIR/pr-url.txt")"
    gh pr close "$PR_URL" 2>/dev/null \
      && echo "[autorun] build: closed PR $PR_URL" \
      || echo "[autorun] build: WARN — could not close PR $PR_URL (may already be closed)"
  fi

  # Delete remote branch
  git -C "$PROJECT_DIR" push origin --delete "autorun/$SLUG" 2>/dev/null \
    && echo "[autorun] build: deleted remote branch autorun/$SLUG" \
    || true

  write_failure_md 1
  echo "[autorun] build: failure.md written to $ARTIFACT_DIR/failure.md"
  exit 1
fi

# ---------------------------------------------------------------------------
# Success path
# ---------------------------------------------------------------------------
update_state "build_complete" "$ATTEMPT"
echo "[autorun] build: complete (attempt $ATTEMPT of $BUILD_MAX_RETRIES)"
