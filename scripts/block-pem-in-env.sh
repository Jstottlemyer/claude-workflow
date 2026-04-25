#!/bin/bash
# PreToolUse hook wrapper — see block-pem-in-env.py for the actual logic.
exec python3 "$(dirname "$0")/block-pem-in-env.py"
