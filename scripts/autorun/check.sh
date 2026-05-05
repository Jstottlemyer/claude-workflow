#!/bin/bash
# scripts/autorun/check.sh
#
# Parallel check: one claude -p per checkpoint persona, all launched concurrently.
# Phase 1: 5 parallel reviewer calls (no --add-dir; plan+spec passed inline).
# Phase 2: 1 synthesis call that reads raw reviewer outputs → final check.md + GO/NO-GO.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$REPO_DIR}"
source "$REPO_DIR/scripts/autorun/defaults.sh"

: "${SLUG:?SLUG must be set by run.sh}"
: "${QUEUE_DIR:?QUEUE_DIR must be set by run.sh}"
: "${ARTIFACT_DIR:?ARTIFACT_DIR must be set by run.sh}"
: "${SPEC_FILE:?SPEC_FILE must be set by run.sh}"

mkdir -p "$ARTIFACT_DIR"

CHECK_DIR="$PROJECT_DIR/docs/specs/$SLUG/check"
RAW_DIR="$CHECK_DIR/raw"
mkdir -p "$RAW_DIR"

# ---------------------------------------------------------------------------
# Dependency: plan.md must exist
# ---------------------------------------------------------------------------
if [ ! -f "$ARTIFACT_DIR/plan.md" ]; then
  echo "[autorun] check: ERROR — $ARTIFACT_DIR/plan.md not found" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# DRY RUN stub
# ---------------------------------------------------------------------------
if [ "${AUTORUN_DRY_RUN:-0}" = "1" ]; then
  echo "[autorun] check: DRY RUN — writing stub artifact"
  cat > "$ARTIFACT_DIR/check.md" <<'EOF'
# Check (DRY RUN)
Overall Verdict: GO WITH FIXES
**Note:** Dry-run stub.
EOF
  exit 0
fi

AUTONOMY_DIRECTIVE="You are running in fully autonomous overnight mode. At every decision point, pick the safest reversible option and execute. Do not ask for approval. Do not pause for user input. Proceed immediately."

SPEC_CONTENT="$(cat "$SPEC_FILE")"
PLAN_CONTENT="$(cat "$ARTIFACT_DIR/plan.md")"

# Discover check personas from disk
PERSONA_FILES=()
while IFS= read -r -d '' f; do
  PERSONA_FILES+=("$f")
done < <(find "$REPO_DIR/personas/check" -name '*.md' -print0 | sort -z)

if [ "${#PERSONA_FILES[@]}" -eq 0 ]; then
  echo "[autorun] check: ERROR — no persona files found in personas/check/" >&2
  exit 1
fi

echo "[autorun] check: Phase 1 — launching ${#PERSONA_FILES[@]} reviewers in parallel (timeout=${TIMEOUT_PERSONA}s each)"

# ---------------------------------------------------------------------------
# Phase 1: parallel reviewer calls
# ---------------------------------------------------------------------------
PIDS=()
NAMES=()

for persona_file in "${PERSONA_FILES[@]}"; do
  persona="$(basename "$persona_file" .md)"
  NAMES+=("$persona")

  USER_PROMPT="$(cat "$persona_file")

---

Review the following implementation plan from your perspective above. Output your findings (Must Fix / Should Fix / Notes / Verdict: PASS|PASS WITH NOTES|FAIL).

## Spec

$SPEC_CONTENT

## Plan

$PLAN_CONTENT"

  printf '%s' "$USER_PROMPT" | timeout "$TIMEOUT_PERSONA" claude -p \
    --dangerously-skip-permissions \
    --system-prompt "$AUTONOMY_DIRECTIVE" \
    > "$RAW_DIR/$persona.md" \
    2>"$RAW_DIR/$persona.err" &

  PIDS+=($!)
  echo "[autorun] check: launched $persona (pid=$!)"
done

