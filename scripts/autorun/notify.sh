#!/bin/bash
# No set -euo pipefail — this script is best-effort; errors must not block the pipeline.

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$REPO_DIR/scripts/autorun/defaults.sh"

# ---------------------------------------------------------------------------
# Validate required env vars
# ---------------------------------------------------------------------------
: "${QUEUE_DIR:?QUEUE_DIR must be set by run.sh}"

# ---------------------------------------------------------------------------
# Build SUBJECT and BODY_FILE
# ---------------------------------------------------------------------------
BODY_FILE="$(mktemp "${TMPDIR:-/tmp}/autorun-notify-body-XXXXXX.md")"
trap 'rm -f "$BODY_FILE"' EXIT

if [ -n "${ARTIFACT_DIR:-}" ] && [ -f "$ARTIFACT_DIR/failure.md" ]; then
  # Per-item failure notification
  SUBJECT="[autorun] FAILED: ${SLUG:-unknown}"
  cp "$ARTIFACT_DIR/failure.md" "$BODY_FILE"
  echo "[autorun] notify: building failure notification for slug=${SLUG:-unknown}"
elif [ -f "$QUEUE_DIR/run-summary.md" ]; then
  # Run completion notification
  SUBJECT="[autorun] Run complete"
  cp "$QUEUE_DIR/run-summary.md" "$BODY_FILE"
  echo "[autorun] notify: building run-completion notification from run-summary.md"
else
  # Minimal fallback body
  SUBJECT="[autorun] Run complete"
  cat > "$BODY_FILE" <<EOF
# Autorun Run Completed

Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)

No detailed summary available (run-summary.md not found).
EOF
  echo "[autorun] notify: no summary file found; using minimal body"
fi

# ---------------------------------------------------------------------------
# AUTORUN_DRY_RUN stub mode
# ---------------------------------------------------------------------------
if [ "${AUTORUN_DRY_RUN:-0}" = "1" ]; then
  echo "[autorun] notify: DRY RUN mode — would have sent: $SUBJECT"
  cat > "$QUEUE_DIR/notification-fallback.md" <<EOF
# Notification Fallback (Dry Run)
**Subject:** $SUBJECT
**Timestamp:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

$(cat "$BODY_FILE")
EOF
  echo "[autorun] notify: dry-run fallback written to $QUEUE_DIR/notification-fallback.md"
  exit 0
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
  osascript -e "display notification \"$BANNER_MSG\" with title \"$SUBJECT\"" \
    && NOTIFIED=1 \
    || echo "[autorun] notify: osascript failed"
fi

# Method 3: Webhook (Slack/generic)
if [ -n "${WEBHOOK_URL:-}" ]; then
  PAYLOAD="{\"text\": \"*$SUBJECT*\\n$(head -10 "$BODY_FILE" | sed 's/"/\\"/g' | tr '\n' '\\' | sed 's/\\/\\n/g')\"}"
  curl -s -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" >/dev/null \
    && NOTIFIED=1 \
    || echo "[autorun] notify: webhook to $WEBHOOK_URL failed"
fi

# ---------------------------------------------------------------------------
# Fallback file if no method succeeded
# ---------------------------------------------------------------------------
if [ "$NOTIFIED" = "0" ]; then
  BODY_CONTENT="$(cat "$BODY_FILE")"
  cat > "$QUEUE_DIR/notification-fallback.md" <<EOF
# Notification Fallback
**Subject:** $SUBJECT
**Timestamp:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

$BODY_CONTENT
EOF
  echo "[autorun] notify: wrote fallback to $QUEUE_DIR/notification-fallback.md"
else
  echo "[autorun] notify: notification sent successfully"
fi

# Notifications are best-effort — always exit 0
exit 0
