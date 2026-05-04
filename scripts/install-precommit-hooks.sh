#!/usr/bin/env bash
# Adopter-installable opt-in pre-commit hook for token-economics.
# Runs tests/test-allowlist.sh whenever tests/fixtures/persona-attribution/**
# or dashboard/data/** are staged, blocking commits that would leak finding
# content past the allowlist gate.
#
# Re-runnable: detects an existing pre-commit hook and either appends our
# block (with sentinel comments) or skips if already installed.
#
# Justin's CLAUDE.md context: this is opt-in, not auto-enabled. Defense in
# depth — A10 catches the leak at PR review even without this hook.

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK_PATH="$REPO_ROOT/.git/hooks/pre-commit"
SENTINEL_BEGIN="# >>> token-economics allowlist hook (managed) >>>"
SENTINEL_END="# <<< token-economics allowlist hook (managed) <<<"

HOOK_BLOCK="$SENTINEL_BEGIN
# Auto-installed by scripts/install-precommit-hooks.sh
# Runs tests/test-allowlist.sh when fixtures or generated data are staged.
if git diff --cached --name-only | grep -E '^(tests/fixtures/persona-attribution/|dashboard/data/)' > /dev/null; then
    bash \"\$(git rev-parse --show-toplevel)/tests/test-allowlist.sh\" || {
        echo 'pre-commit: token-economics allowlist test failed — staged fixtures/data may leak finding content.'
        echo 'Fix the fixture or skip with: git commit --no-verify (NOT recommended for public-release).'
        exit 1
    }
fi
$SENTINEL_END"

# Idempotency: if our sentinel block is already present, do nothing
if [ -f "$HOOK_PATH" ] && grep -F "$SENTINEL_BEGIN" "$HOOK_PATH" > /dev/null 2>&1; then
    echo "[install-precommit-hooks] hook block already installed (idempotent no-op)"
    exit 0
fi

# Compose with existing hook: prepend our block (so we run before any user logic)
# OR if no hook exists, create one with shebang
if [ -f "$HOOK_PATH" ]; then
    EXISTING=$(cat "$HOOK_PATH")
    {
        echo "#!/usr/bin/env bash"
        echo "$HOOK_BLOCK"
        echo ""
        # Strip shebang from existing if present, append the rest
        echo "$EXISTING" | sed '1{/^#!/d;}'
    } > "$HOOK_PATH.tmp"
    mv "$HOOK_PATH.tmp" "$HOOK_PATH"
    echo "[install-precommit-hooks] composed with existing pre-commit hook"
else
    {
        echo "#!/usr/bin/env bash"
        echo "$HOOK_BLOCK"
    } > "$HOOK_PATH"
    echo "[install-precommit-hooks] installed new pre-commit hook"
fi

chmod +x "$HOOK_PATH"
echo "[install-precommit-hooks] DONE — re-run is idempotent"
