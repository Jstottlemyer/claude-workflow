#!/bin/bash
set -euo pipefail

# === Block 0: Function Definitions (no execution yet) ===
# These must be defined before they're called below.

parse_flags() {
    # Parse argv into env vars. Defaults: all flags off.
    SHOW_HELP=0
    NO_INSTALL=0
    INSTALL_THEME_FORCED=0   # --install-theme set
    NO_THEME=0               # wins over --install-theme
    NO_ONBOARD=0
    FORCE_ONBOARD=0
    NON_INTERACTIVE_FLAG=0   # explicit --non-interactive

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help)             SHOW_HELP=1 ;;
            --no-install)          NO_INSTALL=1 ;;
            --install-theme)       INSTALL_THEME_FORCED=1 ;;
            --no-theme)            NO_THEME=1 ;;
            --non-interactive)     NON_INTERACTIVE_FLAG=1 ;;
            --no-onboard)          NO_ONBOARD=1 ;;
            --force-onboard)       FORCE_ONBOARD=1 ;;
            *)                     echo "Unknown flag: $1" >&2; echo "Run with --help for usage." >&2; exit 2 ;;
        esac
        shift
    done

    # Resolve --non-interactive (explicit flag wins; else auto-detect via [ -t 0 ];
    # MONSTERFLOW_FORCE_INTERACTIVE=1 overrides auto-detect)
    if [ "$NON_INTERACTIVE_FLAG" = "1" ]; then
        NON_INTERACTIVE=1
    elif [ "${MONSTERFLOW_FORCE_INTERACTIVE:-0}" = "1" ]; then
        NON_INTERACTIVE=0
    elif [ -t 0 ]; then
        NON_INTERACTIVE=0
    else
        NON_INTERACTIVE=1
    fi

    export NO_INSTALL INSTALL_THEME_FORCED NO_THEME NON_INTERACTIVE NO_ONBOARD FORCE_ONBOARD
}

print_help() {
    cat <<'HELP'
MonsterFlow install.sh — Claude Workflow Pipeline installer

Usage: ./install.sh [flags]

Flags:
  -h, --help              Show this help and exit (no I/O)
  --no-install            Bypass ALL detection and enforcement (CI escape hatch)
  --install-theme         Force theme install (overrides default-N for adopters)
  --no-theme              Skip theme install (wins over --install-theme)
  --non-interactive       Disable all prompts; auto-detected when stdin is not a TTY
  --no-onboard            Suppress onboard panel
  --force-onboard         Run onboard panel even under --non-interactive

Env vars:
  MONSTERFLOW_OWNER=1|0           Force owner/adopter mode (test ergonomics)
  MONSTERFLOW_FORCE_INTERACTIVE=1 Override [ -t 0 ] auto-detect
  MONSTERFLOW_INSTALL_TEST=1      Short-circuit plugin/test prompts (test harness only)
  PERSONA_METRICS_GITIGNORE=1|0   Gitignore persona-metrics artifacts (1=adopter default)

For details: docs/specs/install-rewrite/spec.md
HELP
}

# === Block 1: Flag Parse (no I/O yet) ===
parse_flags "$@"
[ "$SHOW_HELP" = "1" ] && { print_help; exit 0; }

# === Block 2: OS Guards (no repo I/O yet) ===
if [ "$(uname)" != "Darwin" ]; then
    echo "MonsterFlow install.sh is macOS-only." >&2
    echo "Linux support tracked in BACKLOG.md as out-of-scope for v1." >&2
    exit 1
fi
MACOS_VER="$(sw_vers -productVersion 2>/dev/null || echo 0)"
MACOS_MAJOR="${MACOS_VER%%.*}"
# cmux requires macOS >= 14; if older, demote cmux from RECOMMENDED to OPTIONAL
CMUX_DEMOTE=0
if [ "${MACOS_MAJOR:-0}" -lt 14 ] 2>/dev/null; then
    CMUX_DEMOTE=1
fi

# === Block 3: Repo paths + banner (now safe to do I/O) ===
# Use pwd -P to resolve symlinks consistently with owner-detect logic
REPO_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CLAUDE_DIR="$HOME/.claude"
VERSION="$(cat "$REPO_DIR/VERSION" 2>/dev/null | tr -d '[:space:]' || echo 'unknown')"

# Source the python_pip helper (W1 task 1.6)
# python_pip auto-detects pip3 vs pip vs python3 -m pip; install.sh has zero pip
# calls today but the source is forward-compat plumbing.
[ -f "$REPO_DIR/scripts/lib/python-pip.sh" ] && . "$REPO_DIR/scripts/lib/python-pip.sh"

# Set HOMEBREW_NO_AUTO_UPDATE for the rest of the script — non-negotiable for
# the <3s repeat-run budget when brew is invoked.
export HOMEBREW_NO_AUTO_UPDATE=1

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

