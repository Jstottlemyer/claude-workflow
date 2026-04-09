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

# --- Mode selection ---
echo "Install mode:"
echo "  1) Pipeline only — commands, personas, templates, settings (recommended)"
echo "  2) Full setup  — pipeline + shell config + scripts (repo maintainer only)"
echo ""
read -rp "Choose [1/2]: " MODE

if [[ "$MODE" != "1" && "$MODE" != "2" ]]; then
    echo "Invalid choice. Exiting."
    exit 1
fi

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

link_dir() {
    local src="$1"
    local dst="$2"
    if [ -d "$dst" ] && [ ! -L "$dst" ]; then
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
mkdir -p "$HOME/scripts"

# --- Pipeline commands ---
echo ""
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

# --- Personal mode extras ---
if [[ "$MODE" == "2" ]]; then
    echo ""
    echo "Installing shell config..."
    link_file "$REPO_DIR/shell/.tmux.conf" "$HOME/.tmux.conf"
    link_file "$REPO_DIR/shell/.zshrc" "$HOME/.zshrc"
    if [ -f "$REPO_DIR/shell/.zprofile" ]; then
        link_file "$REPO_DIR/shell/.zprofile" "$HOME/.zprofile"
    fi

    echo ""
    echo "Installing scripts..."
    for script in "$REPO_DIR"/scripts/*.sh; do
        link_file "$script" "$HOME/scripts/$(basename "$script")"
        chmod +x "$script"
    done

    # Personal CLAUDE.md
    if [ -f "$REPO_DIR/personal/CLAUDE.md" ]; then
        echo ""
        echo "Installing personal CLAUDE.md..."
        link_file "$REPO_DIR/personal/CLAUDE.md" "$HOME/CLAUDE.md"
    else
        echo ""
        echo "NOTE: No personal/CLAUDE.md found."
        echo "  Copy CLAUDE.md.template to personal/CLAUDE.md and customize it."
    fi

    # Personal .gitconfig
    if [ -f "$REPO_DIR/personal/.gitconfig" ]; then
        link_file "$REPO_DIR/personal/.gitconfig" "$HOME/.gitconfig"
    fi
else
    echo ""
    echo "Shared mode — skipping shell config and personal files."
    echo ""
    echo "Next steps:"
    echo "  1. Copy CLAUDE.md.template to ~/CLAUDE.md and customize it"
    echo "  2. Review settings/settings.json and adjust permissions"
    echo "  3. Install plugins: see plugins.md"
fi

# --- Plugin installation prompt ---
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
if [[ "$MODE" == "2" ]]; then
    echo "  - Shell config (.tmux.conf, .zshrc, .zprofile)"
    echo "  - Dev scripts (dev-session.sh, ssh-setup.sh)"
    echo "  - Personal CLAUDE.md"
fi
echo ""
echo "Run /flow in Claude Code to see the workflow reference card."
