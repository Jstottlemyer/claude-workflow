#!/bin/bash
# scripts/autorun/notify.sh — Task 3.6 (autorun-overnight-policy v6).
#
# Reads queue/runs/<run-id>/morning-report.json and renders a notification
# subject + body keyed off `final_state` (per spec D38 8-permutation table).
# Existing notification machinery (mail, macOS osascript banner, webhook) is
# preserved — only the content is updated to read from morning-report.json.
#
# Exit-code policy: notifications are best-effort; any internal failure must
# not block the pipeline. Always exit 0.
#
# Bash 3.2 compatible (no `${arr[-1]}`, no `mapfile`).

# No `set -euo pipefail` — best-effort.

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_DIR/scripts/autorun/defaults.sh"

POLICY_JSON_PY="${POLICY_JSON_PY:-$REPO_DIR/scripts/autorun/_policy_json.py}"

# ---------------------------------------------------------------------------
# Locate morning-report.json
# ---------------------------------------------------------------------------
# Resolution order:
#   1. $MORNING_REPORT (explicit override; tests use this)
#   2. $ARTIFACT_DIR/morning-report.json (per-run dir)
#   3. $QUEUE_DIR/runs/current/morning-report.json (current symlink)
#
# When none exist, fall back to the legacy run-summary.md path (preserves
# behavior for adopters who still have run-summary.md from older builds).
MORNING_REPORT="${MORNING_REPORT:-}"
if [ -z "$MORNING_REPORT" ] && [ -n "${ARTIFACT_DIR:-}" ] && [ -f "$ARTIFACT_DIR/morning-report.json" ]; then
  MORNING_REPORT="$ARTIFACT_DIR/morning-report.json"
fi
if [ -z "$MORNING_REPORT" ] && [ -n "${QUEUE_DIR:-}" ] && [ -f "$QUEUE_DIR/runs/current/morning-report.json" ]; then
  MORNING_REPORT="$QUEUE_DIR/runs/current/morning-report.json"
fi

# ---------------------------------------------------------------------------
# _json_get_safe POINTER FILE [DEFAULT]
# Wrapper that swallows _policy_json.py errors and returns DEFAULT (or empty).
# ---------------------------------------------------------------------------
_json_get_safe() {
  local pointer="$1" file="$2" default="${3:-}"
  local out
  if ! out="$(python3 "$POLICY_JSON_PY" get "$file" "$pointer" 2>/dev/null)"; then
    printf '%s' "$default"
    return 0
  fi
  # Strip trailing newline (printf-friendly).
  printf '%s' "$out"
}

# ---------------------------------------------------------------------------
# stage_label STAGE
# D38 stage-label map: 11-value STAGE enum -> human label.
# Unknown stage falls through to the raw enum value (defensive — schema enforces
# the enum upstream).
# ---------------------------------------------------------------------------
stage_label() {
  case "$1" in
    spec-review)  printf '%s' "Spec review" ;;
    plan)         printf '%s' "Planning" ;;
    check)        printf '%s' "Checkpoint" ;;
    verify)       printf '%s' "Verification" ;;
    build)        printf '%s' "Build" ;;
    branch-setup) printf '%s' "Branch setup" ;;
    codex-review) printf '%s' "Codex review" ;;
    pr-creation)  printf '%s' "PR creation" ;;
    merging)      printf '%s' "Merge" ;;
    complete)     printf '%s' "Completion" ;;
    pr)           printf '%s' "PR" ;;
    *)            printf '%s' "$1" ;;
  esac
}

# ---------------------------------------------------------------------------
# Build SUBJECT and BODY_FILE
# ---------------------------------------------------------------------------
BODY_FILE="$(mktemp "${TMPDIR:-/tmp}/autorun-notify-body-XXXXXX.md")"
trap 'rm -f "$BODY_FILE"' EXIT