# Three tiers: REQUIRED (pipeline broken without), RECOMMENDED (features
# degrade silently — hooks no-op, /autorun can't make PRs, etc.), OPTIONAL
# (silent-skip features like Codex).
REQUIRED_MISSING=()
RECOMMENDED_MISSING=()
OPTIONAL_MISSING=()

# REQUIRED — pipeline cannot function without these
has_cmd git     || REQUIRED_MISSING+=("git — install Xcode CLI tools (xcode-select --install) or brew install git")
has_cmd claude  || REQUIRED_MISSING+=("claude (Claude Code CLI) — https://claude.com/claude-code")
has_cmd python3 || REQUIRED_MISSING+=("python3 — brew install python")

# Python version check (≥ 3.9 — older versions miss f-string and walrus features used in scripts)
if has_cmd python3; then
    PY_VER="$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null || echo "0.0")"
    PY_MAJ="${PY_VER%%.*}"
    PY_MIN="${PY_VER#*.}"
    if [ "${PY_MAJ:-0}" -lt 3 ] 2>/dev/null || { [ "${PY_MAJ:-0}" -eq 3 ] && [ "${PY_MIN:-0}" -lt 9 ]; } 2>/dev/null; then
        REQUIRED_MISSING+=("python3 ≥ 3.9 (detected $PY_VER) — brew install python")
    fi
fi

# RECOMMENDED — silently degraded features without them
has_cmd gh         || RECOMMENDED_MISSING+=("gh (GitHub CLI, /autorun needs it for PR ops) — brew install gh && gh auth login")
has_cmd shellcheck || RECOMMENDED_MISSING+=("shellcheck (PostToolUse hook on .sh edits — silently no-ops without it) — brew install shellcheck")
has_cmd jq         || RECOMMENDED_MISSING+=("jq (PostToolUse hook on .json edits — silently no-ops without it) — brew install jq")
has_cmd tmux       || RECOMMENDED_MISSING+=("tmux (recommended for overnight /autorun runs) — brew install tmux")

# PATH sanity — ~/.local/bin must be in PATH for `autorun` symlink to resolve
if ! echo ":$PATH:" | grep -q ":$HOME/.local/bin:"; then
    # shellcheck disable=SC2016  # literal $HOME/$PATH are intentional in the user-facing instruction
    RECOMMENDED_MISSING+=('$HOME/.local/bin not in PATH — add `export PATH="$HOME/.local/bin:$PATH"` to ~/.zshrc so `autorun` runs from anywhere')
fi

# OPTIONAL — features silent-skip when absent
has_cmd codex || OPTIONAL_MISSING+=("codex (adversarial review at /spec-review, /check, /build — silent skip) — npm i -g @openai/codex")

