#!/bin/bash
# doctor.sh — Generate a diagnostic report and auto-file it as a GitHub Issue.
#
# Usage: ./scripts/doctor.sh
#
# Captures environment + Claude Code install state, writes a markdown report
# to a temp file, then opens a GitHub Issue on Jstottlemyer/claude-workflow
# via gh. Requires: gh auth login already completed.

set -uo pipefail  # intentionally NOT -e — we want all diagnostics to run even if some probes fail

REPO="Jstottlemyer/claude-workflow"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKFLOW_VERSION="$(cat "$SCRIPT_DIR/../VERSION" 2>/dev/null | tr -d '[:space:]' || echo 'unknown')"
DIAG_FILE=$(mktemp -t doctor-diagnostic.XXXXXX.md)
trap 'rm -f "$DIAG_FILE"' EXIT

# --- Gather diagnostics into $DIAG_FILE ---

{
    echo "# Install Diagnostic"
    echo ""
    echo "**Generated:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "**Pipeline version:** v${WORKFLOW_VERSION}"
    echo "**Host:** \`$(hostname)\`"
    echo "**User:** \`$(whoami)\`"
    echo ""

    echo "## System"
    echo '```'
    uname -a 2>&1 || echo "uname failed"
    sw_vers 2>&1 || echo "sw_vers not available (non-macOS?)"
    echo "SHELL=$SHELL"
    echo "bash: $(bash --version | head -1)"
    echo '```'
    echo ""

    echo "## CLI Versions"
    echo '```'
    echo "claude:  $(claude --version 2>&1 || echo 'NOT INSTALLED')"
    echo "gh:      $(gh --version 2>&1 | head -1 || echo 'NOT INSTALLED')"
    echo "git:     $(git --version 2>&1 || echo 'NOT INSTALLED')"
    echo "python3: $(python3 --version 2>&1 || echo 'NOT INSTALLED')"
    echo '```'
    echo ""

    echo "## ~/.claude/commands/"
    echo '```'
    ls -la "$HOME/.claude/commands/" 2>&1 || echo "(directory missing)"
    echo '```'
    echo ""

    echo "## ~/.claude/personas/ (top-level + subdirs)"
    echo '```'
    ls -la "$HOME/.claude/personas/" 2>&1 || echo "(directory missing)"
    for sub in check code-review plan review; do
        echo ""
        echo "--- personas/$sub ---"
        ls -la "$HOME/.claude/personas/$sub/" 2>&1 || echo "(subdir missing)"
    done
    echo '```'
    echo ""

    echo "## ~/.claude/domain-agents/"
    echo '```'
    if [ -d "$HOME/.claude/domain-agents" ]; then
        ls -la "$HOME/.claude/domain-agents/" 2>&1
        for sub in "$HOME/.claude/domain-agents"/*; do
            [ -d "$sub" ] || continue
            echo ""
            echo "--- $(basename "$sub") ---"
            ls -la "$sub" 2>&1
        done
    else
        echo "(directory missing — install.sh may need re-running with latest pull)"
    fi
    echo '```'
    echo ""

    echo "## ~/.claude/templates/"
    echo '```'
    ls -la "$HOME/.claude/templates/" 2>&1 || echo "(directory missing)"
    echo '```'
    echo ""

    echo "## Symlink Validity Check"
    echo '```'
    broken=0
    for dir in "$HOME/.claude/commands" "$HOME/.claude/personas" "$HOME/.claude/domain-agents" "$HOME/.claude/templates"; do
        [ -d "$dir" ] || continue
        while IFS= read -r -d '' link; do
            target=$(readlink "$link" 2>/dev/null) || continue
            if [ ! -e "$link" ]; then
                echo "BROKEN: $link -> $target"
                broken=$((broken + 1))
            fi
        done < <(find "$dir" -type l -print0 2>/dev/null)
    done
    if [ "$broken" -eq 0 ]; then
        echo "All symlinks resolve ✓"
    else
        echo ""
        echo "$broken broken symlink(s) found."
    fi
    echo '```'
    echo ""

    echo "## Plugin Cache"
    echo '```'
    if [ -d "$HOME/.claude/plugins/cache/claude-plugins-official" ]; then
        ls "$HOME/.claude/plugins/cache/claude-plugins-official/" 2>&1
    else
        echo "(no plugin cache — plugins not installed?)"
    fi
    echo '```'
    echo ""

    echo "## Settings"
    echo '```'
    if [ -L "$HOME/.claude/settings.json" ]; then
        echo "settings.json → $(readlink "$HOME/.claude/settings.json")"
    elif [ -f "$HOME/.claude/settings.json" ]; then
        echo "settings.json is a regular file (install.sh did not symlink)"
    else
        echo "settings.json missing"
    fi
    echo '```'
    echo ""

    echo "## Persona Metrics"
    echo '```'
    REPO="$SCRIPT_DIR/.."
    PM_FAILS=0

    # 1. Prompt symlinks
    echo "--- prompt symlinks ---"
    for p in snapshot findings-emit survival-classifier; do
        target="$HOME/.claude/commands/_prompts/${p}.md"
        if [ -L "$target" ]; then
            echo "ok   $target"
        else
            echo "MISS $target"
            PM_FAILS=$((PM_FAILS+1))
        fi
    done
    echo ""

    # 2. Schema files parse as valid JSON
    echo "--- schemas ---"
    for s in findings participation survival run; do
        schema_file="$REPO/schemas/${s}.schema.json"
        if [ -f "$schema_file" ]; then
            if python3 -c "import json,sys; json.load(open('$schema_file'))" 2>/dev/null; then
                echo "ok   $schema_file (valid JSON)"
            else
                echo "FAIL $schema_file (invalid JSON)"
                PM_FAILS=$((PM_FAILS+1))
            fi
        else
            echo "MISS $schema_file"
            PM_FAILS=$((PM_FAILS+1))
        fi
    done
    echo ""

    # 3. Prompt-version drift grep (compare prompt header version to schema example)
    echo "--- prompt_version drift ---"
    for prompt in snapshot findings-emit survival-classifier; do
        prompt_file="$REPO/commands/_prompts/${prompt}.md"
        if [ -f "$prompt_file" ]; then
            ver=$(grep -oE "${prompt}@[0-9]+\.[0-9]+" "$prompt_file" | head -1)
            if [ -n "$ver" ]; then
                count=$(grep -c "$ver" "$prompt_file")
                echo "ok   ${prompt}.md → $ver (mentioned $count× in file)"
            else
                echo "WARN ${prompt}.md → no prompt_version string found"
                PM_FAILS=$((PM_FAILS+1))
            fi
        fi
    done
    echo ""

    # 4. Fixture-based canonicalization check
    echo "--- canonicalization fixture ---"
    fixture_input="$REPO/tests/fixtures/normalized_signature/input.txt"
    fixture_expected="$REPO/tests/fixtures/normalized_signature/expected.hex"
    if [ -f "$fixture_input" ] && [ -f "$fixture_expected" ]; then
        actual=$(python3 -c "
import unicodedata, hashlib, re
with open('$fixture_input') as f:
    lines = [l for l in f.read().split('\n') if l.strip()]
canon = sorted(re.sub(r'\s+', ' ', unicodedata.normalize('NFC', l).lower()).strip() for l in lines)
print(hashlib.sha256('\n'.join(canon).encode('utf-8')).hexdigest())
" 2>/dev/null)
        expected=$(tr -d '[:space:]' < "$fixture_expected")
        if [ "$actual" = "$expected" ]; then
            echo "ok   canonicalization output matches expected.hex"
            echo "     ($actual)"
        else
            echo "FAIL canonicalization drift"
            echo "     expected: $expected"
            echo "     actual:   $actual"
            PM_FAILS=$((PM_FAILS+1))
        fi
    else
        echo "MISS fixture files (run install.sh from a checkout that includes tests/fixtures/)"
        PM_FAILS=$((PM_FAILS+1))
    fi
    echo ""

    # 5. Atomic-write fixture (informational — full sandbox check happens in T23)
    echo "--- atomic-write directive ---"
    for prompt in snapshot findings-emit survival-classifier; do
        prompt_file="$REPO/commands/_prompts/${prompt}.md"
        if [ -f "$prompt_file" ] && grep -q "os.replace" "$prompt_file"; then
            echo "ok   ${prompt}.md mentions os.replace (atomic write)"
        else
            echo "WARN ${prompt}.md missing os.replace mention"
            PM_FAILS=$((PM_FAILS+1))
        fi
    done
    echo ""

    if [ "$PM_FAILS" -eq 0 ]; then
        echo "Persona Metrics: all checks passed ✓"
    else
        echo "Persona Metrics: $PM_FAILS check(s) failed — see above"
    fi
    echo '```'
    echo ""

    echo "## Workflow Clone State"
    echo '```'
    CLONE="$HOME/Projects/claude-workflow"
    if [ -d "$CLONE/.git" ]; then
        echo "Path: $CLONE"
        echo ""
        echo "--- git log ---"
        git -C "$CLONE" log --oneline -5 2>&1
        echo ""
        echo "--- git status ---"
        git -C "$CLONE" status --short 2>&1 || echo "(clean)"
        echo ""
        echo "--- remote ---"
        git -C "$CLONE" remote -v 2>&1
    else
        echo "(clone not found at $CLONE)"
    fi
    echo '```'
    echo ""

    echo "## User-level CLAUDE.md"
    echo '```'
    if [ -f "$HOME/CLAUDE.md" ]; then
        echo "~/CLAUDE.md exists ($(wc -l < "$HOME/CLAUDE.md") lines)"
    else
        echo "~/CLAUDE.md missing — create one for your personal context (see QUICKSTART section 3)"
    fi
    echo '```'
} > "$DIAG_FILE"

# --- File the issue via gh ---

if ! command -v gh >/dev/null 2>&1; then
    echo "Error: gh CLI not installed. Install with: brew install gh && gh auth login" >&2
    echo ""
    echo "Diagnostic written to: $DIAG_FILE"
    echo "Paste this into an issue at https://github.com/${REPO}/issues manually."
    trap - EXIT  # don't delete on error so user can see it
    exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
    echo "Error: gh not authenticated. Run: gh auth login" >&2
    echo ""
    echo "Diagnostic written to: $DIAG_FILE"
    trap - EXIT
    exit 1
fi

TITLE="Diagnostic: $(hostname) $(date -u +%Y-%m-%dT%H:%M:%SZ)"

URL=$(gh issue create \
    --repo "$REPO" \
    --title "$TITLE" \
    --body-file "$DIAG_FILE" \
    --label "diagnostic" 2>&1) || {
    echo "Failed to file issue. Diagnostic written to: $DIAG_FILE" >&2
    echo "Error output above. You can open an issue manually at https://github.com/${REPO}/issues" >&2
    trap - EXIT
    exit 1
}

echo "Diagnostic filed:"
echo "$URL"
