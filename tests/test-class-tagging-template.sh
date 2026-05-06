#!/usr/bin/env bash
##############################################################################
# tests/test-class-tagging-template.sh
#
# Validates personas/_templates/class-tagging.md — the canonical class-tagging
# instruction block that W3 splices into ~28 reviewer/plan/check personas.
#
# Asserts:
#   1. File exists at the expected path.
#   2. First line is the BEGIN sentinel.
#   3. Last line is the END sentinel.
#   4. All 7 class names appear in the body.
#   5. The sev:security parity keyword is present.
#   6. The precedence string "architectural > security" appears verbatim.
#
# Bash 3.2 compatible. macOS-friendly (uses BSD-compatible flags only).
##############################################################################
set -uo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$ENGINE_DIR/personas/_templates/class-tagging.md"

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

# 1. File exists
if [ -f "$TEMPLATE" ]; then
  note_pass "file exists at personas/_templates/class-tagging.md"
else
  note_fail "missing file: $TEMPLATE"
  echo ""
  echo "Results: $PASS passed, $FAIL failed"
  exit 1
fi

# 2. First line is BEGIN sentinel
FIRST_LINE="$(head -n 1 "$TEMPLATE")"
if [ "$FIRST_LINE" = "<!-- BEGIN class-tagging -->" ]; then
  note_pass "first line is BEGIN sentinel"
else
  note_fail "first line is not BEGIN sentinel (got: $FIRST_LINE)"
fi

# 3. Last line is END sentinel
LAST_LINE="$(tail -n 1 "$TEMPLATE")"
if [ "$LAST_LINE" = "<!-- END class-tagging -->" ]; then
  note_pass "last line is END sentinel"
else
  note_fail "last line is not END sentinel (got: $LAST_LINE)"
fi

# 4. All 7 class names appear at least once
CLASSES="architectural security contract documentation tests scope-cuts unclassified"
for class_name in $CLASSES; do
  count="$(grep -c "$class_name" "$TEMPLATE" || true)"
  if [ "${count:-0}" -ge 1 ]; then
    note_pass "class name present: $class_name (n=$count)"
  else
    note_fail "class name missing: $class_name"
  fi
done

# 5. sev:security parity keyword present
if grep -q "sev:security" "$TEMPLATE"; then
  note_pass "sev:security parity keyword present"
else
  note_fail "sev:security keyword not found"
fi

# 6. Precedence string verbatim, case-sensitive
if grep -q "architectural > security" "$TEMPLATE"; then
  note_pass "precedence string 'architectural > security' present"
else
  note_fail "precedence string 'architectural > security' missing"
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
