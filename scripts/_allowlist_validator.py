#!/usr/bin/env python3
"""Stdlib JSON-Schema-subset validator for the persona-rankings + persona-
attribution allowlists (M2 from /check).

Public release week constraint: NO PyPI dependencies. We hand-roll just the
JSON Schema features used by our two allowlist schemas:

  - additionalProperties: false (THE privacy gate)
  - required[]
  - type (including ["number", "null"] union)
  - enum
  - pattern
  - const
  - minimum / maximum (numerics)
  - minItems / maxItems (arrays)
  - items (recurses)
  - nested object properties (recurses; additionalProperties: false carries down)
  - format: "date-time" (advisory only — actual rule is the pattern next to it)

Anything else in a schema is silently ignored — by design, this validator is
NOT a general-purpose jsonschema replacement. It is a privacy gate bound to
two specific allowlist files.

Spec: docs/specs/token-economics/spec.md (v4.2 §Privacy)
Plan: docs/specs/token-economics/plan.md (decisions #1, M2)
"""

import re


_TYPE_CHECKERS = {
    "string": lambda v: isinstance(v, str),
    "integer": lambda v: isinstance(v, int) and not isinstance(v, bool),
    "number": lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),
    "array": lambda v: isinstance(v, list),
    "object": lambda v: isinstance(v, dict),
    "boolean": lambda v: isinstance(v, bool),
    "null": lambda v: v is None,
}


def _check_type(value, type_decl):
    """type_decl may be a string or a list of strings (union)."""
    if isinstance(type_decl, list):
        return any(_TYPE_CHECKERS.get(t, lambda v: False)(value) for t in type_decl)
    checker = _TYPE_CHECKERS.get(type_decl)
    if checker is None:
        return True  # unknown type → don't block; not our job
    return checker(value)


def _validate_property(path, value, prop_schema, violations):
    """Recursively validate `value` against `prop_schema`, appending to
    `violations` (list of human-readable strings)."""
    # type
    if "type" in prop_schema:
        if not _check_type(value, prop_schema["type"]):
            violations.append(
                "{}: type mismatch (expected {!r}, got {!r})".format(
                    path, prop_schema["type"], type(value).__name__
                )
            )
            return  # downstream checks would mostly cascade

    # null short-circuit: if value is None and the schema permits null, skip
    # the rest (enum / pattern / etc. don't apply).
    if value is None:
        return

    # const
    if "const" in prop_schema:
        if value != prop_schema["const"]:
            violations.append(
                "{}: const mismatch (expected {!r}, got {!r})".format(
                    path, prop_schema["const"], value
                )
            )

    # enum
    if "enum" in prop_schema:
        if value not in prop_schema["enum"]:
            violations.append(
                "{}: enum violation (got {!r}, allowed {!r})".format(
                    path, value, prop_schema["enum"]
                )
            )

    # pattern (strings only)
    if "pattern" in prop_schema and isinstance(value, str):
        if not re.search(prop_schema["pattern"], value):
            violations.append(
                "{}: pattern mismatch (value {!r} does not match {!r})".format(
                    path, value, prop_schema["pattern"]
                )
            )

    # minimum / maximum (numerics)
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in prop_schema and value < prop_schema["minimum"]:
            violations.append(
                "{}: minimum violation ({} < {})".format(
                    path, value, prop_schema["minimum"]
                )
            )
        if "maximum" in prop_schema and value > prop_schema["maximum"]:
            violations.append(
                "{}: maximum violation ({} > {})".format(
                    path, value, prop_schema["maximum"]
                )
            )

    # arrays
    if isinstance(value, list):
        if "minItems" in prop_schema and len(value) < prop_schema["minItems"]:
            violations.append(
                "{}: minItems violation ({} < {})".format(
                    path, len(value), prop_schema["minItems"]
                )
            )
        if "maxItems" in prop_schema and len(value) > prop_schema["maxItems"]:
            violations.append(
                "{}: maxItems violation ({} > {})".format(
                    path, len(value), prop_schema["maxItems"]
                )
            )
        items_schema = prop_schema.get("items")
        if items_schema:
            for i, item in enumerate(value):
                _validate_property(
                    "{}[{}]".format(path, i), item, items_schema, violations
                )

    # nested objects → recurse via validate()
    if isinstance(value, dict) and prop_schema.get("type") == "object":
        nested = validate(value, prop_schema, _path_prefix=path)
        violations.extend(nested)


def validate(row, schema, _path_prefix=""):
    """Return list of violation strings (empty list = valid).

    Enforces additionalProperties: false at every object level (the privacy
    gate). Callers receive the full violation list, not just the first one,
    so a single test invocation surfaces every leak.
    """
    violations = []
    if not isinstance(row, dict):
        violations.append(
            "{}: expected object, got {!r}".format(
                _path_prefix or "<root>", type(row).__name__
            )
        )
        return violations

    properties = schema.get("properties", {})
    required = schema.get("required", [])
    additional_allowed = schema.get("additionalProperties", True)

    # additionalProperties: false → reject any key not in properties
    if additional_allowed is False:
        for key in row.keys():
            if key not in properties:
                p = "{}.{}".format(_path_prefix, key) if _path_prefix else key
                violations.append(
                    "{}: additionalProperties violation (field {!r} not in "
                    "allowlist)".format(p, key)
                )

    # required
    for req_key in required:
        if req_key not in row:
            p = "{}.{}".format(_path_prefix, req_key) if _path_prefix else req_key
            violations.append("{}: required field missing".format(p))

    # per-property checks
    for key, value in row.items():
        if key not in properties:
            continue  # already flagged above (or allowed if additional_allowed)
        prop_schema = properties[key]
        p = "{}.{}".format(_path_prefix, key) if _path_prefix else key
        _validate_property(p, value, prop_schema, violations)

    return violations
