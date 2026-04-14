#!/bin/bash
set -euo pipefail

# Claude Workflow Pipeline — Install Script
# Symlinks pipeline files into the correct locations

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo "=== Claude Workflow Pipeline Installer ==="
echo ""
echo "Repo:   $REPO_DIR"
echo "Target: $CLAUDE_DIR"
echo ""

# --- Helper ---
link_file() {
    local src="$1"
    local dst="$2"
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        echo "  BACKUP: $dst → ${dst}.bak"
        mv "$dst" "${dst}.bak"
    fi
    ln -sf "$src" "$dst"
    echo "  LINKED: $dst → $src"
}

# --- Ensure directories exist ---
mkdir -p "$CLAUDE_DIR/commands"
mkdir -p "$CLAUDE_DIR/personas"
mkdir -p "$CLAUDE_DIR/templates"

# --- Pipeline commands ---
echo "Installing pipeline commands..."
for cmd in "$REPO_DIR"/commands/*.md; do
    link_file "$cmd" "$CLAUDE_DIR/commands/$(basename "$cmd")"
done

# --- Personas ---
echo ""
echo "Installing agent personas..."
for stage in check code-review plan review; do
    mkdir -p "$CLAUDE_DIR/personas/$stage"
    for persona in "$REPO_DIR"/personas/"$stage"/*.md; do
        link_file "$persona" "$CLAUDE_DIR/personas/$stage/$(basename "$persona")"
    done
done

# --- Templates ---
echo ""
echo "Installing templates..."
for tmpl in "$REPO_DIR"/templates/*.md; do
    link_file "$tmpl" "$CLAUDE_DIR/templates/$(basename "$tmpl")"
done

# --- Settings ---
echo ""
echo "Installing settings..."
link_file "$REPO_DIR/settings/settings.json" "$CLAUDE_DIR/settings.json"

# --- Scripts ---
echo ""
echo "Installing scripts..."
mkdir -p "$CLAUDE_DIR/scripts"
for script in "$REPO_DIR"/scripts/*.py "$REPO_DIR"/scripts/*.sh; do
    [ -e "$script" ] || continue
    link_file "$script" "$CLAUDE_DIR/scripts/$(basename "$script")"
done

# --- Plugin installation ---
echo ""
read -rp "Install required plugins now? [y/N]: " INSTALL_PLUGINS
if [[ "$INSTALL_PLUGINS" =~ ^[Yy]$ ]]; then
    echo "Installing required plugins..."
    claude plugins install superpowers context7 || echo "  Plugin install requires Claude Code CLI"

    read -rp "Also install recommended plugins? [y/N]: " INSTALL_REC
    if [[ "$INSTALL_REC" =~ ^[Yy]$ ]]; then
        claude plugins install firecrawl code-review ralph-loop playwright || echo "  Some plugins may have failed"
    fi
fi

echo ""
echo "=== Installation complete ==="
echo ""
echo "Installed:"
echo "  - 8 pipeline commands (/kickoff → /brainstorm → /review → /plan → /check → /build + /flow + /wrap)"
echo "  - 27 agent personas (review, plan, check, code-review)"
echo "  - 1 constitution template"
echo "  - Settings with pipeline-optimized permissions"
echo "  - Scripts (session-cost.py)"
echo ""
echo "Next steps:"
echo "  1. Create a ~/CLAUDE.md with your personal context"
echo "  2. Review ~/.claude/settings.json and adjust permissions"
echo "  3. See plugins.md for optional plugins"
echo ""
echo "Run /flow in Claude Code to see the workflow reference card."
