#!/usr/bin/env bash
##############################################################################
# scripts/bump-version.sh
#
# Bump VERSION + create annotated git tag. Implementation backing the
# /bump-version skill.
#
# Usage:
#   bash scripts/bump-version.sh <major|minor|patch> [--force-branch] [--dry-run]
#
# Exit codes:
#   0 — success
#   1 — pre-condition failed (dirty tree, wrong branch, tag exists)
#   2 — bad arguments
##############################################################################
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$REPO_DIR/VERSION"
PART="${1:-}"
FORCE_BRANCH=0
DRY_RUN=0

shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --force-branch) FORCE_BRANCH=1 ;;
    --dry-run)      DRY_RUN=1 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

case "$PART" in
  major|minor|patch) ;;
  *)
    echo "usage: $0 <major|minor|patch> [--force-branch] [--dry-run]" >&2
    exit 2
    ;;
esac

# --- Pre-conditions ---------------------------------------------------------
if [ ! -f "$VERSION_FILE" ]; then
  echo "✗ VERSION file not found at $VERSION_FILE" >&2
  exit 1
fi

CURRENT="$(tr -d '[:space:]' < "$VERSION_FILE")"
if [[ ! "$CURRENT" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "✗ VERSION '$CURRENT' is not semver (expected MAJOR.MINOR.PATCH)" >&2
  exit 1
fi

# Working tree clean?
if [ -n "$(git -C "$REPO_DIR" status --porcelain)" ]; then
  echo "✗ working tree not clean — commit or stash first" >&2
  git -C "$REPO_DIR" status --short >&2
  exit 1
fi

# On main?
BRANCH="$(git -C "$REPO_DIR" branch --show-current)"
if [ "$BRANCH" != "main" ] && [ "$FORCE_BRANCH" -ne 1 ]; then
  echo "✗ not on main (currently on '$BRANCH'); use --force-branch to override" >&2
  exit 1
fi

# --- Compute new version ----------------------------------------------------
IFS='.' read -r MAJ MIN PATCH <<< "$CURRENT"
case "$PART" in
  major) MAJ=$(( MAJ + 1 )); MIN=0; PATCH=0 ;;
  minor) MIN=$(( MIN + 1 )); PATCH=0 ;;
  patch) PATCH=$(( PATCH + 1 )) ;;
esac
NEW="${MAJ}.${MIN}.${PATCH}"
TAG="v${NEW}"

echo "Current: $CURRENT"
echo "New:     $NEW (${PART} bump)"

# Tag must not exist
if git -C "$REPO_DIR" rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
  echo "✗ local tag $TAG already exists" >&2
  exit 1
fi
if git -C "$REPO_DIR" ls-remote --tags origin "refs/tags/$TAG" 2>/dev/null | grep -q "$TAG"; then
  echo "✗ remote tag $TAG already exists on origin" >&2
  exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "(dry-run — no changes made)"
  exit 0
fi

# --- Apply ------------------------------------------------------------------
echo "$NEW" > "$VERSION_FILE"
echo "✓ VERSION updated"

# Sync hardcoded version pins in docs/index.html (eyebrow + Requirements)
# so the GitHub Pages site doesn't drift behind VERSION (was at v0.3.0 while
# VERSION had been bumped through 0.5/0.7 — caught during 0.8 cut).
INDEX_HTML="$REPO_DIR/docs/index.html"
if [ -f "$INDEX_HTML" ]; then
  if grep -qE "v${CURRENT//./\\.}\\b" "$INDEX_HTML"; then
    sed -i.bak -E "s/v${CURRENT//./\\.}([^[:digit:]]|\$)/v${NEW}\\1/g" "$INDEX_HTML"
    rm -f "$INDEX_HTML.bak"
    echo "✓ docs/index.html version pins updated"
  else
    echo "⚠ docs/index.html does not contain v${CURRENT} — manual review recommended"
  fi
fi

# Reminder: CHANGELOG.md is editorial — not auto-updated. The skill expects
# the operator to convert [Unreleased] → [<NEW>] before bumping. Warn if
# [Unreleased] still has content (likely forgot to cut the release header).
CHANGELOG="$REPO_DIR/CHANGELOG.md"
if [ -f "$CHANGELOG" ] && grep -qE "^## \\[Unreleased\\]" "$CHANGELOG"; then
  # Check if Unreleased section has any content (>= 1 non-empty non-header line after it before next ##)
  UNRELEASED_BODY="$(awk '/^## \[Unreleased\]/{flag=1; next} /^## /{flag=0} flag' "$CHANGELOG" | grep -cE '^[^[:space:]]')"
  if [ "$UNRELEASED_BODY" -gt 0 ]; then
    echo "⚠ CHANGELOG.md [Unreleased] section has content — convert to ## [$NEW] before tagging"
  fi
fi

git -C "$REPO_DIR" add VERSION
[ -f "$INDEX_HTML" ] && git -C "$REPO_DIR" add docs/index.html 2>/dev/null || true
git -C "$REPO_DIR" commit -q -m "chore: bump version to $NEW"
COMMIT_SHA="$(git -C "$REPO_DIR" rev-parse --short HEAD)"
echo "✓ commit created: $COMMIT_SHA chore: bump version to $NEW"

git -C "$REPO_DIR" tag -a "$TAG" -m "Release $TAG"
echo "✓ tag created: $TAG"

echo ""
echo "Next: git push origin main && git push origin $TAG"
