#!/usr/bin/env python3
"""tests/fixtures/permissiveness/partial-landing/v1-stub-validate.py

Minimal v1-stub validator. Mirrors the contract surface of
scripts/autorun/_policy_json.py::cmd_validate but ONLY knows the v1 schema
(schema-v1-stub.json sibling fixture). Used by test_partial_landing_rejection
to prove that a hypothetical PR which bumps the schema/verdict format to v2
WITHOUT also updating the validator would be caught by CI: this v1 stub MUST
reject the v2-shape verdict fixture.

Stdlib only, no shell-out, no eval/exec — minimal validator core extracted
from _policy_json.py (type/required/const/enum/additionalProperties only).

Usage: v1-stub-validate.py <verdict.json>
Exit: 0 ok | 1 invalid | 2 missing-file | 4 malformed-json
"""

import json
import sys
from pathlib import Path

# v1-only schema awareness — deliberately does NOT mention any v2 field name.
# This is the partial-PR-landing scenario: schema bumped on disk but validator
# wasn't updated in lockstep.
KNOWN_SCHEMAS = ("check-verdict",)


def _check_type(instance, expected):
    type_map = {
        "object": dict, "array": list, "string": str,
        "integer": int, "number": (int, float), "boolean": bool,
        "null": type(None),
    }
    if expected == "integer":
        return isinstance(instance, int) and not isinstance(instance, bool)
    if expected == "boolean":
        return isinstance(instance, bool)
    py = type_map.get(expected)
    return py is None or isinstance(instance, py)


def _validate(instance, schema, path, errors):
    if "type" in schema and not _check_type(instance, schema["type"]):
        errors.append("%s: type mismatch" % path)
        return
    if "const" in schema and instance != schema["const"]:
        errors.append("%s: const mismatch — expected %r, got %r" % (
            path, schema["const"], instance))
    if "enum" in schema and instance not in schema["enum"]:
        errors.append("%s: enum violation" % path)
    if isinstance(instance, dict):
        for r in schema.get("required", []):
            if r not in instance:
                errors.append("%s: missing required key %r" % (path, r))
        props = schema.get("properties", {})
        addl = schema.get("additionalProperties", True)
        for k, v in instance.items():
            if k in props:
                _validate(v, props[k], "%s.%s" % (path, k), errors)
            elif addl is False:
                errors.append("%s: additional property not allowed: %r" % (path, k))


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("usage: v1-stub-validate.py <verdict.json>\n")
        return 1
    fpath = argv[1]
    schema_path = Path(__file__).resolve().parent / "schema-v1-stub.json"
    try:
        with open(schema_path, "r", encoding="utf-8") as f:
            schema = json.load(f)
    except (OSError, IOError) as e:
        sys.stderr.write("cannot read v1 stub schema: %s\n" % e)
        return 2
    try:
        with open(fpath, "r", encoding="utf-8") as f:
            instance = json.load(f)
    except FileNotFoundError:
        sys.stderr.write("file not found: %s\n" % fpath)
        return 2
    except json.JSONDecodeError as e:
        sys.stderr.write("malformed json: %s\n" % e)
        return 4
    errors = []
    _validate(instance, schema, "$", errors)
    if errors:
        sys.stderr.write("(ok=False, errors=[\n")
        for e in errors:
            sys.stderr.write("  %s\n" % e)
        sys.stderr.write("])\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
