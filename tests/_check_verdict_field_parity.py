#!/usr/bin/env python3
"""tests/_check_verdict_field_parity.py

Field-list parity audit for schemas/check-verdict.schema.json (v2). Asserts:

  1. The 15 expected v2 fields are all present in `required[]`.
  2. The same 15 fields are all present in `properties{}`.
  3. `additionalProperties` is exactly false.

Used by tests/test-autorun-policy.sh::test_v2_field_list_parity (AC A8 +
completeness MF1 + testability SF2). Stdlib only.

Exit: 0 = parity holds | 1 = parity violation (with diagnostic on stderr).
"""

import json
import sys
from pathlib import Path

# Source-of-truth list of v2 required fields (per pipeline-gate-permissiveness
# spec Integration line ~323 and W1.1 schema-bump task). 6 v1-original fields
# + 9 v2-additions.
EXPECTED_FIELDS = (
    # v1-original (still required in v2)
    "schema_version",
    "prompt_version",
    "verdict",
    "blocking_findings",
    "security_findings",
    "generated_at",
    # v2-additions (per-axis policy + classification surface)
    "iteration",
    "iteration_max",
    "mode",
    "mode_source",
    "class_breakdown",
    "class_inferred_count",
    "followups_file",
    "cap_reached",
    "stage",
)


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("usage: _check_verdict_field_parity.py <schema.json>\n")
        return 1
    schema_path = Path(argv[1])
    try:
        with open(schema_path, "r", encoding="utf-8") as f:
            schema = json.load(f)
    except (OSError, IOError) as e:
        sys.stderr.write("cannot read schema: %s\n" % e)
        return 1
    except json.JSONDecodeError as e:
        sys.stderr.write("malformed schema json: %s\n" % e)
        return 1

    failures = []

    required = schema.get("required") or []
    if not isinstance(required, list):
        failures.append("schema.required is not a list (got %r)" % type(required).__name__)
        required = []

    properties = schema.get("properties") or {}
    if not isinstance(properties, dict):
        failures.append("schema.properties is not an object (got %r)" % type(properties).__name__)
        properties = {}

    addl = schema.get("additionalProperties", "MISSING")
    if addl is not False:
        failures.append("schema.additionalProperties must be exactly false; got %r" % addl)

    required_set = set(required)
    properties_set = set(properties.keys())
    expected_set = set(EXPECTED_FIELDS)

    missing_from_required = sorted(expected_set - required_set)
    missing_from_properties = sorted(expected_set - properties_set)

    for f in missing_from_required:
        failures.append("required[] missing expected field: %r" % f)
    for f in missing_from_properties:
        failures.append("properties{} missing expected field: %r" % f)

    if failures:
        sys.stderr.write("check-verdict v2 field-list parity FAILED:\n")
        for msg in failures:
            sys.stderr.write("  - %s\n" % msg)
        sys.stderr.write(
            "  (Synthetic-rejection corollary: with a v2 field omitted from\n"
            "  required[] or properties{}, every conforming verdict would be\n"
            "  rejected by additionalProperties=false OR pass through unchecked.)\n"
        )
        return 1

    sys.stdout.write("check-verdict v2 field-list parity OK (15/15 fields)\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
