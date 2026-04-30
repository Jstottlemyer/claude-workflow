#!/bin/bash
set -euo pipefail

# Claude Workflow Pipeline — Install Script
# Symlinks pipeline files into the correct locations

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
VERSION="$(cat "$REPO_DIR/VERSION" 2>/dev/null | tr -d '[:space:]' || echo 'unknown')"

echo "=== Claude Workflow Pipeline Installer — v${VERSION} ==="
echo ""
echo "Repo:   $REPO_DIR"
echo "Target: $CLAUDE_DIR"
echo ""

# --- Prerequisites (warn only, don't block) ---
# bash scripts don't inherit zsh's PATH from .zshrc, so brew-installed
# tools at /opt/homebrew/bin (Apple Silicon) or /usr/local/bin (Intel)
# may not be found by `command -v`. Check both.
has_cmd() {
    command -v "$1" >/dev/null 2>&1 \
        || [ -x "/opt/homebrew/bin/$1" ] \
        || [ -x "/usr/local/bin/$1" ]
}

MISSING=()
has_cmd claude  || MISSING+=("claude (Claude Code CLI) — https://claude.com/claude-code")
has_cmd gh      || MISSING+=("gh (GitHub CLI) — brew install gh && gh auth login")
has_cmd python3 || MISSING+=("python3 — brew install python")

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "Optional tools not detected (install works without them, but you'll want them):"
    for tool in "${MISSING[@]}"; do
        echo "  - $tool"
    done
    echo ""
    read -rp "Continue anyway? [Y/n]: " CONTINUE
    if [[ "$CONTINUE" =~ ^[Nn]$ ]]; then
        echo "Install a missing tool, then re-run this script."
        exit 0
    fi
    echo ""
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

# --- Ensure directories exist ---
mkdir -p "$CLAUDE_DIR/commands"
mkdir -p "$CLAUDE_DIR/personas"
mkdir -p "$CLAUDE_DIR/templates"

# --- Pipeline commands ---
echo "Installing pipeline commands..."
for cmd in "$REPO_DIR"/commands/*.md; do
    link_file "$cmd" "$CLAUDE_DIR/commands/$(basename "$cmd")"
done
# Static command assets (e.g., pre-rendered reference cards) — served via cat to skip LLM generation
for asset in "$REPO_DIR"/commands/*.txt; do
    [ -e "$asset" ] || continue
    link_file "$asset" "$CLAUDE_DIR/commands/$(basename "$asset")"
done

# --- Persona Metrics prompts (commands/_prompts/) ---
if [ -d "$REPO_DIR/commands/_prompts" ]; then
    echo ""
    echo "Installing persona-metrics prompts..."
    mkdir -p "$CLAUDE_DIR/commands/_prompts"
    for prompt in "$REPO_DIR"/commands/_prompts/*.md; do
        [ -e "$prompt" ] || continue
        link_file "$prompt" "$CLAUDE_DIR/commands/_prompts/$(basename "$prompt")"
    done
fi

# --- Personas ---
echo ""
echo "Installing agent personas..."
# Top-level personas (judge, synthesis — used by /spec-review, /plan, /check)
for persona in "$REPO_DIR"/personas/*.md; do
    [ -e "$persona" ] || continue
    link_file "$persona" "$CLAUDE_DIR/personas/$(basename "$persona")"
done
# Stage-specific personas
for stage in check code-review plan review; do
    mkdir -p "$CLAUDE_DIR/personas/$stage"
    for persona in "$REPO_DIR"/personas/"$stage"/*.md; do
        link_file "$persona" "$CLAUDE_DIR/personas/$stage/$(basename "$persona")"
    done
done

# --- Domain agents ---
# Link into a stable user-agnostic path so /kickoff can always find them
# regardless of where the user cloned the repo.
echo ""
echo "Installing domain agents..."
mkdir -p "$CLAUDE_DIR/domain-agents"
for domain_dir in "$REPO_DIR"/domains/*/agents; do
    [ -d "$domain_dir" ] || continue
    domain_name=$(basename "$(dirname "$domain_dir")")
    mkdir -p "$CLAUDE_DIR/domain-agents/$domain_name"
    for agent in "$domain_dir"/*.md; do
        [ -e "$agent" ] || continue
        link_file "$agent" "$CLAUDE_DIR/domain-agents/$domain_name/$(basename "$agent")"
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

# --- Autorun scripts ---
echo ""
echo "Installing autorun scripts..."
mkdir -p "$REPO_DIR/scripts/autorun"
find "$REPO_DIR/scripts/autorun" -type f \( -name "*.sh" -o -name "autorun" \) -exec chmod +x {} \;
mkdir -p "$REPO_DIR/queue"
if [ ! -f "$REPO_DIR/queue/.gitignore" ]; then
    cat > "$REPO_DIR/queue/.gitignore" << 'GITIGNORE'
# autorun queue — transient artifacts, never commit
autorun.config.json
*/
STOP
run.log
.current-stage
.autorun.lock
*.spec.md
*.prompt.txt
GITIGNORE
    echo "  CREATED: queue/.gitignore"
fi

