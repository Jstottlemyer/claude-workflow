#!/usr/bin/env bash
##############################################################################
# scripts/install-hooks.sh
#
# Symlinks tracked git hooks from scripts/hooks/ into .git/hooks/ so they
# fire on commit. Idempotent — re-runs replace existing symlinks.
#
# Currently installs:
#   post-commit  → auto-bump VERSION + tag based on conventional-commit
#                  prefix (feat → minor, fix/docs/etc → patch, BREAKING → major)
#                  on main only. See scripts/hooks/post-commit for rules.
#
# Run once after clone:
#   bash scripts/install-hooks.sh
#
# Run --uninstall to remove:
#   bash scripts/install-hooks.sh --uninstall
##############################################################################
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_SRC="$REPO_DIR/scripts/hooks"
HOOKS_DST="$REPO_DIR/.git/hooks"
MODE="${1:-install}"

if [ ! -d "$HOOKS_DST" ]; then
  echo "✗ no .git/hooks dir at $HOOKS_DST — is this a git repo?"
  exit 1
fi

if [ "$MODE" = "--uninstall" ]; then
  for hook in "$HOOKS_SRC"/*; do
    name="$(basename "$hook")"
    target="$HOOKS_DST/$name"
    if [ -L "$target" ]; then
      rm "$target"
      echo "✓ removed $target"
    fi
  done
  exit 0
fi

for hook in "$HOOKS_SRC"/*; do
  name="$(basename "$hook")"
  target="$HOOKS_DST/$name"
  chmod +x "$hook"
  ln -sf "$hook" "$target"
  echo "✓ linked $target → $hook"
done

# `git push` should follow tags so auto-bump tags push with main.
git -C "$REPO_DIR" config --local push.followTags true
echo "✓ git config push.followTags = true (tags push automatically)"

echo ""
echo "Auto-bump rules (commits on main only):"
echo "  feat: …                       → minor bump"
echo "  fix: / docs: / chore: / etc.  → patch bump"
echo "  BREAKING CHANGE: in body, or"
echo "  type!: …                      → major bump"
echo "  [skip-auto-bump] anywhere in msg   → no bump"
echo ""
echo "Recursion-safe: the auto-generated 'chore: bump version to X.Y.Z'"
echo "commit doesn't trigger another bump."
