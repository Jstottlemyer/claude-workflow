#!/bin/bash
# tests/test-plan-gate-mode.sh
#
# Asserts that commands/plan.md has a Phase 0c gate-mode block wired correctly
# per docs/specs/pipeline-gate-permissiveness/plan.md task W3.6.
#
# Bash 3.2 compatible. No bashisms beyond [ ... ] and grep -q.

set -u

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLAN_MD="$REPO_DIR/commands/plan.md"

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

printf "test-plan-gate-mode: commands/plan.md gate-mode wiring\n"

if [ ! -f "$PLAN_MD" ]; then
  printf "  FATAL %s does not exist\n" "$PLAN_MD"
  exit 1
fi

# 1. Phase 0c heading present
assert_grep "Phase 0c heading present"           "Phase 0c: Gate Mode Resolution" "$PLAN_MD"

# 2. Helper script sourced
assert_grep "_gate_helpers.sh referenced"        "_gate_helpers.sh"               "$PLAN_MD"

# 3. gate_mode_resolve invoked
assert_grep "gate_mode_resolve referenced"       "gate_mode_resolve"              "$PLAN_MD"

# 4. gate_max_recycles_clamp invoked
assert_grep "gate_max_recycles_clamp referenced" "gate_max_recycles_clamp"        "$PLAN_MD"

# 5. Truth-table reference
assert_grep "_gate-mode.md reference present"    "_gate-mode.md"                  "$PLAN_MD"

# 6. CLI flag mentioned (escape via single-quote pattern; no shell metas)
assert_grep "--force-permissive flag mentioned"  '--force-permissive'             "$PLAN_MD"

# 7. Sentinel path mentioned
assert_grep ".gate-mode-warned sentinel path"    ".gate-mode-warned"              "$PLAN_MD"

printf "test-plan-gate-mode: %d passed, %d failed\n" "$PASS" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
