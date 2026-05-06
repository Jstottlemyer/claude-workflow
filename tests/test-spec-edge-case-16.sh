#!/usr/bin/env bash
##############################################################################
# tests/test-spec-edge-case-16.sh
#
# Asserts pipeline-gate-permissiveness/spec.md contains Edge Case 16 with all
# five subcase markers (16a–16e). Guards against accidental section deletion
# during late-cycle spec edits.
##############################################################################
set -uo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SPEC="$ENGINE_DIR/docs/specs/pipeline-gate-permissiveness/spec.md"

PASS=0
FAIL=0

if [ ! -f "$SPEC" ]; then
  echo "✗ spec not found at $SPEC"
  exit 1
fi

check() {
  local pattern="$1"
  local label="$2"
  if grep -qE "$pattern" "$SPEC"; then
    echo "✓ $label"
    PASS=$(( PASS + 1 ))
  else
    echo "✗ $label — pattern not found: $pattern"
    FAIL=$(( FAIL + 1 ))
  fi
}

check '^16\. \*\*Late-cycle clarifications' "Edge Case 16 header present"
check '16a\. \*\*Reworded-finding dedup-key drift' "16a — reworded-finding dedup"
check '16b\. \*\*Renderer-failure recovery path' "16b — renderer-failure recovery"
check '16c\. \*\*`iteration > iteration_max` semantics' "16c — iteration cap semantics"
check '16d\. \*\*Per-spec banner once-per-session-per-spec' "16d — banner sentinel semantics"
check '16e\. \*\*Codex review at `/check` is mandatory' "16e — Codex review mandatory"

echo ""
echo "Edge Case 16 tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
