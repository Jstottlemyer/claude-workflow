#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$REPO_DIR/scripts/autorun/defaults.sh"

# ---------------------------------------------------------------------------
# Validate required env vars (set by run.sh before sourcing this script)
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
  echo "[autorun] spec-review: DRY RUN mode — skipping claude -p invocation"

  REVIEW_DIR="$REPO_DIR/docs/specs/$SLUG/spec-review"
  mkdir -p "$REVIEW_DIR"

  cat > "$ARTIFACT_DIR/review-findings.md" <<'EOF'
# Spec Review Findings (DRY RUN)
**Verdict:** PASS WITH NOTES
**Note:** Dry-run stub.
EOF

  cat > "$REVIEW_DIR/run.json" <<'EOF'
{"status": "ok", "mode": "dry_run"}
EOF

  echo "[autorun] spec-review: dry-run artifacts written; exiting 0"
  exit 0
fi

# ---------------------------------------------------------------------------
# Autonomy directive (injected via --system-prompt, NOT in the user prompt)
# ---------------------------------------------------------------------------
AUTONOMY_DIRECTIVE="You are running in fully autonomous overnight mode. At every decision point, pick the safest reversible option and execute. If you find yourself about to write \"Should I\", \"Do you want\", \"Which approach\", \"Before I proceed\", \"Approve to proceed\" — stop. Delete the sentence. Make the call. Log your reasoning in the end-of-run summary. Do not ask for approval. Do not pause for user input. Proceed to writing all artifacts now."

# ---------------------------------------------------------------------------
# Build the user-message prompt
# ---------------------------------------------------------------------------
PROMPT="$(cat "$REPO_DIR/commands/spec-review.md")

---
AUTORUN_CONTEXT:
- SLUG: $SLUG
- SPEC_FILE: $SPEC_FILE
- AUTORUN: 1
- MODE: headless autonomous — do not emit any approval prompts or pause for user input
- After completing the review, write all artifacts to their normal locations, then stop. Do not wait for approval.

$(cat "$SPEC_FILE")"

# ---------------------------------------------------------------------------
# Invoke claude -p with timeout; capture stderr for approval-gate detection
# ---------------------------------------------------------------------------
STDERR_LOG="$(mktemp "${TMPDIR:-/tmp}/autorun-spec-review-XXXXXX.log")"
trap 'rm -f "$STDERR_LOG"' EXIT

echo "[autorun] spec-review: starting claude -p (timeout=${TIMEOUT_STAGE}s, slug=$SLUG)"

CLAUDE_EXIT=0
timeout "$TIMEOUT_STAGE" claude -p \
    --system-prompt "$AUTONOMY_DIRECTIVE" \
    --add-dir "$REPO_DIR" \
    "$PROMPT" \
    2>"$STDERR_LOG" || CLAUDE_EXIT=$?

if [ "$CLAUDE_EXIT" -ne 0 ]; then
  echo "[autorun] spec-review FAILED (claude -p exit $CLAUDE_EXIT)"
  echo "[autorun] spec-review: last 50 lines of stderr:"
  tail -n 50 "$STDERR_LOG" | sed 's/^/  /'
  exit 1
fi

echo "[autorun] spec-review: claude -p exited 0"

# ---------------------------------------------------------------------------
# Test 2: Approval-gate detection
# Check both stderr log and any stdout that was captured in the process.
# Since we piped stdout to our parent (run.sh) and stderr to STDERR_LOG,
# we check STDERR_LOG. The command-level approval prompt may appear in
# combined output — check the log we have.
# ---------------------------------------------------------------------------
if grep -qi "Approve to proceed" "$STDERR_LOG" 2>/dev/null; then
  echo "[autorun] WARN: approval gate detected in stderr output — autonomy directive may not have suppressed it"
fi

# ---------------------------------------------------------------------------
# Test 3: Verify per-persona raw files exist
# ---------------------------------------------------------------------------
RAW_DIR="$REPO_DIR/docs/specs/$SLUG/spec-review/raw"
echo "[autorun] spec-review: checking per-persona raw files in $RAW_DIR"

EXPECTED_PERSONAS=(requirements gaps ambiguity feasibility scope stakeholders)
MISSING_PERSONAS=()
FOUND_PERSONAS=()

for persona in "${EXPECTED_PERSONAS[@]}"; do
  if [ -f "$RAW_DIR/${persona}.md" ]; then
    FOUND_PERSONAS+=("$persona")
  else
    MISSING_PERSONAS+=("$persona")
  fi
done

echo "[autorun] spec-review: persona raw files found: ${#FOUND_PERSONAS[@]}/6 (${FOUND_PERSONAS[*]:-none})"
if [ "${#MISSING_PERSONAS[@]}" -gt 0 ]; then
  echo "[autorun] spec-review: WARN — missing persona raw files: ${MISSING_PERSONAS[*]}"
fi

