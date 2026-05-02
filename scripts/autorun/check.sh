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
# Dependency: plan.md must exist (written by plan.sh)
# ---------------------------------------------------------------------------
if [ ! -f "$ARTIFACT_DIR/plan.md" ]; then
  echo "[autorun] check: ERROR — $ARTIFACT_DIR/plan.md not found"
  echo "[autorun] check: plan.sh must complete successfully before calling check.sh"
  exit 1
fi

# ---------------------------------------------------------------------------
# AUTORUN_DRY_RUN stub mode
# ---------------------------------------------------------------------------
if [ "${AUTORUN_DRY_RUN:-0}" = "1" ]; then
  echo "[autorun] check: DRY RUN mode — skipping claude -p invocation"

  cat > "$ARTIFACT_DIR/check.md" <<'EOF'
# Check (DRY RUN)
Overall Verdict: GO WITH FIXES
**Note:** Dry-run stub.
EOF

  echo "[autorun] check: dry-run artifact written; exiting 0"
  exit 0
fi

# ---------------------------------------------------------------------------
# Autonomy directive (injected via --system-prompt)
# ---------------------------------------------------------------------------
AUTONOMY_DIRECTIVE="You are running in fully autonomous overnight mode. Run the plan checkpoint now. Write check.md to docs/specs/$SLUG/check.md and stop. Do not ask for approval or emit approval prompts."

# ---------------------------------------------------------------------------
# Build the user-message prompt
# ---------------------------------------------------------------------------
PROMPT="$(cat "$REPO_DIR/commands/check.md")

---
AUTORUN_CONTEXT:
- SLUG: $SLUG
- SPEC_FILE: $SPEC_FILE
- PLAN_FILE: $ARTIFACT_DIR/plan.md
- REVIEW_FINDINGS_FILE: $ARTIFACT_DIR/review-findings.md
- AUTORUN: 1
- MODE: headless autonomous — run the checkpoint review, write check.md, then stop. Do not ask for approval.

## Spec
$(cat "$SPEC_FILE")

## Plan
$(cat "$ARTIFACT_DIR/plan.md")

## Review Findings
$(cat "$ARTIFACT_DIR/review-findings.md")"

# ---------------------------------------------------------------------------
# Invoke claude -p with timeout; capture stderr for diagnostics
# ---------------------------------------------------------------------------
STDERR_LOG="$(mktemp "${TMPDIR:-/tmp}/autorun-check-XXXXXX.log")"
STDOUT_LOG="$(mktemp "${TMPDIR:-/tmp}/autorun-check-stdout-XXXXXX.log")"
trap 'rm -f "$STDERR_LOG" "$STDOUT_LOG"' EXIT

echo "[autorun] check: starting claude -p (timeout=${TIMEOUT_STAGE}s, slug=$SLUG)"

CLAUDE_EXIT=0
printf '%s' "$PROMPT" | timeout "$TIMEOUT_STAGE" claude -p \
    --dangerously-skip-permissions \
    --system-prompt "$AUTONOMY_DIRECTIVE" \
    --add-dir "$PROJECT_DIR" \
    >"$STDOUT_LOG" \
    2>"$STDERR_LOG" || CLAUDE_EXIT=$?

if [ "$CLAUDE_EXIT" -ne 0 ]; then
  echo "[autorun] check: FAILED (claude -p exit $CLAUDE_EXIT)"
  echo "[autorun] check: last 50 lines of stderr:"
  tail -n 50 "$STDERR_LOG" | sed 's/^/  /'
  exit 1
fi

echo "[autorun] check: claude -p exited 0"

# ---------------------------------------------------------------------------
# Artifact verification: check docs/specs/$SLUG/check.md first,
# then fall back to stdout capture
# ---------------------------------------------------------------------------
CHECK_CANONICAL="$PROJECT_DIR/docs/specs/$SLUG/check.md"

if [ -f "$CHECK_CANONICAL" ]; then
  cp "$CHECK_CANONICAL" "$ARTIFACT_DIR/check.md"
  echo "[autorun] check: check.md copied from $CHECK_CANONICAL"
else
  echo "[autorun] check: WARN — $CHECK_CANONICAL not found; capturing stdout as check content"
  if [ -s "$STDOUT_LOG" ]; then
    cp "$STDOUT_LOG" "$ARTIFACT_DIR/check.md"
    echo "[autorun] check: check.md written from stdout capture ($(wc -l < "$ARTIFACT_DIR/check.md") lines)"
  else
    echo "[autorun] check: ERROR — stdout was also empty; check.md not written"
    exit 1
  fi
fi

# Final verification
if [ ! -f "$ARTIFACT_DIR/check.md" ]; then
  echo "[autorun] check: ERROR — $ARTIFACT_DIR/check.md was not written"
  exit 1
fi

echo "[autorun] check: $ARTIFACT_DIR/check.md written ($(wc -l < "$ARTIFACT_DIR/check.md") lines)"

# ---------------------------------------------------------------------------
# NO-GO gate — exit 2 signals run.sh to halt this item and write failure.md
# ---------------------------------------------------------------------------
if grep -qi "NO-GO\|NO GO" "$ARTIFACT_DIR/check.md" 2>/dev/null; then
  echo "[autorun] check: NO-GO verdict — halting item"
  exit 2
fi

echo "[autorun] check: complete"
