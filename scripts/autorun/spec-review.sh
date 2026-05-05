#!/bin/bash
# scripts/autorun/spec-review.sh
#
# Parallel spec-review: one claude -p per persona, all launched concurrently.
# No --add-dir: spec content is passed inline, keeping each call small and fast.
# Merges raw persona outputs into review-findings.md after all personas complete.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$REPO_DIR}"
source "$REPO_DIR/scripts/autorun/defaults.sh"

: "${SLUG:?SLUG must be set by run.sh}"
: "${QUEUE_DIR:?QUEUE_DIR must be set by run.sh}"
: "${ARTIFACT_DIR:?ARTIFACT_DIR must be set by run.sh}"
: "${SPEC_FILE:?SPEC_FILE must be set by run.sh}"

mkdir -p "$ARTIFACT_DIR"

REVIEW_DIR="$PROJECT_DIR/docs/specs/$SLUG/spec-review"
RAW_DIR="$REVIEW_DIR/raw"
mkdir -p "$RAW_DIR"

# ---------------------------------------------------------------------------
# DRY RUN stub
# ---------------------------------------------------------------------------
if [ "${AUTORUN_DRY_RUN:-0}" = "1" ]; then
  echo "[autorun] spec-review: DRY RUN — writing stub artifacts"
  cat > "$ARTIFACT_DIR/review-findings.md" <<'EOF'
# Spec Review Findings (DRY RUN)
**Verdict:** PASS WITH NOTES
**Note:** Dry-run stub.
EOF
  mkdir -p "$REVIEW_DIR"
  echo '{"status":"ok","mode":"dry_run"}' > "$REVIEW_DIR/run.json"
  exit 0
fi

AUTONOMY_DIRECTIVE="You are running in fully autonomous overnight mode. At every decision point, pick the safest reversible option and execute. If you find yourself about to write \"Should I\", \"Do you want\", \"Which approach\", \"Before I proceed\", \"Approve to proceed\" — stop. Delete the sentence. Make the call. Log your reasoning in the end-of-run summary. Do not ask for approval. Do not pause for user input. Proceed to writing all artifacts now."

SPEC_CONTENT="$(cat "$SPEC_FILE")"

# Discover personas from disk — never hardcode names so adopter forks stay safe
PERSONA_FILES=()
while IFS= read -r -d '' f; do
  PERSONA_FILES+=("$f")
done < <(find "$REPO_DIR/personas/review" -name '*.md' -print0 | sort -z)

if [ "${#PERSONA_FILES[@]}" -eq 0 ]; then
  echo "[autorun] spec-review: ERROR — no persona files found in personas/review/" >&2
  exit 1
fi

echo "[autorun] spec-review: launching ${#PERSONA_FILES[@]} personas in parallel (timeout=${TIMEOUT_PERSONA}s each)"

# ---------------------------------------------------------------------------
# Launch all personas concurrently
# ---------------------------------------------------------------------------
PIDS=()
NAMES=()

for persona_file in "${PERSONA_FILES[@]}"; do
  persona="$(basename "$persona_file" .md)"
  NAMES+=("$persona")

  USER_PROMPT="$(cat "$persona_file")

---

Review the following spec from your perspective above. Output your findings using your standard format (Critical Gaps / Important Considerations / Observations / Verdict).

## Spec

$SPEC_CONTENT"

  printf '%s' "$USER_PROMPT" | timeout "$TIMEOUT_PERSONA" claude -p \
    --dangerously-skip-permissions \
    --system-prompt "$AUTONOMY_DIRECTIVE" \
    > "$RAW_DIR/$persona.md" \
    2>"$RAW_DIR/$persona.err" &

  PIDS+=($!)
  echo "[autorun] spec-review: launched $persona (pid=$!)"
done

# ---------------------------------------------------------------------------
# Wait for all — collect exit codes
# ---------------------------------------------------------------------------
FAILED=()
for i in "${!PIDS[@]}"; do
  pid="${PIDS[$i]}"
  persona="${NAMES[$i]}"
  exit_code=0
  wait "$pid" || exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    lines="$(wc -l < "$RAW_DIR/$persona.md" 2>/dev/null || echo 0)"
    echo "[autorun] spec-review: $persona done (${lines} lines)"
  else
    echo "[autorun] spec-review: $persona FAILED (exit $exit_code)"
    FAILED+=("$persona")
    if [ -s "$RAW_DIR/$persona.err" ]; then
      echo "[autorun] spec-review: $persona stderr:" && tail -5 "$RAW_DIR/$persona.err" | sed 's/^/  /'
    fi
  fi
done

if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "[autorun] spec-review: WARN — ${#FAILED[@]} persona(s) failed: ${FAILED[*]}"
fi

# Abort if all personas failed
if [ "${#FAILED[@]}" -eq "${#PIDS[@]}" ]; then
  echo "[autorun] spec-review: ERROR — all personas failed; cannot produce review" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Merge raw outputs → review.md
# ---------------------------------------------------------------------------
REVIEW_MD="$REVIEW_DIR/review.md"
{
  echo "# Spec Review — $SLUG"
  echo ""
  echo "**Reviewed:** $(date +%Y-%m-%d)"
  echo "**Reviewers:** ${NAMES[*]}"
  echo ""
  for persona in "${NAMES[@]}"; do
    raw_file="$RAW_DIR/$persona.md"
    [ -f "$raw_file" ] || continue
    echo "---"
    echo ""
    echo "## $persona"
    echo ""
    cat "$raw_file"
    echo ""
  done
} > "$REVIEW_MD"

cp "$REVIEW_MD" "$ARTIFACT_DIR/review-findings.md"
echo "[autorun] spec-review: review-findings.md written ($(wc -l < "$ARTIFACT_DIR/review-findings.md") lines)"

# ---------------------------------------------------------------------------
# Gate: count Verdict: FAIL across all raw persona files
# ---------------------------------------------------------------------------
FAIL_COUNT=0
for persona in "${NAMES[@]}"; do
  raw_file="$RAW_DIR/$persona.md"
  [ -f "$raw_file" ] || continue
  if grep -qi "^Verdict: FAIL" "$raw_file" 2>/dev/null; then
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "[autorun] spec-review: FAIL verdict from $persona"
  fi
done

echo "[autorun] spec-review: FAIL verdict count=$FAIL_COUNT (threshold=$SPEC_REVIEW_FATAL_THRESHOLD)"

echo '{"status":"ok","personas":'"${#NAMES[@]}"',"failed":'"${#FAILED[@]}"',"fail_verdicts":'"$FAIL_COUNT"'}' \
  > "$REVIEW_DIR/run.json"

if [ "$FAIL_COUNT" -ge "$SPEC_REVIEW_FATAL_THRESHOLD" ]; then
  echo "[autorun] spec-review: threshold exceeded — halting item"
  exit 2
fi

echo "[autorun] spec-review: complete"
exit 0