# ---------------------------------------------------------------------------
# Test 4: Verify findings.jsonl exists
# ---------------------------------------------------------------------------
FINDINGS_FILE="$REPO_DIR/docs/specs/$SLUG/spec-review/findings.jsonl"
if [ -f "$FINDINGS_FILE" ]; then
  echo "[autorun] spec-review: findings.jsonl present ($(wc -l < "$FINDINGS_FILE") lines)"
else
  echo "[autorun] spec-review: WARN — findings.jsonl not found at $FINDINGS_FILE"
fi

# ---------------------------------------------------------------------------
# Test 5: Verify run.json exists and has status "ok"
# ---------------------------------------------------------------------------
RUN_JSON="$REPO_DIR/docs/specs/$SLUG/spec-review/run.json"
if [ ! -f "$RUN_JSON" ]; then
  echo "[autorun] spec-review: WARN — run.json not found at $RUN_JSON"
else
  RUN_STATUS="$(python3 -c "import json; d=json.load(open('$RUN_JSON')); print(d.get('status',''))" 2>/dev/null || echo "")"
  if [ "$RUN_STATUS" = "ok" ]; then
    echo "[autorun] spec-review: run.json status=ok"
  else
    echo "[autorun] spec-review: WARN — run.json status='$RUN_STATUS' (expected 'ok')"
  fi
fi

# ---------------------------------------------------------------------------
# Threshold gate: count FAIL verdicts in findings.jsonl
# If >= SPEC_REVIEW_FATAL_THRESHOLD, write artifact and exit 2
# ---------------------------------------------------------------------------
FAIL_COUNT=0
if [ -f "$FINDINGS_FILE" ]; then
  FAIL_COUNT="$(python3 -c "
import json, sys
count = 0
try:
    with open('$FINDINGS_FILE') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
                if str(row.get('verdict', '')).upper() == 'FAIL':
                    count += 1
            except Exception:
                pass
except Exception:
    pass
print(count)
" 2>/dev/null || echo "0")"
fi

echo "[autorun] spec-review: FAIL verdict count=$FAIL_COUNT (threshold=$SPEC_REVIEW_FATAL_THRESHOLD)"

if [ "$FAIL_COUNT" -ge "$SPEC_REVIEW_FATAL_THRESHOLD" ]; then
  echo "[autorun] spec-review: threshold exceeded ($FAIL_COUNT >= $SPEC_REVIEW_FATAL_THRESHOLD) — writing findings and exiting 2"
  # Write findings artifact before halting
  _write_findings_artifact() {
    local review_md="$REPO_DIR/docs/specs/$SLUG/review.md"
    if [ -f "$review_md" ]; then
      cp "$review_md" "$ARTIFACT_DIR/review-findings.md"
      echo "[autorun] spec-review: wrote review-findings.md from review.md"
    elif [ -d "$RAW_DIR" ]; then
      {
        echo "# Spec Review Findings (concatenated raw personas)"
        echo ""
        echo "**THRESHOLD EXCEEDED: $FAIL_COUNT FAIL verdicts (threshold=$SPEC_REVIEW_FATAL_THRESHOLD)**"
        echo ""
        for f in "$RAW_DIR"/*.md; do
          [ -f "$f" ] || continue
          echo "---"
          echo "## $(basename "$f" .md)"
          echo ""
          cat "$f"
          echo ""
        done
      } > "$ARTIFACT_DIR/review-findings.md"
      echo "[autorun] spec-review: wrote review-findings.md from raw persona files"
    else
      echo "# Spec Review Findings" > "$ARTIFACT_DIR/review-findings.md"
      echo "" >> "$ARTIFACT_DIR/review-findings.md"
      echo "**THRESHOLD EXCEEDED: $FAIL_COUNT FAIL verdicts (threshold=$SPEC_REVIEW_FATAL_THRESHOLD)**" >> "$ARTIFACT_DIR/review-findings.md"
      echo "[autorun] spec-review: wrote minimal review-findings.md (no source artifacts found)"
    fi
  }
  _write_findings_artifact
  exit 2
fi

# ---------------------------------------------------------------------------
# Context handoff: write review-findings.md to ARTIFACT_DIR
# ---------------------------------------------------------------------------
REVIEW_MD="$REPO_DIR/docs/specs/$SLUG/review.md"
if [ -f "$REVIEW_MD" ]; then
  cp "$REVIEW_MD" "$ARTIFACT_DIR/review-findings.md"
  echo "[autorun] spec-review: wrote review-findings.md from review.md"
elif [ -d "$RAW_DIR" ] && [ -n "$(ls "$RAW_DIR"/*.md 2>/dev/null)" ]; then
  {
    echo "# Spec Review Findings (concatenated raw personas)"
    echo ""
    for f in "$RAW_DIR"/*.md; do
      [ -f "$f" ] || continue
      echo "---"
      echo "## $(basename "$f" .md)"
      echo ""
      cat "$f"
      echo ""
    done
  } > "$ARTIFACT_DIR/review-findings.md"
  echo "[autorun] spec-review: wrote review-findings.md from raw persona files (review.md not found)"
else
  echo "[autorun] spec-review: WARN — neither review.md nor raw persona files found; review-findings.md not written"
fi

echo "[autorun] spec-review: complete"
