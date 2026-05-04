#!/usr/bin/env bash
##############################################################################
# tests/test-allowlist-inverted.sh — Wave 1 Task 1.9-inv (token-economics, M8)
#
# INVERTED CONTRACT: this script EXITS NON-ZERO when the leakage IS detected
# (i.e. the test passes — the privacy gate caught the leak).
#
# tests/run-tests.sh invokes this via the shape:
#   if ! ./tests/test-allowlist-inverted.sh; then echo "PASS"; fi
#
# So a NON-ZERO exit here means "the leakage canary fixture was correctly
# rejected by the allowlist validator and we therefore consider the privacy
# gate working." A ZERO exit means the validator silently accepted the
# leakage row — the WORST possible regression for the privacy contract.
#
# Asserts BOTH of the following (any failure = ZERO exit, which is the
# inverted-FAIL condition for the orchestrator):
#   1. Validating tests/fixtures/persona-attribution/leakage-fail.jsonl
#      against schemas/persona-attribution.allowlist.json produces ≥1
#      violation.
#   2. The violation message contains the literal string `additionalProperties`
#      AND the offending field name `finding_title`.
#
# Uses scripts/_allowlist_validator.py (stdlib, no jsonschema dep).
#
# Spec: docs/specs/token-economics/spec.md (v4.2 §Privacy)
# Plan: docs/specs/token-economics/plan.md (v1.2 — decision #26 M8 separation)
##############################################################################
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

FIXTURE="tests/fixtures/persona-attribution/leakage-fail.jsonl"
SCHEMA="schemas/persona-attribution.allowlist.json"

if [ ! -f "$FIXTURE" ]; then
  echo "SETUP-FAIL: leakage fixture not found at $FIXTURE" >&2
  # SETUP failure -> exit ZERO so the orchestrator's `! invocation` flips to
  # FAIL (we cannot confirm the privacy gate without the fixture).
  exit 0
fi
if [ ! -f "$SCHEMA" ]; then
  echo "SETUP-FAIL: schema not found at $SCHEMA" >&2
  exit 0
fi

# Python helper: prints the violation list to stderr and exits NON-ZERO iff
# the leakage IS detected with the expected substrings present. Exits ZERO
# (silent acceptance) when the validator failed to catch the leak — which is
# what we are guarding against.
#
# We disable `set -e` around the capture so a non-zero helper exit (which is
# the GOOD outcome here) doesn't blow out the script before we read $?.
set +e
HELPER_OUT="$(python3 - "$FIXTURE" "$SCHEMA" <<'PY' 2>&1
import json
import sys
from pathlib import Path

repo = Path.cwd()
sys.path.insert(0, str(repo / "scripts"))
import _allowlist_validator as V

fixture_path = Path(sys.argv[1])
schema_path = Path(sys.argv[2])

with open(schema_path, "r", encoding="utf-8") as fh:
    schema = json.load(fh)

violations_all = []
rows = 0
with open(fixture_path, "r", encoding="utf-8") as fh:
    for raw in fh:
        raw = raw.strip()
        if not raw:
            continue
        try:
            row = json.loads(raw)
        except json.JSONDecodeError as e:
            sys.stderr.write("json decode: {}\n".format(e))
            continue
        rows += 1
        violations_all.extend(V.validate(row, schema))

if rows == 0:
    sys.stderr.write("INVERTED-FAIL: leakage fixture had no rows\n")
    sys.exit(0)

if not violations_all:
    sys.stderr.write(
        "INVERTED-FAIL: leakage fixture validated cleanly (no violations)\n"
    )
    sys.exit(0)

joined = "\n".join(violations_all)
sys.stderr.write(joined + "\n")

has_keyword = "additionalProperties" in joined
has_field = "finding_title" in joined
if not (has_keyword and has_field):
    sys.stderr.write(
        "INVERTED-FAIL: violation message missing required substrings "
        "(additionalProperties={}, finding_title={})\n".format(
            has_keyword, has_field
        )
    )
    sys.exit(0)

# Both conditions met — the privacy gate caught the leak. Exit NON-ZERO so
# the inverted orchestrator pattern (`! ./test-allowlist-inverted.sh`) flips
# this into a PASS.
sys.exit(2)
PY
)"
HELPER_RC=$?
set -e

# Echo the helper's stderr/stdout so callers see what happened.
printf '%s\n' "$HELPER_OUT"

if [ "$HELPER_RC" -ne 0 ]; then
  # Privacy gate worked — leakage caught. INVERTED PASS.
  echo "INVERTED-PASS: leakage row rejected with required substrings; exiting non-zero by design"
  exit "$HELPER_RC"
fi

# Helper exited zero -> the validator failed to catch the leak.
echo "INVERTED-FAIL: validator did NOT reject the leakage row" >&2
exit 0
