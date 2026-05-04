#!/bin/bash
##############################################################################
# tests/test-config-content.sh
#
# Supply-chain integrity gate (W4 task 4.7, plan v1.2 R11):
# Refuse to ship anything in config/* that contains code-execution patterns.
# The theme files (cmux.json, tmux.conf, zsh-prompt-colors.zsh) are sourced
# into the user's shell — any eval/curl/wget/nc/bash <(…)/source <(…) in
# them is a supply-chain attack vector.
#
# Pass: grep finds nothing → exit 0
# Fail: grep finds a forbidden pattern → exit 1, names the file/line
##############################################################################
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_DIR="$REPO_DIR/config"

# Distinct word boundaries so we don't false-positive on substrings like
# `evaluate` or `executor`. The bash <(…) / source <(…) patterns are
# matched literally (process-substitution, only valid in bash/zsh).
PATTERN='\b(eval|curl|wget|nc|bash <\(|source <\()\b'

if [ ! -d "$CONFIG_DIR" ]; then
    echo "✓ config/ does not exist (nothing to scan)"
    exit 0
fi

if grep -rEn "$PATTERN" "$CONFIG_DIR/" 2>/dev/null; then
    echo "" >&2
    echo "✗ config/* contains forbidden code-execution patterns" >&2
    echo "  Theme files are sourced into the user's shell — refuse to ship." >&2
    exit 1
fi

echo "✓ config/* clean (no eval/curl/wget/nc/bash<()/source<())"
exit 0