FAILED=()
for i in "${!PIDS[@]}"; do
  pid="${PIDS[$i]}"
  persona="${NAMES[$i]}"
  exit_code=0
  wait "$pid" || exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    lines="$(wc -l < "$RAW_DIR/$persona.md" 2>/dev/null || echo 0)"
    echo "[autorun] check: $persona done (${lines} lines)"
  else
    echo "[autorun] check: $persona FAILED (exit $exit_code)"
    FAILED+=("$persona")
  fi
done

if [ "${#FAILED[@]}" -eq "${#PIDS[@]}" ]; then
  echo "[autorun] check: ERROR — all reviewers failed" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Phase 2: synthesis — read all reviewer outputs → final check.md + verdict
# ---------------------------------------------------------------------------
echo "[autorun] check: Phase 2 — synthesizing reviewer outputs into check.md"

RAW_COMBINED=""
for persona in "${NAMES[@]}"; do
  raw_file="$RAW_DIR/$persona.md"
  [ -f "$raw_file" ] || continue
  RAW_COMBINED="$RAW_COMBINED
---
## $persona reviewer

$(cat "$raw_file")
"
done

SYNTHESIS_PROMPT="You are the synthesis step of a plan checkpoint review. You have received outputs from ${#NAMES[@]} specialist reviewers. Your job:

1. Identify Must-Fix items that appeared in multiple reviews (convergence signal).
2. Produce a final Overall Verdict: GO | GO WITH FIXES | NO-GO.
   - GO: no Must-Fix items, minor notes only.
   - GO WITH FIXES: Must-Fix items exist but are surgical edits, not architectural rework.
   - NO-GO: fundamental architecture is wrong or a blocker cannot be resolved by edits alone.
3. Write a consolidated check.md with: Overall Verdict, Reviewer Verdicts table, Must Fix list (sourced reviewers), Should Fix list, and Decision Path.

Be terse. This is a headless synthesis — no ceremony, no approval prompts. Write the artifact.

## Reviewer Outputs

$RAW_COMBINED"

STDOUT_LOG="$(mktemp "${TMPDIR:-/tmp}/autorun-check-synth-XXXXXX.log")"
STDERR_LOG="$(mktemp "${TMPDIR:-/tmp}/autorun-check-synth-err-XXXXXX.log")"
trap 'rm -f "$STDOUT_LOG" "$STDERR_LOG"' EXIT

SYNTH_EXIT=0
printf '%s' "$SYNTHESIS_PROMPT" | timeout "$TIMEOUT_STAGE" claude -p \
  --dangerously-skip-permissions \
  --system-prompt "$AUTONOMY_DIRECTIVE" \
  > "$STDOUT_LOG" \
  2>"$STDERR_LOG" || SYNTH_EXIT=$?

if [ "$SYNTH_EXIT" -ne 0 ]; then
  echo "[autorun] check: synthesis FAILED (exit $SYNTH_EXIT)" >&2
  tail -20 "$STDERR_LOG" | sed 's/^/  /'
  exit 1
fi

# Copy synthesis output → check.md (canonical location + artifact dir)
CHECK_CANONICAL="$PROJECT_DIR/docs/specs/$SLUG/check.md"
if [ -s "$STDOUT_LOG" ]; then
  cp "$STDOUT_LOG" "$CHECK_CANONICAL"
  cp "$STDOUT_LOG" "$ARTIFACT_DIR/check.md"
  echo "[autorun] check: check.md written ($(wc -l < "$ARTIFACT_DIR/check.md") lines)"
else
  echo "[autorun] check: ERROR — synthesis produced empty output" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# NO-GO gate
# ---------------------------------------------------------------------------
if grep -qi "NO-GO\|NO GO" "$ARTIFACT_DIR/check.md" 2>/dev/null; then
  echo "[autorun] check: NO-GO verdict — halting item"
  exit 2
fi

echo "[autorun] check: complete (GO or GO WITH FIXES)"
exit 0
