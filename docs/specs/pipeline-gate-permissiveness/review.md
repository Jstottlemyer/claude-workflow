# Spec Review v2 — pipeline-gate-permissiveness (refined)

**Spec:** `docs/specs/pipeline-gate-permissiveness/spec.md` (revised post-/spec-review v1)
**Reviewers:** ambiguity, feasibility, gaps, requirements, scope, stakeholders + codex-adversary
**Generated:** 2026-05-05 (round 2)
**Overall health:** **Concerns (2 architectural items introduced by v1 refinement; rest is tightening)**

---

## Summary vs v1

The v1 refinement closed all 8 architectural items the first review surfaced (verdict-as-JSON, followups-as-JSONL-with-lifecycle, fail-closed `unclassified` fallback, autorun lockstep, taxonomy tiebreakers, target-phase tag, migration UX, `--force-permissive` + `mode_source`). All 6 Claude reviewers returned PASS or PASS WITH NOTES; one returned outright PASS (scope).

**However** — Codex round 2 caught two genuine architectural correctness bugs introduced *by* the refinement itself:

1. **Cross-gate `followups.jsonl` regeneration corrupts open rows.** The file is shared across `/spec-review`, `/plan`, `/check`, but lifecycle step 4 marks any open row absent from "this iteration's" findings as `superseded`. A `/plan` iteration would incorrectly supersede still-valid `/spec-review` or `/check` followups.
2. **Strict runs leave stale `state: open` rows; `/build` contract doesn't reject them.** Strict mode preserves the audit trail (no regenerate), but `state: open` rows from a prior permissive run remain visible to `/build`'s `state: open AND target_phase IN (...)` filter. The "latest verdict was NO_GO" guard is implicit, not contracted.

Both are easy to fix; they're applied inline in this review.

---

## Before You Build (2 architectural items — fixed inline)

### A1. Scope `regenerate-active` to `source_gate == current_gate`. `[BLOCKER → FIXED INLINE]`
**Source:** codex-adversary #1

The lifecycle reconciliation in Data & State runs over the WHOLE `followups.jsonl`. With three gates writing to the same file, gate B's iteration can't know whether gate A's open rows are still valid. Fix: lifecycle step 4 marks `state: superseded` only for rows where `source_gate == current_gate` AND the `finding_id` is absent from the current iteration's post-Judge set. Rows from other gates are untouched.

**Inline fix:** edit Data & State §followups.jsonl §Lifecycle step 4 to scope by `source_gate`. Edit AC A14 to assert this.

### A2. `/build` must verify the latest verdict is `GO` or `GO_WITH_FIXES` before consuming `followups.jsonl`. `[BLOCKER → FIXED INLINE]`
**Source:** codex-adversary #2

Currently `/build` filters by `state: open AND target_phase IN (build-inline, docs-only)`. If the most recent `/check` was a strict-mode `NO_GO`, the followups from a prior permissive run are still `state: open` and would silently feed into `/build` if it ran. The contract must also check the most recent gate verdict.

**Inline fix:** edit Integration `commands/build.md` bullet to add the verdict check; edit AC A7 to require `latest_verdict ∈ {GO, GO_WITH_FIXES}`.

---

## Important But Non-Blocking (8 warn-route items — applied per spec's own framework)

Per the spec's 6-class framework, these are `contract` / `documentation` findings — apply inline if cheap, defer to `/plan` otherwise:

