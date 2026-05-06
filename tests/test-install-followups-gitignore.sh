#!/bin/bash
##############################################################################
# tests/test-install-followups-gitignore.sh
#
# Verifies install.sh's PERSONA_METRICS_GITIGNORE block includes the per-spec
# followups.jsonl path (added in v0.9.0 for the pipeline-gate-permissiveness
# spec, matching the per-user data audit policy in
# feedback_public_repo_data_audit.md).
#
# Asserts:
#   1. The sentinel-bracketed block exists in install.sh.
#   2. The block contains the literal `docs/specs/*/followups.jsonl` line.
#   3. `bash -n install.sh` exits 0 (script still parses).
##############################################################################
set -euo pipefail

# Pin /bin/bash for bash 3.2 fidelity.
export BASH=/bin/bash

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_SH="$REPO_ROOT/install.sh"

if [ ! -f "$INSTALL_SH" ]; then
    echo "FAIL: install.sh not found at $INSTALL_SH"
    exit 1
fi

# Sentinels in the install.sh source: the BEGIN/END strings appear (a) as
# variable assignments (BLOCK_BEGIN=, BLOCK_END=) and (b) as `echo
# "$BLOCK_BEGIN"` / `echo "$BLOCK_END"` lines that frame the heredoc-style
# block of gitignore patterns. The followups.jsonl line lives between the
# two `echo "$BLOCK_*"` lines.
ECHO_BEGIN='echo "$BLOCK_BEGIN"'
ECHO_END='echo "$BLOCK_END"'
ASSIGN_BEGIN='BLOCK_BEGIN="# BEGIN persona-metrics (MonsterFlow)"'
ASSIGN_END='BLOCK_END="# END persona-metrics"'

# 1. Sentinel variable assignments present.
if ! grep -qF "$ASSIGN_BEGIN" "$INSTALL_SH"; then
    echo "FAIL: BLOCK_BEGIN assignment not found in install.sh"
    exit 1
fi
if ! grep -qF "$ASSIGN_END" "$INSTALL_SH"; then
    echo "FAIL: BLOCK_END assignment not found in install.sh"
    exit 1
fi
if ! grep -qF "$ECHO_BEGIN" "$INSTALL_SH"; then
    echo "FAIL: 'echo \"\$BLOCK_BEGIN\"' framing line not found"
    exit 1
fi
if ! grep -qF "$ECHO_END" "$INSTALL_SH"; then
    echo "FAIL: 'echo \"\$BLOCK_END\"' framing line not found"
    exit 1
fi

# 2. followups.jsonl line present, AND inside the framing echo statements.
# Extract the lines between `echo "$BLOCK_BEGIN"` and `echo "$BLOCK_END"`.
BLOCK_CONTENT=$(awk -v begin="$ECHO_BEGIN" -v end="$ECHO_END" '
    index($0, begin) { in_block=1; next }
    index($0, end)   { if (in_block) { in_block=0 } ; next }
    in_block         { print }
' "$INSTALL_SH")

if [ -z "$BLOCK_CONTENT" ]; then
    echo "FAIL: extracted block content is empty"
    exit 1
fi

if ! echo "$BLOCK_CONTENT" | grep -qF 'docs/specs/*/followups.jsonl'; then
    echo "FAIL: 'docs/specs/*/followups.jsonl' not found inside persona-metrics block"
    echo "--- Block content ---"
    echo "$BLOCK_CONTENT"
    echo "---------------------"
    exit 1
fi

# 3. Script still parses.
if ! bash -n "$INSTALL_SH"; then
    echo "FAIL: bash -n install.sh exited non-zero"
    exit 1
fi

echo "PASS: install.sh persona-metrics block contains followups.jsonl and parses cleanly"
exit 0
