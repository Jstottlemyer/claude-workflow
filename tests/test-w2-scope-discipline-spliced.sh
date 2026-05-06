#!/usr/bin/env bash
##############################################################################
# tests/test-w2-scope-discipline-spliced.sh
#
# Validates W2.2: the class-tagging template is spliced into the
# scope-discipline reviewer persona (proof-point persona before W3 fan-out).
#
# Note on filename: the W2 plan refers to `personas/review/scope-discipline.md`
# but the on-disk file is `personas/review/scope.md` — the same persona
# (focus: scope discipline / scope-cuts). We assert against the on-disk path.
#
# Asserts:
#   1. Persona file contains `<!-- BEGIN class-tagging -->` sentinel.
#   2. Persona file contains `<!-- END class-tagging -->` sentinel.
#   3. Content between the sentinels in the persona is byte-identical to
#      content between the same sentinels in the canonical template
#      (modulo a single leading/trailing newline). Load-bearing assertion:
#      catches stale spliced content if the template later changes.
#
# Bash 3.2 compatible. macOS-friendly (uses BSD-compatible flags only).
##############################################################################
set -uo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$ENGINE_DIR/personas/_templates/class-tagging.md"
PERSONA="$ENGINE_DIR/personas/review/scope.md"

PASS=0
FAIL=0
FAILED=()

note_pass() {
  PASS=$(( PASS + 1 ))
  echo "  PASS — $1"
}

note_fail() {
  FAIL=$(( FAIL + 1 ))
  FAILED+=("$1")
  echo "  FAIL — $1"
}

# Pre-check: both files exist
if [ ! -f "$TEMPLATE" ]; then
  echo "  FAIL — template missing: $TEMPLATE"
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi
if [ ! -f "$PERSONA" ]; then
  echo "  FAIL — persona missing: $PERSONA"
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

# 1. BEGIN sentinel present
if grep -q "<!-- BEGIN class-tagging -->" "$PERSONA"; then
  note_pass "BEGIN sentinel present in scope.md"
else
  note_fail "BEGIN sentinel missing from scope.md"
fi

# 2. END sentinel present
if grep -q "<!-- END class-tagging -->" "$PERSONA"; then
  note_pass "END sentinel present in scope.md"
else
  note_fail "END sentinel missing from scope.md"
fi

# 3. Byte-identity of the inter-sentinel block (the load-bearing assertion).
#    Extract everything strictly BETWEEN the sentinel lines (exclusive),
#    from both files, and compare. This catches stale spliced content when
#    the canonical template changes but the persona is not re-spliced.
extract_between_sentinels() {
  # Prints lines strictly between the BEGIN and END sentinels.
  awk '
    /<!-- BEGIN class-tagging -->/ { in_block = 1; next }
    /<!-- END class-tagging -->/   { in_block = 0; next }
    in_block { print }
  ' "$1"
}

TEMPLATE_BLOCK="$(extract_between_sentinels "$TEMPLATE")"
PERSONA_BLOCK="$(extract_between_sentinels "$PERSONA")"

if [ "$TEMPLATE_BLOCK" = "$PERSONA_BLOCK" ]; then
  note_pass "inter-sentinel content is byte-identical to canonical template"
else
  note_fail "inter-sentinel content drifts from canonical template (re-splice required)"
  # Show a tiny diff hint for debugging
  echo "    --- template (first 3 lines)" >&2
  printf '%s\n' "$TEMPLATE_BLOCK" | head -n 3 | sed 's/^/    /' >&2
  echo "    --- persona  (first 3 lines)" >&2
  printf '%s\n' "$PERSONA_BLOCK"  | head -n 3 | sed 's/^/    /' >&2
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed:"
  for f in "${FAILED[@]}"; do
    echo "  - $f"
  done
  exit 1
fi
exit 0
