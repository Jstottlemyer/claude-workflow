# Requirements Completeness — v3 Review (round 3)

**Reviewer:** requirements
**Spec:** `docs/specs/token-economics/spec.md` (revision 3, 2026-05-04)
**Verdict summary:** PASS — round 3 has substantially fewer concerns than round 2; all 4 prior testability gaps (A0, A1, A3, A8) verified closed; new privacy rows (A9, A10, A11) are machine-checkable as written.

## Critical Gaps

None. The four round-2 testability blockers are each closed with concrete verification:

- **A0 honor-system → closed.** Spec now names `tests/test-phase-0-artifact.sh` with three explicit assertions: (a) `## Phase 0 Spike Result` heading present, (b) section names a non-empty linkage field (`agentId`), (c) `tests/fixtures/persona-attribution/` exists with ≥1 valid `.jsonl`. All three are binary, scriptable, and runnable in CI.
- **A1 conditional / ±5% → closed.** A1 is now stated as **exact equality** (`sum(per_persona_tokens) == sum(usage rows from subagents/agent-*.jsonl)`); A1.5 is broken out as a separate row that closes Phase-0 Open Q1 by cross-checking parent annotation against the subagent transcript sum. Both are deterministic.
- **A3 manual → closed.** A3 references **programmatic synthetic fixtures** at `tests/fixtures/cross-project/` (two synthetic project trees) and explicitly names `tests/test-compute-persona-value.sh` invoking `compute-persona-value.py --project <fixture-A> --project <fixture-B>` with an assertion that output draws from both roots. Project Discovery cascade tested via fixture-config + fixture-CLI-args paths — covers tier (1) and tier (3) of the cascade explicitly.
- **A8 unbounded carve-out → closed.** §Idempotency contract enumerates a diff-stable allowlist (15 named fields, sort order specified, float rounding pinned at 6 decimals) and explicitly excludes `last_seen` as the **only** intentionally-volatile field, sourced from `run.json.created_at` (not file mtime). A8 references this section by name.

## Important Considerations

- **A11 outcome criterion is binary but underspecified at the boundary.** "≥10 historical gate runs, ≥1 row per (persona, gate) pair seen in those runs" is testable, but ambiguous when a persona was loaded for a gate but its raw artifact failed to write (e.g., agent crashed mid-dispatch). Suggest A11 also assert `len(rows) >= len(distinct (persona, gate) pairs observed in findings.jsonl)` rather than "in those runs" — findings.jsonl is the schema-grounded ground truth, "runs" is fuzzier.
- **A10 leakage canary is good but only covers one field.** The canary asserts `LEAKAGE_CANARY_DO_NOT_PERSIST_xyz123` does not appear in `persona-rankings.jsonl`. Consider also asserting it does not appear in `compute-persona-value.py` stderr/stdout (warning paths that echo finding titles would silently leak via `/wrap-insights` shell capture). One extra grep on captured stderr would close it.
- **A1.5 has a dependent branch the test must encode.** "If they agree, parent annotation is canonical; else subagent transcript is canonical" — A1.5 verifies the equality, but the spec doesn't state who flips the implementation switch when they disagree. Suggest adding "On disagreement, A1.5 fails the build and `/plan` re-opens Open Q1" so the test failure is the forcing function, not a silent behavioral fork.
- **e2 (persona prompt change) reset semantics under-tested by A4.** A4 covers the reset and the `insufficient_sample` flag, but not whether `contributing_finding_ids[]` is also cleared. A privacy-adjacent concern: if pre-edit findings remain in `contributing_finding_ids[]` after a reset, drill-down could surface findings the persona under the new prompt never produced. One-line addition to A4: "Assert `contributing_finding_ids` is empty after reset."

## Observations

- Acceptance criteria coverage is now genuinely complete for v1: A0 (spike), A1 + A1.5 (cost), A2 (value computed), A3 (cross-project), A4 (window reset), A5 (dashboard), A6 (wrap text), A7 (edges e1–e11), A8 (idempotency), A9–A10 (privacy), A11 (outcome). Each has a named test file or a binary assertion. A QA engineer reading only this spec could write a complete test plan.
- The two-survival-rate model (judge_survival vs downstream_survival) is now schema-grounded in both directions — denominators and numerators name specific JSONL files and fields. e10 + e11 explicitly handle the divide-by-zero cases (rate = null, cell renders as "—"). This was the largest semantic risk in v2 and it's clean now.
- Edge cases e1–e11 are exhaustive for the data shapes the spec describes; e9 (never-run hybrid render) and e10/e11 (null-rate cells) are new and tighten the dashboard contract well.
- `/wrap-insights` text format includes "(only N qualifying)" annotation — graceful degradation is specified, not left to the implementer. Good.
- Diff-stable field list in §Idempotency contract is explicit enough that A8's "byte-for-byte identical excluding `last_seen`" is unambiguous — the exact set of fields to compare is enumerated, not implied.
- Privacy section is a real specification, not a disclaimer: it names the redaction script (`scripts/redact-persona-attribution-fixture.py`), enumerates allowed/disallowed fixture content, and ties to A9 + A10 verification. Strong for a public release.

## Verdict: PASS

Round 3 has substantially fewer concerns than round 2 — the four flagged testability gaps are all closed with named test files and binary assertions, the new privacy criteria are verifiable as written, and acceptance coverage is complete. Three Important Considerations above are tightening suggestions, not blockers; the spec is ready for `/plan` and ready to ship publicly this week.
