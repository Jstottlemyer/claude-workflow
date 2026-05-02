#!/usr/bin/env bash
##############################################################################
# scripts/post-edit-json-validate.sh
#
# PostToolUse hook: validate edited JSON files via `jq empty`.
#
# Catches stray-comma / missing-quote breakage in settings.json,
# autorun.config.json, schemas/*.json before they bite mid-session.
#
# Exit codes:
#   0 — always (advisory only)
##############################################################################
set -uo pipefail

PAYLOAD="$(cat 2>/dev/null || echo '{}')"
FILE_PATH="$(printf '%s' "$PAYLOAD" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    fp = d.get("tool_input",{}).get("file_path","") or d.get("file_path","")
    print(fp)
except Exception:
    print("")
' 2>/dev/null || echo "")"

[ -z "$FILE_PATH" ] && exit 0
case "$FILE_PATH" in
  *.json) ;;
  *) exit 0 ;;
esac

command -v jq >/dev/null 2>&1 || exit 0

# `jq empty` prints nothing on valid JSON, error to stderr on invalid.
ERR="$(jq empty "$FILE_PATH" 2>&1 >/dev/null || true)"
[ -z "$ERR" ] && exit 0

python3 -c 'import json,sys; print(json.dumps({"systemMessage": "JSON syntax error in " + sys.argv[1] + ": " + sys.argv[2]}))' "$FILE_PATH" "$ERR" 2>/dev/null || true
exit 0
