#!/usr/bin/env python3
"""render-followups.py — deterministic followups.jsonl -> followups.md renderer.

Spec: docs/specs/pipeline-gate-permissiveness/spec.md
  -- "followups.md (rendered, not authoritative)" section (line ~306)
  -- A22 (provenance header), A23 (regression marker)
Plan: docs/specs/pipeline-gate-permissiveness/plan.md (Wave 1, Task 1.6)
  -- Cross-cutting: render-followups.py runs OUTSIDE the lock for the WRITE;
     lock is acquired ONLY for the JSONL READ to coexist safely with a
     concurrent Synthesis writer. See plan §Cross-cutting Decisions Pinned.

Why this exists
---------------
`followups.jsonl` is the authoritative store for warn-routed gate findings.
`/build` wave 1 reads the JSONL directly. Humans read `followups.md`, which
this script renders deterministically: same input bytes -> byte-identical
output bytes. No timestamps from the wall clock; we use the latest
`updated_at` from the rows themselves.

CLI
---
    render-followups.py <spec-dir> [--no-lock]

Exit codes
----------
- 0: success (incl. zero open rows -> writes "no active follow-ups" body)
- 2: malformed JSONL row (or unparseable JSON)
- 3: lock contention (cannot acquire .followups.jsonl.lock within timeout)
- 4: <spec-dir> does not exist OR has no followups.jsonl

Hard constraints
----------------
- Python 3.9+ stdlib only (json, pathlib, argparse, os, tempfile, sys).
- AST-banlist clean: no eval/exec/compile/__import__/subprocess/etc.
- Reads `_followups_lock.followups_lock` from the sibling `scripts/` dir.
"""
from __future__ import annotations

# Exit code constants (also documented in --help epilog).
EXIT_OK = 0
EXIT_MALFORMED = 2
EXIT_LOCK_CONTENTION = 3
EXIT_NO_FOLLOWUPS = 4

import argparse
import json
import os
import sys
import tempfile
from pathlib import Path

# Make `from _followups_lock import followups_lock` resolve when run as a
# script from anywhere (e.g. `python3 scripts/render-followups.py ...` from
# the repo root, or via an absolute path). We insert the directory containing
# THIS file at the front of sys.path so the sibling helper is importable.
_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

from _followups_lock import followups_lock, FollowupsLockTimeout  # noqa: E402


# Section ordering matches /build wave-1 consumption order
# (per spec line 302: build-inline + docs-only consumed in wave 1;
# plan-revision triggers /plan re-run; post-build becomes PR annotations).
SECTION_ORDER = ("build-inline", "docs-only", "plan-revision", "post-build")

SECTION_DESCRIPTIONS = {
    "build-inline": "wave-1 build tasks",
    "docs-only": "wave-1 doc updates",
    "plan-revision": "trigger /plan re-run",
    "post-build": "PR-body annotations",
}

# Class ordering within a section — alphabetical-by-design so the order is
# predictable and language-stable (no locale dependency).
# Followups can only carry contract / documentation / tests / scope-cuts.
CLASS_ORDER = ("contract", "documentation", "tests", "scope-cuts")


