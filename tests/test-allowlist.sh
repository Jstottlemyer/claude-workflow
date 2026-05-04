#!/usr/bin/env bash
##############################################################################
# tests/test-allowlist.sh — Wave 1 Task 1.9 (token-economics)
#
# Normal-fixture allowlist path. Asserts:
#   1. Every row in tests/fixtures/persona-attribution/*.jsonl (EXCLUDING
#      leakage-fail.jsonl) validates against
#      schemas/persona-attribution.allowlist.json — exit 0.
#   2. If dashboard/data/persona-rankings.jsonl exists, every row validates
#      against schemas/persona-rankings.allowlist.json.
#   3. Stderr canary check: invoking
#      `python3 scripts/compute-persona-value.py --dry-run </dev/null 2>&1`
#      MUST NOT contain the literal string `LEAKAGE_CANARY`.
#
# Uses scripts/_allowlist_validator.py (stdlib, no jsonschema dep).
#
# Spec: docs/specs/token-economics/spec.md (v4.2 §Privacy)
# Plan: docs/specs/token-economics/plan.md (v1.2 — Wave 1 task 1.9, M2)
##############################################################################
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=0

note_pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }
note_fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

# 1. Validate normal fixtures against persona-attribution.allowlist.json.
#    Exclude leakage-fail.jsonl (tested by test-allowlist-inverted.sh).
if python3 - <<'PY'
import json
import sys
from pathlib import Path

repo = Path.cwd()
sys.path.insert(0, str(repo / "scripts"))
import _allowlist_validator as V

schema_path = repo / "schemas" / "persona-attribution.allowlist.json"
with open(schema_path, "r", encoding="utf-8") as fh:
    schema = json.load(fh)

fixtures_dir = repo / "tests" / "fixtures" / "persona-attribution"
errors = 0
checked = 0
for jf in sorted(fixtures_dir.glob("*.jsonl")):
    if jf.name == "leakage-fail.jsonl":
        continue
    with open(jf, "r", encoding="utf-8") as fh:
        for ln, raw in enumerate(fh, 1):
            raw = raw.strip()
            if not raw:
                continue
            try:
                row = json.loads(raw)
            except json.JSONDecodeError as e:
                sys.stderr.write("{}:{}: json decode: {}\n".format(jf.name, ln, e))
                errors += 1
                continue
            checked += 1
            v = V.validate(row, schema)
            if v:
                sys.stderr.write(
                    "{}:{}: {}\n".format(jf.name, ln, "; ".join(v))
                )
                errors += v.__len__()

if checked == 0:
    sys.stderr.write("no fixture rows checked\n")
    sys.exit(2)

sys.exit(1 if errors else 0)
PY
then
  note_pass "persona-attribution fixtures (excluding leakage-fail.jsonl) validate"
else
  note_fail "persona-attribution fixtures (excluding leakage-fail.jsonl) validate"
fi

# 2. Conditional: persona-rankings.jsonl validation if file exists.
RANKINGS="$REPO_ROOT/dashboard/data/persona-rankings.jsonl"
if [ -f "$RANKINGS" ]; then
  if python3 - "$RANKINGS" <<'PY'
import json
import sys
from pathlib import Path

repo = Path.cwd()
sys.path.insert(0, str(repo / "scripts"))
import _allowlist_validator as V

rankings_path = Path(sys.argv[1])
schema_path = repo / "schemas" / "persona-rankings.allowlist.json"
with open(schema_path, "r", encoding="utf-8") as fh:
    schema = json.load(fh)

errors = 0
with open(rankings_path, "r", encoding="utf-8") as fh:
    for ln, raw in enumerate(fh, 1):
        raw = raw.strip()
        if not raw:
            continue
        try:
            row = json.loads(raw)
        except json.JSONDecodeError as e:
            sys.stderr.write("rankings:{}: json decode: {}\n".format(ln, e))
            errors += 1
            continue
        v = V.validate(row, schema)
        if v:
            sys.stderr.write("rankings:{}: {}\n".format(ln, "; ".join(v)))
            errors += len(v)

sys.exit(1 if errors else 0)
PY
  then
    note_pass "persona-rankings.jsonl rows validate"
  else
    note_fail "persona-rankings.jsonl rows validate"
  fi
else
  echo "SKIP: dashboard/data/persona-rankings.jsonl not present (conditional check)"
fi

# 3. Stderr canary — LEAKAGE_CANARY must NOT appear in compute-persona-value
#    --dry-run output. Capture combined stdout+stderr regardless of exit code
#    (the script may exit non-zero in this sandbox; only the canary string
#    matters here).
CANARY_OUT="$(python3 scripts/compute-persona-value.py --dry-run </dev/null 2>&1 || true)"
if printf '%s\n' "$CANARY_OUT" | grep -q 'LEAKAGE_CANARY'; then
  note_fail "stderr canary — LEAKAGE_CANARY found in --dry-run output"
else
  note_pass "stderr canary — LEAKAGE_CANARY absent from --dry-run output"
fi

echo ""
echo "test-allowlist: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
