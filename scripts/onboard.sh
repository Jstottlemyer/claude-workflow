#!/bin/bash
# scripts/onboard.sh — post-install onboarding panel
#
# Re-run anytime:
#   bash ~/Projects/MonsterFlow/scripts/onboard.sh
#
# Honours env vars set by install.sh:
#   MONSTERFLOW_NON_INTERACTIVE=1  — suppress interactive prompts
#   MONSTERFLOW_FORCE_ONBOARD=1    — run panel even if non-interactive
#
# Standalone and re-runnable: install.sh need not have just run.

set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"

# 1. doctor.sh — verify wiring (failure printed but non-fatal)
if [ -x "$REPO_DIR/scripts/doctor.sh" ]; then
    bash "$REPO_DIR/scripts/doctor.sh" || true
fi

# 2. The boxed panel — MUST contain literal substrings /flow, /spec,
# dashboard/index.html (acceptance test asserts these). Per UX spec the
# panel is 64 cols wide; content lines pad to keep right-border alignment
# in modern terminals, but content survives if the box-drawing chars
# render as `?` in a degraded terminal.
cat <<'PANEL'

╭─ MonsterFlow is ready ───────────────────────────────────────╮
│                                                              │
│  Next steps:                                                 │
│    1. cd into a project                                      │
│    2. /flow            — see the workflow card               │
│    3. /spec            — design your first feature           │
│    4. open ~/Projects/MonsterFlow/dashboard/index.html       │
│                                                              │
PANEL

# Per-system optional offers (only when interactive AND signal exists)
NON_INTERACTIVE="${MONSTERFLOW_NON_INTERACTIVE:-0}"
[ ! -t 0 ] && NON_INTERACTIVE=1   # auto-detect

# MONSTERFLOW_FORCE_ONBOARD=1 — let install.sh force the panel even when
# non-interactive (panel still prints; the per-prompt offers below remain
# guarded by NON_INTERACTIVE so we never block on stdin in CI).

# Helper: bash trap-alarm 5s timeout for `gh auth status`
# (per plan D9 — corporate-proxy hang protection; macOS lacks GNU `timeout`).
gh_auth_check_with_timeout() {
    local pid result watchdog
    ( gh auth status >/dev/null 2>&1 ) &
    pid=$!
    ( sleep 5 && kill -INT "$pid" 2>/dev/null ) &
    watchdog=$!
    wait "$pid" 2>/dev/null
    result=$?
    kill "$watchdog" 2>/dev/null || true
    return "$result"
}

if [ "$NON_INTERACTIVE" = "0" ]; then
    echo "│  Optional:                                                   │"
    # graphify offer — gates on ~/.local/share/MonsterFlow/.last-graphify-run mtime
    if [ -x "$REPO_DIR/scripts/bootstrap-graphify.sh" ]; then
        STAMP="$HOME/.local/share/MonsterFlow/.last-graphify-run"
        OFFER_GRAPHIFY=1
        if [ -f "$STAMP" ] && [ -n "$(find "$STAMP" -mtime -7 2>/dev/null)" ]; then
            OFFER_GRAPHIFY=0   # ran recently
        fi
        if [ "$OFFER_GRAPHIFY" = "1" ]; then
            GIDX=""
            read -rp "    • Index ~/Projects/ for the dashboard? [y/N]: " GIDX || GIDX=""
            if [[ "$GIDX" =~ ^[Yy]$ ]]; then
                bash "$REPO_DIR/scripts/bootstrap-graphify.sh" || true
                mkdir -p "$(dirname "$STAMP")"
                touch "$STAMP"
            fi
        fi
    fi
    # gh offer — only if installed AND unauthenticated (with timeout)
    if command -v gh >/dev/null 2>&1; then
        if ! gh_auth_check_with_timeout; then
            GAUTH=""
            read -rp "    • Authenticate gh CLI now? [y/N]: " GAUTH || GAUTH=""
            if [[ "$GAUTH" =~ ^[Yy]$ ]]; then
                gh auth login || true
            fi
        fi
    fi
fi

# Codex one-line opt-in (no prompt — informational)
if ! command -v codex >/dev/null 2>&1; then
    echo "│    • Want adversarial review? Run /codex:setup               │"
fi

cat <<'PANEL'
│                                                              │
╰──────────────────────────────────────────────────────────────╯

PANEL
