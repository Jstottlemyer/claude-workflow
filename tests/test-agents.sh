#!/usr/bin/env bash
##############################################################################
# tests/test-agents.sh
#
# Validates that every .claude/agents/*.md file has the required frontmatter
# (name, description) and a non-empty body.
##############################################################################
set -uo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AGENTS_DIR="$ENGINE_DIR/.claude/agents"

PASS=0
FAIL=0

if [ ! -d "$AGENTS_DIR" ]; then
  echo "✗ no .claude/agents/ dir at $AGENTS_DIR"
  exit 1
fi

shopt -s nullglob
agents=("$AGENTS_DIR"/*.md)
shopt -u nullglob

if [ "${#agents[@]}" -eq 0 ]; then
  echo "✗ no agent files found in $AGENTS_DIR"
  exit 1
fi

for f in "${agents[@]}"; do
  name="$(basename "$f" .md)"

  # Must start with --- frontmatter
  if ! head -1 "$f" | grep -q '^---$'; then
    echo "✗ $name — missing frontmatter delimiter on line 1"
    FAIL=$(( FAIL + 1 ))
    continue
  fi

  # Extract frontmatter via python (between first two --- lines)
  result="$(python3 - "$f" <<'PY'
import sys, re
path = sys.argv[1]
text = open(path).read()
m = re.match(r'^---\n(.*?)\n---', text, re.DOTALL)
if not m:
    print("ERR: no closing --- delimiter")
    sys.exit(0)
fm = m.group(1)
have_name = bool(re.search(r'^name:\s*\S', fm, re.MULTILINE))
have_desc = bool(re.search(r'^description:\s*\S', fm, re.MULTILINE))
body = text[m.end():].strip()
if not have_name:
    print("ERR: missing 'name:' in frontmatter")
elif not have_desc:
    print("ERR: missing 'description:' in frontmatter")
elif len(body) < 50:
    print("ERR: body too short (<50 chars)")
else:
    print("OK")
PY
)"

  if [ "$result" = "OK" ]; then
    echo "✓ $name"
    PASS=$(( PASS + 1 ))
  else
    echo "✗ $name — $result"
    FAIL=$(( FAIL + 1 ))
  fi
done

echo ""
echo "Agent tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