def _parse_args(argv):
    parser = argparse.ArgumentParser(
        prog="render-followups.py",
        description=(
            "Deterministic followups.jsonl -> followups.md renderer. "
            "Reads <spec-dir>/followups.jsonl, writes <spec-dir>/followups.md."
        ),
        epilog=(
            "Exit codes:\n"
            "  0  success (including empty input)\n"
            "  2  malformed JSONL row or JSON parse error\n"
            "  3  lock contention (could not acquire within timeout)\n"
            "  4  spec-dir does not exist or has no followups.jsonl\n"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "spec_dir",
        help="path to docs/specs/<feature>/ (the dir containing followups.jsonl)",
    )
    parser.add_argument(
        "--no-lock",
        action="store_true",
        help=(
            "skip lock acquisition (read-only snapshot for human use; "
            "NOT safe under concurrent Synthesis writers)"
        ),
    )
    return parser.parse_args(argv)


def _read_jsonl(jsonl_path):
    """Parse followups.jsonl into a list of dicts.

    Empty lines are tolerated (skipped). Any non-empty line that fails
    `json.loads` raises a `_RowParseError` with the line number.
    """
    rows = []
    with open(jsonl_path, "r", encoding="utf-8") as fp:
        for lineno, raw in enumerate(fp, start=1):
            stripped = raw.strip()
            if not stripped:
                continue
            try:
                obj = json.loads(stripped)
            except json.JSONDecodeError as e:
                raise _RowParseError(lineno, str(e))
            if not isinstance(obj, dict):
                raise _RowParseError(lineno, "row is not a JSON object")
            rows.append(obj)
    return rows


class _RowParseError(Exception):
    def __init__(self, lineno, msg):
        super().__init__("line %d: %s" % (lineno, msg))
        self.lineno = lineno


def _safe(row, key, default=""):
    """Best-effort field accessor — renderer MUST NOT crash on a row that
    is missing optional/audit-only fields. Schema validation is enforced
    at WRITE time by _policy_json.py; the renderer is read-only and
    permissive so a partially-malformed JSONL still produces a usable MD."""
    v = row.get(key, default)
    return default if v is None else v


def _sort_key(row):
    """Within-section sort: (class, created_at, finding_id).

    `class` is mapped to its index in CLASS_ORDER for stable ordering;
    unknown classes sort last (preserving determinism without crashing).
    """
    cls = _safe(row, "class", "")
    try:
        cls_idx = CLASS_ORDER.index(cls)
    except ValueError:
        cls_idx = len(CLASS_ORDER)  # unknown classes sort after known ones
    return (cls_idx, _safe(row, "created_at", ""), _safe(row, "finding_id", ""))


def _section_key(target_phase):
    """Section sort key: index in SECTION_ORDER; unknown phases sort last."""
    try:
        return SECTION_ORDER.index(target_phase)
    except ValueError:
        return len(SECTION_ORDER)


def _render(rows, feature_name):
    """Build the full followups.md content from the parsed JSONL rows.

    `rows` is the FULL row set (all states); we filter to `state: open`
    for body rendering, but the header counts use the full set.
    """
    open_rows = [r for r in rows if _safe(r, "state") == "open"]
    addressed_count = sum(1 for r in rows if _safe(r, "state") == "addressed")
    superseded_count = sum(1 for r in rows if _safe(r, "state") == "superseded")
    open_count = len(open_rows)

    lines = []
    lines.append(
        "<!-- generated from followups.jsonl by scripts/render-followups.py;"
        " do not edit by hand -->"
    )
    lines.append("# Follow-ups — %s" % feature_name)
    lines.append("")
    lines.append("**Source:** [followups.jsonl](followups.jsonl)")
    lines.append(
        "**Open:** %d · **Addressed:** %d · **Superseded:** %d (hidden)"
        % (open_count, addressed_count, superseded_count)
    )
    lines.append("")
    lines.append(
        "> Why this file exists: contract/docs/tests findings the gate routed"
        " here instead of blocking."
    )
    lines.append(
        "> /build wave 1 reads followups.jsonl (the authoritative copy) and"
        " works build-inline + docs-only rows."
    )
    lines.append(
        "> Edit the spec or fix the code; re-run the gate to clear rows."
        " Rows close automatically when /build's wave-final commit references"
        " the finding_id."
    )
    lines.append("")
    lines.append("---")
    lines.append("")

    if open_count == 0:
        lines.append("_No active follow-ups._")
        lines.append("")
        return "\n".join(lines)

    # Group open rows by target_phase, ordered per SECTION_ORDER.
    by_phase = {}
    for r in open_rows:
        by_phase.setdefault(_safe(r, "target_phase", ""), []).append(r)

    phase_keys = sorted(by_phase.keys(), key=_section_key)

    for phase in phase_keys:
        section_rows = sorted(by_phase[phase], key=_sort_key)
        desc = SECTION_DESCRIPTIONS.get(phase, "")
        if desc:
            lines.append("## %s (%d) — %s" % (phase, len(section_rows), desc))
        else:
            lines.append("## %s (%d)" % (phase, len(section_rows)))
        lines.append("")

        # Within each section, group by class (preserving CLASS_ORDER).
        by_class = {}
        for r in section_rows:
            by_class.setdefault(_safe(r, "class", ""), []).append(r)

        # Render in CLASS_ORDER, then any unknown classes alphabetically.
        known_classes = [c for c in CLASS_ORDER if c in by_class]
        unknown_classes = sorted(c for c in by_class.keys() if c not in CLASS_ORDER)

        for cls in known_classes + unknown_classes:
            cls_rows = by_class[cls]
            cls_label = cls if cls else "(unclassified)"
            lines.append("### %s (%d)" % (cls_label, len(cls_rows)))
            lines.append("")
            for r in cls_rows:
                lines.append(_render_row(r))
            lines.append("")

    # Trim trailing blank line and add a single final newline.
    while lines and lines[-1] == "":
        lines.pop()
    lines.append("")
    return "\n".join(lines)


def _render_row(row):
    """Render a single open row as a bullet item.

    Format:
      - **<finding_id>** — <title> · *from /<source_gate> iter <N>*
        <suggested_fix>

    For regression rows, append the regressed marker on the header line.
    """
    finding_id = _safe(row, "finding_id", "(no finding_id)")
    title = _safe(row, "title", "")
    source_gate = _safe(row, "source_gate", "")
    source_iteration = _safe(row, "source_iteration", "")
    suggested_fix = _safe(row, "suggested_fix", "")

    head = "- **%s** — %s · *from /%s iter %s*" % (
        finding_id, title, source_gate, source_iteration,
    )

    if _safe(row, "regression", False) is True:
        prev = _safe(row, "previously_addressed_by", "")
        # SHA may be 7-40 hex; PR refs come through unchanged. Truncate
        # 40-char SHAs to 7 for human readability; leave shorter values
        # (already-truncated SHAs, PR refs) untouched.
        if isinstance(prev, str) and len(prev) > 7 and not prev.startswith("PR#"):
            prev_short = prev[:7]
        else:
            prev_short = prev
        head = head + " ⚠ regressed (was addressed in %s)" % prev_short

    body = "  %s" % suggested_fix
    return "%s\n%s" % (head, body)


def _atomic_write(target_path, content):
    """Write content to target_path atomically via tempfile + os.replace.

    Tempfile is created in the same directory as the target so the
    final rename is on the same filesystem (atomic).
    """
    target_path = Path(target_path)
    target_path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(
        prefix=".followups.md.",
        suffix=".tmp",
        dir=str(target_path.parent),
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fp:
            fp.write(content)
            fp.flush()
            os.fsync(fp.fileno())
        os.replace(tmp, str(target_path))
    except Exception:
        # Clean up the tempfile on any failure; replace() succeeded means
        # the temp is already gone, so this only fires on partial writes.
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def _feature_name(spec_dir):
    """Return the feature slug. v1: just the basename of spec-dir.

    Frontmatter parsing is intentionally NOT implemented here — the spec's
    feature-slug convention (`docs/specs/<slug>/`) makes the dir name the
    canonical identifier. If a future spec wants a display name, we can
    add a frontmatter pass without changing the renderer's contract.
    """
    return Path(spec_dir).resolve().name


def main(argv=None):
    args = _parse_args(argv)

    spec_dir = Path(args.spec_dir).expanduser()
    if not spec_dir.exists() or not spec_dir.is_dir():
        sys.stderr.write("no followups.jsonl at %s\n" % spec_dir)
        return EXIT_NO_FOLLOWUPS

    jsonl_path = spec_dir / "followups.jsonl"
    if not jsonl_path.exists():
        sys.stderr.write("no followups.jsonl at %s\n" % jsonl_path)
        return EXIT_NO_FOLLOWUPS

    md_path = spec_dir / "followups.md"
    lock_path = spec_dir / ".followups.jsonl.lock"

    # Read the JSONL (under lock unless --no-lock). The renderer's WRITE
    # of followups.md happens AFTER lock release per plan cross-cutting
    # decision: render-followups.py runs OUTSIDE the lock for the write
    # because the post-rename atomic JSONL is stable, and followups.md is
    # the renderer's sole authority (not contended with Synthesis).
    try:
        if args.no_lock:
            rows = _read_jsonl(jsonl_path)
        else:
            try:
                with followups_lock(lock_path):
                    rows = _read_jsonl(jsonl_path)
            except FollowupsLockTimeout as e:
                sys.stderr.write("FollowupsLockTimeout: %s\n" % e)
                return EXIT_LOCK_CONTENTION
    except _RowParseError as e:
        sys.stderr.write("malformed followups.jsonl: %s\n" % e)
        return EXIT_MALFORMED

    feature_name = _feature_name(spec_dir)
    content = _render(rows, feature_name)
    _atomic_write(md_path, content)
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