# Display findings, tier by tier
if [ ${#REQUIRED_MISSING[@]} -gt 0 ]; then
    echo "✗ REQUIRED — pipeline will not work without these:"
    for tool in "${REQUIRED_MISSING[@]}"; do echo "  - $tool"; done
    echo ""
fi
if [ ${#RECOMMENDED_MISSING[@]} -gt 0 ]; then
    echo "⚠ RECOMMENDED — features degrade silently without these:"
    for tool in "${RECOMMENDED_MISSING[@]}"; do echo "  - $tool"; done
    echo ""
fi
if [ ${#OPTIONAL_MISSING[@]} -gt 0 ]; then
    echo "○ OPTIONAL — silent skip if absent:"
    for tool in "${OPTIONAL_MISSING[@]}"; do echo "  - $tool"; done
    echo ""
fi

if [ ${#REQUIRED_MISSING[@]} -gt 0 ] || [ ${#RECOMMENDED_MISSING[@]} -gt 0 ]; then
    read -rp "Continue anyway? [Y/n]: " CONTINUE
    if [[ "$CONTINUE" =~ ^[Nn]$ ]]; then
        echo "Install missing tools, then re-run this script."
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
mkdir -p "$HOME/.local/bin"
ln -sf "$REPO_DIR/scripts/autorun/autorun" "$HOME/.local/bin/autorun"
echo "  LINKED: autorun -> $HOME/.local/bin/autorun"
# Owner vs adopter detection: OWNER=1 means install.sh ran from inside the
# MonsterFlow engine repo itself. Anything else is an adopter installing
# the engine into their own project. Basing this on PWD vs REPO_DIR (not
# basename) is robust to clones named "MonsterFlow" but used as engine.
OWNER=0
if [[ "$PWD" == "$REPO_DIR" ]]; then
    OWNER=1
fi

ADOPTER_ROOT=""
if [[ "$OWNER" -eq 0 && -d "$PWD/.git" ]]; then
    ADOPTER_ROOT="$PWD"
fi

# Create queue/ + .gitignore in BOTH the engine repo and the adopter project.
# autorun runs from $PROJECT_DIR (defaults to $PWD), so adopter projects need
# their own queue/.gitignore — otherwise specs, configs, run logs, and PR
# URLs leak into commits despite docs claiming "queue/ is gitignored."
write_queue_gitignore() {
    local target_dir="$1"
    mkdir -p "$target_dir"
    if [ ! -f "$target_dir/.gitignore" ]; then
        cat > "$target_dir/.gitignore" << 'GITIGNORE'
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
        echo "  CREATED: $target_dir/.gitignore"
    fi
}

write_queue_gitignore "$REPO_DIR/queue"
if [ -n "$ADOPTER_ROOT" ]; then
    write_queue_gitignore "$ADOPTER_ROOT/queue"
fi

# --- Persona Metrics: gitignore default-flip for adopters ---
# Owner (working ON MonsterFlow) → commit metrics (dogfood pattern).
# Adopter (using MonsterFlow) → gitignore metrics (may contain sensitive review prose).
# Override via PERSONA_METRICS_GITIGNORE=0 (commit) or =1 (gitignore).
PERSONA_METRICS_GITIGNORE_DEFAULT=1
if [[ "$OWNER" -eq 1 ]]; then
    PERSONA_METRICS_GITIGNORE_DEFAULT=0
fi
PERSONA_METRICS_GITIGNORE="${PERSONA_METRICS_GITIGNORE:-$PERSONA_METRICS_GITIGNORE_DEFAULT}"

if [[ "$PERSONA_METRICS_GITIGNORE" == "1" && -n "$ADOPTER_ROOT" ]]; then
    GITIGNORE="$ADOPTER_ROOT/.gitignore"
    BLOCK_BEGIN="# BEGIN persona-metrics (MonsterFlow)"
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

# --- Git hooks (auto-bump VERSION + tag) ---
# Wires up scripts/hooks/post-commit which auto-bumps VERSION + tags
# based on conventional-commit prefix (feat → minor, fix/docs/etc →
# patch, BREAKING CHANGE → major). Only fires on `main` branch.
# Idempotent — re-runs replace the symlink.
if [ -x "$REPO_DIR/scripts/install-hooks.sh" ] && [ -d "$REPO_DIR/.git/hooks" ]; then
    echo ""
    echo "Installing git hooks (auto-bump VERSION on commit)..."
    bash "$REPO_DIR/scripts/install-hooks.sh" 2>&1 | sed 's/^/  /'
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

# --- Validate install via test suite ---
if [ -x "$REPO_DIR/tests/run-tests.sh" ]; then
    echo ""
    read -rp "Run test suite to validate install? [Y/n]: " RUN_TESTS
    if [[ ! "$RUN_TESTS" =~ ^[Nn]$ ]]; then
        echo ""
        bash "$REPO_DIR/tests/run-tests.sh" || echo "⚠ some tests failed — investigate via 'bash tests/run-tests.sh'"
    fi
fi

echo ""
echo "=== Installation complete ==="
echo ""
echo "Installed:"
echo "  - 38 pipeline agents:"
echo "      29 pipeline personas (review 6, plan 7, check 5, code-review 9, judge, synthesis)"
echo "       9 domain agents (mobile 6, games 3) — available to /kickoff for per-project install"
echo "  - 10 pipeline commands (/kickoff → /spec → /spec-review → /plan → /check → /build + /autorun + /flow + /wrap + /bump-version)"
echo "  - 2 focused subagents (autorun-shell-reviewer, persona-metrics-validator)"
echo "  - 2 user-only skills (/autorun-dryrun, /bump-version)"
echo "  - 2 PostToolUse hooks (shellcheck on .sh, jq empty on .json) — advisory-only"
echo "  - 1 git post-commit hook (auto-bump VERSION + tag on main, conventional-commit driven)"
echo "  - 3 templates (constitution, repo-signals, CLAUDE.md baseline)"
echo "  - Settings with pipeline-optimized permissions"
echo "  - Scripts (session-cost.py, doctor.sh, statusline-command.sh, bump-version.sh)"
echo "  - Autorun pipeline (scripts/autorun/ + queue/ with .gitignore)"
echo "  - Test suite (tests/run-tests.sh — 5 files, 30+ assertions)"
echo ""
echo "Next steps:"
echo "  1. Customize ~/CLAUDE.md (copied from templates/CLAUDE.md — fill in your name, role, dev env)"
echo "  2. Review ~/.claude/settings.json and adjust permissions"
echo "  3. See plugins.md for optional plugins"
echo "  4. See QUICKSTART.md if this is your first time"
echo "  5. Auto-bump rules: feat:→minor · fix:/docs:/etc.→patch · type!: or BREAKING CHANGE:→major"
echo "  6. If anything looks off, run ./scripts/doctor.sh to file a diagnostic"
echo ""
echo "Run /flow in Claude Code to see the workflow reference card."