if [ -n "$MORNING_REPORT" ] && [ -f "$MORNING_REPORT" ]; then
  # Read fields from morning-report.json via _policy_json.py get.
  FINAL_STATE="$(_json_get_safe /final_state "$MORNING_REPORT" "")"
  SLUG_FIELD="$(_json_get_safe /slug "$MORNING_REPORT" "${SLUG:-unknown}")"
  RUN_ID_FIELD="$(_json_get_safe /run_id "$MORNING_REPORT" "${RUN_ID:-unknown}")"
  PR_URL_FIELD="$(_json_get_safe /pr_url "$MORNING_REPORT" "")"
  # PR number derived from pr_url (last numeric path segment); leave empty if absent.
  PR_NUMBER=""
  if [ -n "$PR_URL_FIELD" ] && [ "$PR_URL_FIELD" != "null" ]; then
    PR_NUMBER="$(printf '%s' "$PR_URL_FIELD" | sed -n 's|.*/pull/\([0-9][0-9]*\).*|\1|p')"
  fi
  # First block's stage drives the halted-at-stage label.
  HALT_STAGE="$(_json_get_safe /blocks/0/stage "$MORNING_REPORT" "")"
  HALT_STAGE_LABEL=""
  if [ -n "$HALT_STAGE" ]; then
    HALT_STAGE_LABEL="$(stage_label "$HALT_STAGE")"
  fi
  HALT_REASON="$(_json_get_safe /blocks/0/reason "$MORNING_REPORT" "")"

  case "$FINAL_STATE" in
    merged)
      if [ -n "$PR_NUMBER" ]; then
        LINE="Merged to main: $SLUG_FIELD — PR #$PR_NUMBER merged. No action needed."
      else
        LINE="Merged to main: $SLUG_FIELD — PR merged. No action needed."
      fi
      SUBJECT="[autorun] Merged: $SLUG_FIELD"
      ;;
    pr-awaiting-review)
      LINE="PR awaiting review: $SLUG_FIELD — degraded run; review the PR and merge manually if it looks good."
      if [ -n "$PR_URL_FIELD" ] && [ "$PR_URL_FIELD" != "null" ]; then
        LINE="$LINE PR: $PR_URL_FIELD"
      fi
      SUBJECT="[autorun] PR awaiting review: $SLUG_FIELD"
      ;;
    halted-at-stage)
      if [ -z "$HALT_STAGE_LABEL" ]; then
        HALT_STAGE_LABEL="unknown"
      fi
      LINE="Halted at $HALT_STAGE_LABEL: $SLUG_FIELD — read the blocking reason; fix and re-run. Stage: $HALT_STAGE_LABEL."
      if [ -n "$HALT_REASON" ]; then
        LINE="$LINE Reason: $HALT_REASON"
      fi
      SUBJECT="[autorun] Halted at $HALT_STAGE_LABEL: $SLUG_FIELD"
      ;;
    completed-no-pr)
      LINE="Run completed but PR creation failed: $SLUG_FIELD — branch + commit ready at queue/runs/$RUN_ID_FIELD/. Suggested: gh pr create --base main --head autorun/$SLUG_FIELD."
      SUBJECT="[autorun] Completed (no PR): $SLUG_FIELD"
      ;;
    *)
      LINE="Autorun notification for $SLUG_FIELD — final_state=\"$FINAL_STATE\" (unrecognized)."
      SUBJECT="[autorun] Run complete: $SLUG_FIELD"
      ;;
  esac

  {
    printf '# Autorun Notification\n'
    printf '\n'
    printf '%s\n' "$LINE"
    printf '\n'
    printf 'Run ID: %s\n' "$RUN_ID_FIELD"
    printf 'Slug: %s\n' "$SLUG_FIELD"
    printf 'Final state: %s\n' "$FINAL_STATE"
    if [ -n "$PR_URL_FIELD" ] && [ "$PR_URL_FIELD" != "null" ]; then
      printf 'PR: %s\n' "$PR_URL_FIELD"
    fi
    printf 'Timestamp: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$BODY_FILE"
  echo "[autorun] notify: built notification from $MORNING_REPORT (final_state=$FINAL_STATE)"
elif [ -n "${ARTIFACT_DIR:-}" ] && [ -f "$ARTIFACT_DIR/failure.md" ]; then
  # Legacy per-item failure notification (preserved for backward compat).
  SUBJECT="[autorun] FAILED: ${SLUG:-unknown}"
  cp "$ARTIFACT_DIR/failure.md" "$BODY_FILE"
  echo "[autorun] notify: building failure notification for slug=${SLUG:-unknown} (legacy path)"
elif [ -n "${QUEUE_DIR:-}" ] && [ -f "$QUEUE_DIR/run-summary.md" ]; then
  # Legacy run-summary.md path (preserved for backward compat).
  SUBJECT="[autorun] Run complete"
  cp "$QUEUE_DIR/run-summary.md" "$BODY_FILE"
  echo "[autorun] notify: building run-completion notification from run-summary.md (legacy path)"
else
  # Minimal fallback body.
  SUBJECT="[autorun] Run complete"
  cat > "$BODY_FILE" <<EOF
# Autorun Run Completed

Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)

