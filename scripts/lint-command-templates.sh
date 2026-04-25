#!/bin/bash
# lint-command-templates.sh — catch hardcoded paths in command/skill templates
#
# Purpose: prevent regressions like the 2026-04-23 wrap.md bug where the memory
# path was hardcoded as `/Users/jstottlemyer/.claude/projects/-Users-jstottlemyer/memory/`
# instead of the template form `~/.claude/projects/<cwd-slug>/memory/`.
#
# A hardcoded path in a command template means:
#   - The path only works on the author's machine
#   - Future sessions silently write memories to a directory no one loads from
#   - The bug is invisible until a future session fails to recall the memory
#
# Exit 0 if clean, 1 if violations found.
#
# Usage:
#   ./scripts/lint-command-templates.sh              # scan commands/
#   ./scripts/lint-command-templates.sh path/to/dir  # scan a custom dir

set -uo pipefail

SCAN_DIR="${1:-commands}"
VIOLATIONS=0

if [ ! -d "$SCAN_DIR" ]; then
    echo "ERROR: scan directory not found: $SCAN_DIR" >&2
    exit 2
fi

echo "Scanning $SCAN_DIR/ for hardcoded memory paths..."

# Pattern 1: hardcoded absolute .claude/projects path with user-specific prefix.
# Must NOT use <cwd-slug> template placeholder.
# Skip .bak files — they're historical backups, not active templates.
while IFS= read -r file; do
    # Look for lines that reference .claude/projects/-Users-... /memory
    # (note: rg-ish pattern — sticking to portable grep)
    matches=$(grep -nE '\.claude/projects/-Users-[A-Za-z_-]+/memory' "$file" 2>/dev/null || true)
    if [ -n "$matches" ]; then
        # Exclude lines that also contain <cwd-slug> or are clearly documentation/examples
        filtered=$(echo "$matches" | grep -v '<cwd-slug>' | grep -v '# example' || true)
        if [ -n "$filtered" ]; then
            echo ""
            echo "✗ HARDCODED MEMORY PATH in $file:"
            echo "$filtered" | sed 's/^/    /'
            echo "  → Use the template form: ~/.claude/projects/<cwd-slug>/memory/"
            VIOLATIONS=$((VIOLATIONS + 1))
        fi
    fi
done < <(find "$SCAN_DIR" -type f -name "*.md" ! -name "*.bak")

# Pattern 2: hardcoded /Users/<name>/ anywhere in command files — paths should be
# $HOME / ~ or derived, not absolute.
while IFS= read -r file; do
    matches=$(grep -nE '/Users/[a-zA-Z][a-zA-Z0-9_-]+/' "$file" 2>/dev/null || true)
    if [ -n "$matches" ]; then
        # Allow documentation examples that clearly label themselves
        filtered=$(echo "$matches" | grep -v '# example\|e\.g\.\|<user>' || true)
        if [ -n "$filtered" ]; then
            echo ""
            echo "⚠ ABSOLUTE USER-SPECIFIC PATH in $file:"
            echo "$filtered" | sed 's/^/    /'
            echo "  → Consider \$HOME, ~, or a <placeholder>."
            VIOLATIONS=$((VIOLATIONS + 1))
        fi
    fi
done < <(find "$SCAN_DIR" -type f -name "*.md" ! -name "*.bak")

echo ""
if [ "$VIOLATIONS" -eq 0 ]; then
    echo "✓ No violations. All command templates use portable path forms."
    exit 0
else
    echo "✗ Found $VIOLATIONS violation(s). Fix before committing."
    exit 1
fi