3. **Resurfaced `addressed` findings break the dedupe-key model** (codex #3) → `contract`. Schema needs an `occurrence_id` OR the addressed row transitions back to `open` with regression metadata. **Apply inline** — pick "transition addressed → open with `regression: true` field" (cheaper than introducing occurrence_id).

4. **Lock-file semantics underspecified** (codex #4, feasibility I-2): atomic acquisition, stale-lock handling, cleanup-on-interrupt, timeout, whether `render-followups.py` runs under the same lock — all unsaid. → `contract`. **Defer to /plan.**

5. **`--force-permissive` is too quiet for a strict-override** (codex #5, stakeholders IC-D): no stderr banner, no audit log entry. → `documentation` + `contract`. **Apply inline** — add a stderr banner and an audit-log row at `.force-permissive-log`.

6. **`class:security` ↔ `sev:security` schema field name not pinned** (codex #6, feasibility 4): the dual-emission is specified but the literal field name (`severity` enum vs `tags: ["sev:security"]` array) isn't. → `contract`. **Defer to /plan** — needs schema inspection.

7. **`render-followups.py` contract too thin** (codex #7, feasibility 5, stakeholders IC-E): sort keys, malformed-row handling, exit codes, lock interaction. → `contract`. **Defer to /plan** — proper CLI-contract block with input/output/exit-codes.

8. **`check-verdict` fence label across `/spec-review` + `/plan`** (codex #8, ambiguity I-C): consumers may infer "check" semantics from the label. The `stage` field helps but sidecar naming for non-check gates isn't pinned. → `documentation`. **Defer to /plan.**

9. **`additionalProperties: false` field-list parity** (feasibility 1): the prose enumeration omits `class_inferred_count`. With `additionalProperties: false`, one missing field name rejects every verdict. → `contract`. **Apply inline** — add `class_inferred_count` to the prose list.

10. **Migration banner is per-spec, not per-session** (stakeholders IC-B): N specs without `gate_mode:` → N banners across a workday. → `documentation`. **Defer to /plan** — design the per-user vs per-spec sentinel split.

---

## Observations (5 minor — surface in /plan)

11. `addressed_by` field has no specified writer (stakeholders IC-C). `/build`'s wave-final commit needs to write `state: addressed`, `addressed_by: <SHA>`. /plan should pin this.

12. Reworded-finding dedup-key drift (feasibility 3): reviewer rewords → `finding_id` hash changes → audit trail double-counts. Acceptable v1 risk; document in Edge Cases at /plan.

13. Recovery-time/SLO still implicit (requirements 1): renderer-failure path unspecified. Add to Edge Cases at /plan.

14. `iteration > iteration_max` semantics on a one-line caption (ambiguity I-A): worth a Data & State sentence. Apply at /plan.

15. v0.9.0 collision with reserved grep-fallback removal (stakeholders IC1, kept as O4): non-blocking; lean is "ride together."

---

## Reviewer Verdicts

| Dimension | Verdict | Key Finding |
|-----------|---------|-------------|
| requirements | PASS WITH NOTES | One schema-vs-AC contradiction on `followups_file: null`; 4 minor clarifications |
| gaps | PASS WITH NOTES | I5 admin-debug tooling still genuinely open; minor read-validator edge |
| ambiguity | PASS WITH NOTES | 7 clarifications worth applying inline at /plan; none cause divergent implementations |
| feasibility | PASS WITH NOTES | 5 sub-blocker items for /plan: field-list parity, lock primitive, dedup drift, security parity site, render contract |
| **scope** | **PASS** | Refinement growth (343→429 lines) is fully justified; no creep |
| stakeholders | PASS WITH NOTES | 5 stakeholder concerns (IC-A through IC-E); none blocking |
| **codex-adversary** | **(advisory; 2 high-risk)** | **Cross-gate regeneration scoping + strict-stale-rows-into-/build** — both architectural, fixed inline |

## Conflicts Resolved

- **Codex's 2 architectural findings** — no Claude reviewer caught them; codex's specific knowledge of cross-gate state-machine pitfalls dominated. Both fixes applied inline.
- **`addressed → open` regression vs `occurrence_id`** (codex #3): two valid resolutions. Picked transition-with-regression-flag because it preserves the dedupe-key invariant and is cheaper than introducing a new id field.

---

## What's Being Applied Inline (now)

1. Lifecycle scoping by `source_gate` (architectural fix #1)
2. `/build` latest-verdict check (architectural fix #2)
3. `addressed → open` regression transition (warn-route #3, cheap)
4. `--force-permissive` stderr banner + audit log (warn-route #5, cheap)
5. `class_inferred_count` added to prose field list (warn-route #9, cheap)

## What's Deferred to /plan

- Lock-file primitive choice + semantics (#4)
- `sev:security` schema field name (#6)
- `render-followups.py` CLI contract (#7)
- Sidecar naming across stages (#8)
- Per-user vs per-spec banner split (#10)
- All 5 observations (#11–#15)

---

**Recommendation:** apply the 5 inline fixes; advance to `/plan`. The 8 deferred items are implementation-detail-shaped and properly belong in the plan artifact.

Approve to proceed to `/plan`? (approve / refine `<what to change>`)
