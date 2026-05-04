# Ambiguity Review — Round 3 (token-economics v3)

**Reviewer:** ambiguity
**Round:** 3
**Spec:** `docs/specs/token-economics/spec.md` (revision 3, ready-for-plan)

## Round-2 ambiguity items — closure check

| R2 ambiguity | Status in v3 |
|---|---|
| Survival "body includes content from" undefined | **Closed.** v3 uses pure `personas[]` membership (`persona ∈ personas[]`); no body-substring matching anywhere. |
| "Merge target" undefined | **Closed.** Concept dropped entirely; the two survival rates do not appeal to a "merge target". |
| Within-run multi-dispatch counting | **Closed.** §Window + Counting unit both state explicitly: "Re-prompts within a single gate run share a tool_use_id and count as one." |
| Jaccard scope | **Closed.** Uniqueness now uses `findings.jsonl.unique_to_persona` directly; no jaccard, no thresholds, no scope to argue about. |

All four round-2 ambiguity blockers are genuinely resolved (not papered over). Round-3 ambiguity surface is **smaller** than round 2.

## Critical Gaps

None.

## Important Considerations

### I1 — "All bullets" in raw/<persona>.md is *almost* unambiguous, with one residual edge

§Approach Phase 1 defines emitted as "lines starting with `- ` or `* ` under `## Critical Gaps`, `## Important Considerations`, `## Observations` headings". Two implementer questions remain:

- **Nested / continuation lines:** a bullet that wraps across lines (continuation indented two spaces, or sub-bullets under a parent) — does the sub-bullet count as a separate emitted item, or as part of the parent? Personas regularly emit nested structure. Pick one (recommend: top-level bullets only — sub-bullets are elaboration of the parent finding).
- **The `## Verdict` section:** the persona template ends with `### Verdict PASS/FAIL — one sentence rationale`. v3 explicitly excludes it by listing only the three section headings, but does not say *why* (it would inflate the denominator with a non-finding). One sentence in §Survival semantics confirming "Verdict line is not a finding and is excluded" would prevent a future implementer from "fixing" the omission.

Neither blocks `/plan`, but both will surface in the test fixture for A7.

### I2 — Two survival denominators are distinguishable in prose, but the `0.404` example invites confusion

§Survival semantics names them clearly ("denominator = bullets emitted" vs "denominator = the persona's findings that survived Judge"). Good.

The schema example then shows `judge_survival_rate: 0.659` and `downstream_survival_rate: 0.404` side-by-side without a one-line annotation reminding the reader that the two rates have different denominators. An adopter eyeballing the dashboard will reasonably assume `downstream < judge` is "more was lost downstream" — but `downstream` could exceed `judge` mathematically (downstream is gated on judge-survivors, not on emitted bullets). Recommend adding a single inline comment in the JSONC block:

```jsonc
"judge_survival_rate": 0.659,           // total_judge_survived / total_emitted
"downstream_survival_rate": 0.404,      // total_downstream_survived / total_judge_survived (NOT / total_emitted)
```

The formulas are already there; just bold the difference in denominator.

### I3 — `outcome ∈ {addressed, kept}` is referenced but the schema citation is implicit

§Approach and §Survival semantics both reference `outcome ∈ {addressed, kept}` from `survival.jsonl`. The spec says (§Integration → "Existing systems leveraged") that it depends on the persona-metrics `survival.jsonl` schema, but never inlines the canonical outcome enum. If `survival-classifier` emits `accepted` instead of `addressed`, or adds a third valid value (`partially_addressed`?), the rate silently misclassifies.

Two acceptable fixes:
- (a) Inline the full outcome enum here ("`addressed | kept | dropped | superseded`" or whatever the source defines).
- (b) Cite the exact source file + heading: "per `docs/specs/persona-metrics/spec.md` §Survival outcomes, `outcome ∈ {addressed, kept}` are the survival-positive values".

Currently the spec asserts a closed set without anchoring it. Important because a new outcome value could ship in persona-metrics and silently break this rate without any test catching it (A2 only asserts the rate is in `[0.0, 1.0] ∪ {null}`, not that the enum membership check is current).

### I4 — null-rate composition with sorting is *named* but not fully specified for the mixed case

e10/e11 say rate cells render as "—". A5 says "insufficient-sample rate cells render as '—' (not dimmed numbers)". Good.

But: when a user clicks the column header to sort by `downstream_survival_rate` ascending, where do `null` rows land? Top? Bottom? Stable-sorted by persona name within the null group? Not specified. JS default behavior depends on the comparator and is famously inconsistent across browsers/libraries.

Pick one (recommend: nulls always sort to bottom regardless of asc/desc, so they never claim the "best" or "worst" slot). Add to A5 or as a one-line addition to e10/e11.

## Observations

### O1 — "Jolly survival" → "judge survival" naming is consistent

I checked for the kind of cross-section drift that bit round 2 (e.g., "post-Judge survival" in one place, "judge survival" in another). v3 uses `judge_survival_rate` and "judge survival" everywhere I looked. Good hygiene.

### O2 — "Diff-stable allowlist" terminology

§Idempotency contract calls out "Diff-stable fields" with an explicit list. The phrase "allowlist" appears in the section title in spec line 199 (`### Idempotency contract (A8 spec)`) and in A8's "Diff-stable allowlist documented in §Idempotency contract." The list is the allowlist. Two engineers will not implement this differently. Closed.

### O3 — "v1 stays static — no week-over-week deltas"

Appears in §Approach Phase 2 and A6. Unambiguous (deltas are out of scope for v1). Just flagging that I checked.

### O4 — "Hybrid layer" terminology in §Scope

§Scope says "hybrid layer; see UX". §UX defers to §Approach Phase 2 + §Data & State. The hybrid concept is fully specified by the time you finish §Approach Phase 2 (data-driven JSONL + render-time enrichment with current `personas/` files; e9 covers it). An implementer who reads top-to-bottom will not be confused. PASS.

### O5 — "Most recent contributing run" for `last_seen`

§Idempotency contract: `last_seen` is "sourced from `run.json.created_at` of most recent contributing run, NOT file mtime". Clear. The implementation question of *which* contributing run wins when two have the same timestamp is microscopic and not worth specifying.

## Verdict

**PASS WITH NOTES.** Round-2 ambiguity blockers (4 of them) are all genuinely closed by structural changes, not by hand-waving. Round-3 ambiguity surface is materially smaller — I1–I4 are all "important considerations," none rise to critical-gap. The two highest-leverage fixes are I3 (inline or cite the `outcome` enum) and I4 (specify null sort position), both one-liners that should land in `/plan` not block it.
