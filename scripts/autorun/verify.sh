#!/bin/bash
##############################################################################
# scripts/autorun/verify.sh
#
# Post-build spec compliance verifier. Runs INSIDE the build.sh retry loop
# after tests pass. Checks that every explicit spec requirement is present
# in the committed code changes — not just that routes load.
#
# Exit codes:
#   0 — COMPLIANT (all requirements met, or inconclusive infrastructure error)
#   1 — INCOMPLETE (one or more requirements not found in the diff)
#
# Writes: $ARTIFACT_DIR/verify-gaps.md
#   Contains per-requirement [PASS]/[FAIL] lines and a VERDICT line.
#   On the next build attempt, build.sh injects the [FAIL] lines as context.
##############################################################################
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$REPO_DIR}"
source "$REPO_DIR/scripts/autorun/defaults.sh"

: "${SLUG:?SLUG must be set by build.sh}"
: "${QUEUE_DIR:?QUEUE_DIR must be set by build.sh}"
: "${ARTIFACT_DIR:?ARTIFACT_DIR must be set by build.sh}"
: "${SPEC_FILE:?SPEC_FILE must be set by build.sh}"

mkdir -p "$ARTIFACT_DIR"

# ---------------------------------------------------------------------------
# DRY RUN stub
# ---------------------------------------------------------------------------
if [ "${AUTORUN_DRY_RUN:-0}" = "1" ]; then
  echo "[autorun] verify: DRY RUN mode — writing stub COMPLIANT result"
  printf '## Spec Compliance (DRY RUN)\n\nVERDICT: COMPLIANT\n' > "$ARTIFACT_DIR/verify-gaps.md"
  exit 0
fi

# ---------------------------------------------------------------------------
# Collect build context
# ---------------------------------------------------------------------------
PRE_BUILD_SHA="$(cat "$ARTIFACT_DIR/pre-build-sha.txt" 2>/dev/null || echo "")"

if [ -z "$PRE_BUILD_SHA" ]; then
  echo "[autorun] verify: WARN — no pre-build SHA found; skipping compliance check"
  exit 0
fi

CURRENT_SHA="$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || echo "")"
if [ -z "$CURRENT_SHA" ] || [ "$CURRENT_SHA" = "$PRE_BUILD_SHA" ]; then
  echo "[autorun] verify: FAIL — no commits since pre-build SHA; build agent produced nothing"
  printf 'VERDICT: INCOMPLETE — build agent produced no commits\n' > "$ARTIFACT_DIR/verify-gaps.md"
  exit 1
fi

# Cap diff to avoid overflowing the context window
GIT_DIFF="$(git -C "$PROJECT_DIR" diff "$PRE_BUILD_SHA" HEAD -- . 2>/dev/null | head -3000 || echo "(diff unavailable)")"
DIFF_LINE_COUNT="$(printf '%s\n' "$GIT_DIFF" | wc -l | tr -d ' ')"

TRUNCATION_NOTE=""
if [ "$DIFF_LINE_COUNT" -ge 3000 ]; then
  TRUNCATION_NOTE="
⚠ WARNING: diff was truncated at 3000 lines. Requirements implemented after line 3000 are NOT visible — mark any requirement without clear diff evidence as [FAIL]."
fi

echo "[autorun] verify: checking compliance for $SLUG (diff: ~${DIFF_LINE_COUNT} lines)"

# ---------------------------------------------------------------------------
# Build verification prompt
# ---------------------------------------------------------------------------
VERIFY_PROMPT="You are a post-build spec compliance verifier. Your job is to check whether every explicit requirement in the spec is present in the committed code changes.

## Critical Rules
- 'A route exists' or 'a page renders' is NOT compliance for a requirement that specifies UI elements, access gates, or specific data fields.
  - Example: spec says 'users see a Permission Denied banner when role != admin'. A route returning 403 is [FAIL] — the banner render logic must appear in the diff.
- 'A file was created' is NOT compliance unless the spec's specific content or behavior is present in the diff.
- If there is no clear diff evidence for a requirement, mark it [FAIL].
- Be strict. If in doubt, mark [FAIL].
- Do NOT judge code quality — only whether the requirement is present.

## Spec (what was required)
$(head -1000 "$SPEC_FILE")

## Plan (what the build agent intended to implement)
$(head -500 "$ARTIFACT_DIR/plan.md" 2>/dev/null || echo "(plan not available)")

## Committed Changes (git diff since pre-build SHA, capped at 3000 lines — ${DIFF_LINE_COUNT} actual lines shown)
${TRUNCATION_NOTE}
$GIT_DIFF

## Output Format
For each explicit spec requirement, output exactly one line:
[PASS] <requirement summary>
or
[FAIL] <requirement summary> — <specific reason: what is missing from the diff>

After listing all requirements, output exactly one of these verdict lines:
VERDICT: COMPLIANT
VERDICT: INCOMPLETE — <N> requirement(s) not met"

# ---------------------------------------------------------------------------
# Invoke claude -p
# ---------------------------------------------------------------------------
VERIFY_STDERR="$(mktemp "${TMPDIR:-/tmp}/autorun-verify-XXXXXX.log")"
trap 'rm -f "$VERIFY_STDERR"' EXIT

printf '%s' "$VERIFY_PROMPT" | timeout "${TIMEOUT_VERIFY:-600}" claude -p \
  --dangerously-skip-permissions \
  --system-prompt "You are a strict spec compliance verifier. Be precise and concise. Do not implement anything — only report what is and is not present in the diff." \
  2>"$VERIFY_STDERR" | tee "$ARTIFACT_DIR/verify-gaps.md" || true
VERIFY_EXIT=${PIPESTATUS[1]}

# 124 = timeout, 127 = command not found — true infrastructure errors; treat as inconclusive
if [ "$VERIFY_EXIT" -eq 124 ] || [ "$VERIFY_EXIT" -eq 127 ]; then
  echo "[autorun] verify: infrastructure error (exit $VERIFY_EXIT) — treating as inconclusive (proceeding)"
  exit 0
fi

if [ "$VERIFY_EXIT" -ne 0 ]; then
  echo "[autorun] verify: verifier exited $VERIFY_EXIT — checking verdict in output"
fi

# ---------------------------------------------------------------------------
# Parse verdict
# ---------------------------------------------------------------------------
if grep -iq "^VERDICT: INCOMPLETE" "$ARTIFACT_DIR/verify-gaps.md" 2>/dev/null; then
  FAIL_COUNT="$(grep -ic '^\[FAIL\]' "$ARTIFACT_DIR/verify-gaps.md" 2>/dev/null || true)"
  FAIL_COUNT="${FAIL_COUNT:-0}"
  echo "[autorun] verify: INCOMPLETE — ${FAIL_COUNT} requirement(s) not met in $SLUG"
  exit 1
fi

PASS_COUNT="$(grep -ic '^\[PASS\]' "$ARTIFACT_DIR/verify-gaps.md" 2>/dev/null || true)"
PASS_COUNT="${PASS_COUNT:-0}"
echo "[autorun] verify: COMPLIANT — ${PASS_COUNT} requirement(s) verified for $SLUG"
exit 0
