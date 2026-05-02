#!/usr/bin/env bash
##############################################################################
# tests/test-bump-version.sh
#
# Tests scripts/bump-version.sh against an isolated git repo so we don't
# touch the real VERSION/tags. Verifies:
#   1. patch bump: 0.4.21 → 0.4.22 + commit + tag
#   2. minor bump: 0.4.21 → 0.5.0
#   3. major bump: 0.4.21 → 1.0.0
#   4. refuses dirty tree
#   5. refuses non-main without --force-branch
#   6. refuses if tag already exists
#   7. --dry-run makes no changes
#   8. invalid part arg exits 2
##############################################################################
set -uo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ENGINE_DIR/scripts/bump-version.sh"

if [ ! -x "$SCRIPT" ]; then
  echo "✗ setup: $SCRIPT not executable"
  exit 2
fi

PASS=0
FAIL=0

# Build a sandbox repo that mimics MonsterFlow's layout.
make_sandbox() {
  local dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/test-bump-XXXXXX")"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email "test@local"
  git -C "$dir" config user.name "Test"
  echo "0.4.21" > "$dir/VERSION"
  mkdir -p "$dir/scripts"
  cp "$SCRIPT" "$dir/scripts/bump-version.sh"
  chmod +x "$dir/scripts/bump-version.sh"
  git -C "$dir" add .
  git -C "$dir" commit -q -m "init"
  echo "$dir"
}

run_in() {
  local dir="$1"; shift
  ( cd "$dir" && "$dir/scripts/bump-version.sh" "$@" ) 2>&1
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "✓ $label"
    PASS=$(( PASS + 1 ))
  else
    echo "✗ $label — expected '$expected', got '$actual'"
    FAIL=$(( FAIL + 1 ))
  fi
}

assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "✓ $label (exit $expected)"
    PASS=$(( PASS + 1 ))
  else
    echo "✗ $label — expected exit $expected, got $actual"
    FAIL=$(( FAIL + 1 ))
  fi
}

# 1. patch bump
SB="$(make_sandbox)"
run_in "$SB" patch >/dev/null 2>&1
assert_eq "patch bump version" "0.4.22" "$(tr -d '[:space:]' < "$SB/VERSION")"
if git -C "$SB" rev-parse -q --verify "refs/tags/v0.4.22" >/dev/null; then
  echo "✓ patch bump tag v0.4.22 created"
  PASS=$(( PASS + 1 ))
else
  echo "✗ patch bump tag v0.4.22 not created"
  FAIL=$(( FAIL + 1 ))
fi
rm -rf "$SB"

# 2. minor bump
SB="$(make_sandbox)"
run_in "$SB" minor >/dev/null 2>&1
assert_eq "minor bump version" "0.5.0" "$(tr -d '[:space:]' < "$SB/VERSION")"
rm -rf "$SB"

# 3. major bump
SB="$(make_sandbox)"
run_in "$SB" major >/dev/null 2>&1
assert_eq "major bump version" "1.0.0" "$(tr -d '[:space:]' < "$SB/VERSION")"
rm -rf "$SB"

# 4. refuses dirty tree
SB="$(make_sandbox)"
echo "wip" > "$SB/dirty.txt"
EXIT=0
run_in "$SB" patch >/dev/null 2>&1 || EXIT=$?
assert_exit "refuses dirty tree" "1" "$EXIT"
assert_eq "VERSION unchanged after dirty refusal" "0.4.21" "$(tr -d '[:space:]' < "$SB/VERSION")"
rm -rf "$SB"

# 5. refuses non-main without --force-branch
SB="$(make_sandbox)"
git -C "$SB" checkout -q -b feature/x
EXIT=0
run_in "$SB" patch >/dev/null 2>&1 || EXIT=$?
assert_exit "refuses non-main branch" "1" "$EXIT"
# but --force-branch should work
EXIT=0
run_in "$SB" patch --force-branch >/dev/null 2>&1 || EXIT=$?
assert_exit "accepts --force-branch on feature branch" "0" "$EXIT"
rm -rf "$SB"

# 6. refuses if tag already exists
SB="$(make_sandbox)"
git -C "$SB" tag -a v0.4.22 -m "preexisting"
EXIT=0
run_in "$SB" patch >/dev/null 2>&1 || EXIT=$?
assert_exit "refuses preexisting tag" "1" "$EXIT"
rm -rf "$SB"

# 7. --dry-run makes no changes
SB="$(make_sandbox)"
HEAD_BEFORE="$(git -C "$SB" rev-parse HEAD)"
run_in "$SB" patch --dry-run >/dev/null 2>&1
assert_eq "dry-run leaves VERSION unchanged" "0.4.21" "$(tr -d '[:space:]' < "$SB/VERSION")"
HEAD_AFTER="$(git -C "$SB" rev-parse HEAD)"
assert_eq "dry-run leaves HEAD unchanged" "$HEAD_BEFORE" "$HEAD_AFTER"
rm -rf "$SB"

# 8. invalid part exits 2
SB="$(make_sandbox)"
EXIT=0
run_in "$SB" garbage >/dev/null 2>&1 || EXIT=$?
assert_exit "invalid part arg" "2" "$EXIT"
rm -rf "$SB"

echo ""
echo "bump-version tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
