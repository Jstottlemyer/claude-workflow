#!/usr/bin/env bash
##############################################################################
# tests/test-skills.sh
#
# Validates every .claude/skills/<name>/SKILL.md has required frontmatter
# (name, description) plus a non-empty body. If `disable-model-invocation`
# is set, ensure it's `true` (typo guard).
##############################################################################
set -uo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS_DIR="$ENGINE_DIR/.claude/skills"

PASS=0
FAIL=0

if [ ! -d "$SKILLS_DIR" ]; then
  echo "✗ no .claude/skills/ dir at $SKILLS_DIR"
  exit 1
fi

shopt -s nullglob
skills=("$SKILLS_DIR"/*/SKILL.md)
shopt -u nullglob

if [ "${#skills[@]}" -eq 0 ]; then
  echo "✗ no SKILL.md files found in $SKILLS_DIR"
  exit 1
fi

for f in "${skills[@]}"; do
  name="$(basename "$(dirname "$f")")"

  if ! head -1 "$f" | grep -q '^---$'; then
    echo "✗ $name — missing frontmatter delimiter on line 1"
    FAIL=$(( FAIL + 1 ))
    continue
  fi

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

# If disable-model-invocation is set, value must be true/false (no typos)
dmi = re.search(r'^disable-model-invocation:\s*(\S+)', fm, re.MULTILINE)
dmi_ok = True
if dmi and dmi.group(1) not in ("true", "false"):
    dmi_ok = False

if not have_name:
    print("ERR: missing 'name:'")
elif not have_desc:
    print("ERR: missing 'description:'")
elif len(body) < 50:
    print("ERR: body too short")
elif not dmi_ok:
    print("ERR: disable-model-invocation must be true or false, got " + dmi.group(1))
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
echo "Skill tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
