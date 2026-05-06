#!/bin/bash
# Test: CHANGELOG.md contains a well-formed v0.9.0 entry documenting
# the pipeline-gate-permissiveness change.
#
# Race-safe: this test only reads CHANGELOG.md; no other files touched.

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHANGELOG="${REPO_ROOT}/CHANGELOG.md"

PASS=0
FAIL=0

assert_contains() {
    local needle="$1"
    local description="$2"
    if grep -qF -- "$needle" "$CHANGELOG"; then
        PASS=$((PASS + 1))
        echo "  PASS: ${description}"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: ${description}"
        echo "        expected to find: ${needle}"
    fi
}

echo "test-changelog-v0.9.0-entry.sh"
echo "------------------------------"

# 1. CHANGELOG.md exists
if [ ! -f "$CHANGELOG" ]; then
    echo "  FAIL: CHANGELOG.md not found at ${CHANGELOG}"
    exit 1
fi
PASS=$((PASS + 1))
echo "  PASS: CHANGELOG.md exists"

# 2-10: substantive content checks
assert_contains "[0.9.0]" "version header [0.9.0] present"
assert_contains "2026-05-05" "release date 2026-05-05 present"
assert_contains "gate_mode" "new frontmatter knob 'gate_mode' documented"
assert_contains "--force-permissive" "override flag '--force-permissive' documented"
assert_contains "permissive" "mode 'permissive' documented"
assert_contains "strict" "mode 'strict' documented"
assert_contains "followups.jsonl" "new artifact 'followups.jsonl' documented"
assert_contains ".gate-mode-warned" "per-spec migration sentinel '.gate-mode-warned' documented"
assert_contains "schema_version: 2" "schema version bump 'schema_version: 2' documented"
assert_contains ".force-permissive-log" "audit-log path '.force-permissive-log' documented"

echo "------------------------------"
echo "Passed: ${PASS}    Failed: ${FAIL}"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
