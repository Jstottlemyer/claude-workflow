#!/bin/bash
# tests/test-check-gate-mode.sh
#
# Asserts that commands/check.md has a Phase 0c gate-mode block + cap_reached
# next-steps wiring per docs/specs/pipeline-gate-permissiveness/plan.md task
# W3.7.
#
# Bash 3.2 compatible. No bashisms beyond [ ... ] and grep -q.

set -u

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_MD="$REPO_DIR/commands/check.md"

PASS=0
FAIL=0

assert_grep() {
  desc="$1"
  pattern="$2"
  file="$3"
  if grep -q -- "$pattern" "$file"; then
    printf "  ok  %s\n" "$desc"
    PASS=$((PASS + 1))
  else
    printf "  FAIL %s (pattern: %s)\n" "$desc" "$pattern"
    FAIL=$((FAIL + 1))
  fi
}

printf "test-check-gate-mode: commands/check.md gate-mode wiring\n"

if [ ! -f "$CHECK_MD" ]; then
  printf "  FATAL %s does not exist\n" "$CHECK_MD"
  exit 1
fi

# 1. Phase 0c heading present
assert_grep "Phase 0c heading present"           "Phase 0c: Gate Mode Resolution" "$CHECK_MD"

# 2. Helper script sourced
assert_grep "_gate_helpers.sh referenced"        "_gate_helpers.sh"               "$CHECK_MD"

# 3. gate_mode_resolve invoked
assert_grep "gate_mode_resolve referenced"       "gate_mode_resolve"              "$CHECK_MD"

# 4. gate_max_recycles_clamp invoked
assert_grep "gate_max_recycles_clamp referenced" "gate_max_recycles_clamp"        "$CHECK_MD"

# 5. Truth-table reference
assert_grep "_gate-mode.md reference present"    "_gate-mode.md"                  "$CHECK_MD"

# 6. cap_reached next-steps block referenced (check-specific addition)
assert_grep "cap_reached next-steps referenced"  "cap_reached"                    "$CHECK_MD"

# 7. CLI flag mentioned (escape via single-quote pattern; no shell metas)
assert_grep "--force-permissive flag mentioned"  '--force-permissive'             "$CHECK_MD"

# 8. Sentinel path mentioned
assert_grep ".gate-mode-warned sentinel path"    ".gate-mode-warned"              "$CHECK_MD"

printf "test-check-gate-mode: %d passed, %d failed\n" "$PASS" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
