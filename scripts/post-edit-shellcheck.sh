#!/usr/bin/env bash
##############################################################################
# scripts/post-edit-shellcheck.sh
#
# PostToolUse hook: run shellcheck on edited shell scripts.
#
# Reads the Claude Code hook payload from stdin (JSON with tool_input.file_path),
# extracts the edited file path, and if it's a shell script, runs shellcheck
# and reports findings as a non-blocking advisory message.
#
# Exit codes:
#   0 — always (advisory only; never block edits)
##############################################################################
set -uo pipefail

# Read JSON payload (stdin) and extract file_path.
# Hook payload schema: {"tool_input": {"file_path": "..."}, ...}
PAYLOAD="$(cat 2>/dev/null || echo '{}')"
FILE_PATH="$(printf '%s' "$PAYLOAD" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    fp = d.get("tool_input",{}).get("file_path","") or d.get("file_path","")
    print(fp)
except Exception:
    print("")
' 2>/dev/null || echo "")"

# Bail silently if no path or not a shell script.
[ -z "$FILE_PATH" ] && exit 0
case "$FILE_PATH" in
  *.sh|*.bash) ;;
  *) exit 0 ;;
esac

# Bail if shellcheck not installed (don't fail the edit).
command -v shellcheck >/dev/null 2>&1 || exit 0

# Run shellcheck. -x = follow sourced files; head -20 caps noise.
OUTPUT="$(shellcheck -x "$FILE_PATH" 2>&1 | head -20 || true)"
[ -z "$OUTPUT" ] && exit 0

# Emit as systemMessage so it surfaces in the conversation as advisory text.
python3 -c 'import json,sys; print(json.dumps({"systemMessage": "shellcheck: " + sys.argv[1]}))' "$OUTPUT" 2>/dev/null || true
exit 0