No detailed summary available (morning-report.json not found).
EOF
  echo "[autorun] notify: no morning-report.json found; using minimal body"
fi

# ---------------------------------------------------------------------------
# AUTORUN_DRY_RUN stub mode
# ---------------------------------------------------------------------------
if [ "${AUTORUN_DRY_RUN:-0}" = "1" ]; then
  echo "[autorun] notify: DRY RUN mode — would have sent: $SUBJECT"
  if [ -n "${QUEUE_DIR:-}" ]; then
    cat > "$QUEUE_DIR/notification-fallback.md" <<EOF
# Notification Fallback (Dry Run)
**Subject:** $SUBJECT
**Timestamp:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

$(cat "$BODY_FILE")
EOF
    echo "[autorun] notify: dry-run fallback written to $QUEUE_DIR/notification-fallback.md"
  fi
  # Print the body to stdout in dry-run / test mode so callers can grep it.
  cat "$BODY_FILE"
  exit 0
fi

# ---------------------------------------------------------------------------
# AUTORUN_NOTIFY_STDOUT — for tests and manual inspection.
# When set to 1, print body to stdout in addition to (or instead of) sending.
# ---------------------------------------------------------------------------
if [ "${AUTORUN_NOTIFY_STDOUT:-0}" = "1" ]; then
  printf 'Subject: %s\n' "$SUBJECT"
  cat "$BODY_FILE"
  # Continue to attempt real notification methods unless explicitly skipped.
  if [ "${AUTORUN_NOTIFY_SKIP_SEND:-0}" = "1" ]; then
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Attempt notifications — NOTIFIED=0 until any method succeeds
# ---------------------------------------------------------------------------
NOTIFIED=0

# Method 1: macOS mail
if [ -n "${MAIL_TO:-}" ]; then
  mail -s "$SUBJECT" "$MAIL_TO" < "$BODY_FILE" \
    && NOTIFIED=1 \
    || echo "[autorun] notify: mail to $MAIL_TO failed"
fi

# Method 2: osascript desktop banner (macOS only)
if command -v osascript >/dev/null 2>&1; then
  BANNER_MSG="$(head -3 "$BODY_FILE" | tr '\n' ' ' | cut -c1-200)"
  # Escape backslashes and double-quotes for AppleScript string literals.
  # Without this, quotes/backslashes in spec text could break the command or
  # inject AppleScript syntax.
  BANNER_ESC="$(printf '%s' "$BANNER_MSG" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
  SUBJECT_ESC="$(printf '%s' "$SUBJECT"    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
  osascript -e "display notification \"$BANNER_ESC\" with title \"$SUBJECT_ESC\"" \
    && NOTIFIED=1 \
    || echo "[autorun] notify: osascript failed"
fi

# Method 3: Webhook (Slack/generic)
if [ -n "${WEBHOOK_URL:-}" ]; then
  BODY_TEXT="$(head -10 "$BODY_FILE" 2>/dev/null || true)"
  PAYLOAD="$(python3 -c "
import json, sys
subject = sys.argv[1]
body = sys.argv[2]
print(json.dumps({'text': '*{}*\n{}'.format(subject, body)}))
" "$SUBJECT" "$BODY_TEXT" 2>/dev/null || printf '{"text": "%s"}' "$SUBJECT")"
  curl -s -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" >/dev/null \
    && NOTIFIED=1 \
    || echo "[autorun] notify: webhook to $WEBHOOK_URL failed"
fi

# ---------------------------------------------------------------------------
# Fallback file if no method succeeded
# ---------------------------------------------------------------------------
if [ "$NOTIFIED" = "0" ] && [ -n "${QUEUE_DIR:-}" ]; then
  BODY_CONTENT="$(cat "$BODY_FILE")"
  cat > "$QUEUE_DIR/notification-fallback.md" <<EOF
# Notification Fallback
**Subject:** $SUBJECT
**Timestamp:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

$BODY_CONTENT
EOF
  echo "[autorun] notify: wrote fallback to $QUEUE_DIR/notification-fallback.md"
elif [ "$NOTIFIED" = "1" ]; then
  echo "[autorun] notify: notification sent successfully"
fi

# Notifications are best-effort — always exit 0
exit 0