# --- Persona Metrics: gitignore default-flip for adopters ---
# Adopter installs (any project NOT named 'claude-workflow') default to opt-in-to-commit
# for persona-metrics artifacts. claude-workflow's own repo overrides via name detection.
# Set PERSONA_METRICS_GITIGNORE=0 to override the adopter default and commit metrics.
PERSONA_METRICS_GITIGNORE_DEFAULT=1
if [[ "$(basename "$REPO_DIR")" == "claude-workflow" ]]; then
    PERSONA_METRICS_GITIGNORE_DEFAULT=0  # this repo's own dogfood pattern: commit metrics
fi
PERSONA_METRICS_GITIGNORE="${PERSONA_METRICS_GITIGNORE:-$PERSONA_METRICS_GITIGNORE_DEFAULT}"

# Find an adopter project root: cwd if it has a .git dir AND isn't this repo
ADOPTER_ROOT=""
if [[ "$PWD" != "$REPO_DIR" && -d "$PWD/.git" ]]; then
    ADOPTER_ROOT="$PWD"
fi

if [[ "$PERSONA_METRICS_GITIGNORE" == "1" && -n "$ADOPTER_ROOT" ]]; then
    GITIGNORE="$ADOPTER_ROOT/.gitignore"
    BLOCK_BEGIN="# BEGIN persona-metrics (claude-workflow)"
    BLOCK_END="# END persona-metrics"

    # Idempotent: check for sentinel before appending
    if [ ! -f "$GITIGNORE" ] || ! grep -qF "$BLOCK_BEGIN" "$GITIGNORE"; then
        echo ""
        echo "Persona Metrics: appending gitignore block to $GITIGNORE (PERSONA_METRICS_GITIGNORE=1)"
        touch "$GITIGNORE"
        {
            echo ""
            echo "$BLOCK_BEGIN"
            echo "# Auto-added by install.sh — measurement artifacts may contain sensitive review prose."
            echo "# Set PERSONA_METRICS_GITIGNORE=0 and re-run install.sh to commit metrics intentionally."
            echo "docs/specs/*/spec-review/findings*.jsonl"
            echo "docs/specs/*/spec-review/participation.jsonl"
            echo "docs/specs/*/spec-review/survival.jsonl"
            echo "docs/specs/*/spec-review/run.json"
            echo "docs/specs/*/spec-review/raw/"
            echo "docs/specs/*/spec-review/source.spec.md"
            echo "docs/specs/*/plan/findings*.jsonl"
            echo "docs/specs/*/plan/participation.jsonl"
            echo "docs/specs/*/plan/survival.jsonl"
            echo "docs/specs/*/plan/run.json"
            echo "docs/specs/*/plan/raw/"
            echo "docs/specs/*/check/findings*.jsonl"
            echo "docs/specs/*/check/participation.jsonl"
            echo "docs/specs/*/check/survival.jsonl"
            echo "docs/specs/*/check/run.json"
            echo "docs/specs/*/check/raw/"
            echo "docs/specs/*/check/source.plan.md"
            echo "docs/specs/*/.persona-metrics-warned"
            echo "$BLOCK_END"
        } >> "$GITIGNORE"
    fi
fi

# --- CLAUDE.md baseline ---
echo ""
GLOBAL_CLAUDE="$HOME/CLAUDE.md"
if [ ! -f "$GLOBAL_CLAUDE" ]; then
    read -rp "No ~/CLAUDE.md found. Copy baseline template? [Y/n]: " COPY_CLAUDE
    if [[ ! "$COPY_CLAUDE" =~ ^[Nn]$ ]]; then
        cp "$REPO_DIR/templates/CLAUDE.md" "$GLOBAL_CLAUDE"
        echo "  Copied templates/CLAUDE.md → ~/CLAUDE.md"
        echo "  Edit it to add your name, role, and personal context."
    fi
else
    python3 "$REPO_DIR/scripts/claude-md-merge.py" --target "$GLOBAL_CLAUDE" --template "$REPO_DIR/templates/CLAUDE.md"
fi

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
echo "  - 37 agents total:"
echo "      28 pipeline personas (review 6, plan 6, check 5, code-review 9, judge, synthesis)"
echo "       9 domain agents (mobile 6, games 3) — available to /kickoff for per-project install"
echo "  - 8 pipeline commands (/kickoff → /spec → /spec-review → /plan → /check → /build + /flow + /wrap)"
echo "  - 3 templates (constitution, repo-signals, CLAUDE.md baseline)"
echo "  - Settings with pipeline-optimized permissions"
echo "  - Scripts (session-cost.py, doctor.sh, statusline-command.sh)"
echo "  - Autorun pipeline (scripts/autorun/ + queue/ with .gitignore)"
echo ""
echo "Next steps:"
echo "  1. Customize ~/CLAUDE.md (copied from templates/CLAUDE.md — fill in your name, role, dev env)"
echo "  2. Review ~/.claude/settings.json and adjust permissions"
echo "  3. See plugins.md for optional plugins"
echo "  4. See QUICKSTART.md if this is your first time"
echo "  5. If anything looks off, run ./scripts/doctor.sh to file a diagnostic"
echo ""
echo "Run /flow in Claude Code to see the workflow reference card."
