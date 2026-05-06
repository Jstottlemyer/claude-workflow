#!/bin/bash
# Test: docs/index.html surfaces the three-tier verdict (GO / GO_WITH_FIXES / NO_GO)
# introduced by pipeline-gate-permissiveness v0.9.0.
#
# Race-safety: this test only reads docs/index.html. It does not write or mutate.

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HTML="$REPO_ROOT/docs/index.html"

PASS=0
FAIL=0
FAIL_MSGS=()

assert() {
  local label="$1"
  local cond="$2"
  if [ "$cond" = "0" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $label"
  else
    FAIL=$((FAIL + 1))
    FAIL_MSGS+=("$label")
    echo "  FAIL: $label"
  fi
}

echo "test-docs-index-three-tier-verdict.sh"
echo "  HTML: $HTML"

# 1. File exists.
if [ -f "$HTML" ]; then
  assert "docs/index.html exists" 0
else
  assert "docs/index.html exists" 1
  echo ""
  echo "Result: $PASS passed, $FAIL failed"
  exit 1
fi

# 2a. Contains literal GO_WITH_FIXES.
if grep -F -q "GO_WITH_FIXES" "$HTML"; then
  assert "contains 'GO_WITH_FIXES'" 0
else
  assert "contains 'GO_WITH_FIXES'" 1
fi

# 2b. Contains literal NO_GO.
if grep -F -q "NO_GO" "$HTML"; then
  assert "contains 'NO_GO'" 0
else
  assert "contains 'NO_GO'" 1
fi

# 2c. Contains a bare 'GO' as a verdict label (not just inside GO_WITH_FIXES / NO_GO).
# Strip GO_WITH_FIXES and NO_GO, then check a standalone GO remains.
stripped="$(sed -e 's/GO_WITH_FIXES//g' -e 's/NO_GO//g' "$HTML")"
if printf '%s' "$stripped" | grep -F -q "GO"; then
  assert "contains standalone 'GO' verdict label" 0
else
  assert "contains standalone 'GO' verdict label" 1
fi

# 3. Contains some form of three-tier annotation.
if grep -E -q "three-tier|three verdicts|v0\.9\.0" "$HTML"; then
  assert "contains three-tier annotation (three-tier|three verdicts|v0.9.0)" 0
else
  assert "contains three-tier annotation (three-tier|three verdicts|v0.9.0)" 1
fi

# 4. Contains at least one mermaid block.
if grep -F -q "mermaid" "$HTML"; then
  assert "contains a mermaid block" 0
else
  assert "contains a mermaid block" 1
fi

# 5. HTML structure preserved.
html_open="$(grep -c "<html" "$HTML")"
html_close="$(grep -c "</html>" "$HTML")"
if [ "$html_open" -ge 1 ]; then
  assert "<html opens at least once ($html_open)" 0
else
  assert "<html opens at least once ($html_open)" 1
fi
if [ "$html_close" -ge 1 ]; then
  assert "</html> closes at least once ($html_close)" 0
else
  assert "</html> closes at least once ($html_close)" 1
fi

echo ""
echo "Result: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  for msg in "${FAIL_MSGS[@]}"; do
    echo "  - $msg"
  done
  exit 1
fi
exit 0
