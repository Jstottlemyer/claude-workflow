# Scope Analysis — Round 3

**Reviewer:** scope (PRD Review)
**Spec:** `docs/specs/token-economics/spec.md` (revision 3, 2026-05-04)
**Round 3 trajectory check:** clean. All four round-2 important findings landed:

- Spike-failure path: Open Q3 explicitly routes the logging-shim path to a separate spec — not in-flight scope expansion. ✓
- Cross-project aggregation: `persona_content_hash` lives on every row; window reset is hash-based, not mtime. ✓
- BACKLOG #3 trigger: "≥10 validated runs accumulate" is mechanical, not vibes. ✓
- v1 stays static: Approach Phase 2 + A6 both lock "no week-over-week deltas" for v1. ✓

The v1+v3 split this persona pushed for in round 2 has held. v3 is instrumentation-only with a public-release-readiness layer bolted on; the layer added scope (privacy, project discovery, fixture redaction) but no new features. That's the right shape.

## Critical Gaps

(none — round 3 has no scope blockers)

## Important Considerations

### 1. Three render surfaces is one too many for v1

Spec ships a Persona Insights dashboard tab (Phase 2) **and** a `/wrap-insights` text sub-section (top/bottom 3 per gate × per dimension) **and** a `/wrap-insights ranking` bare-arg full-table view, all reading the same JSONL. For an instrumentation-only v1 whose first user is Justin (and one Pro-tier friend who won't see this until v1.1 anyway), two surfaces would suffice: the JSONL itself + one of {dashboard tab, wrap text}.

The dashboard tab is the durable, sortable, drill-down-capable surface. The `/wrap-insights` text section is the in-terminal at-a-glance surface. Both have a real job. The `/wrap-insights ranking` bare-arg full-table is the third surface and earns the least: it duplicates the dashboard tab in ASCII, in a context (terminal) where the dashboard tab is one click away.

**Recommendation:** drop the `/wrap-insights ranking` bare-arg full-table from v1 scope. Keep the per-gate top/bottom 3 sub-section. If terminal full-table demand materializes after release, add it then. Mention this as deferred in §Out of scope.

This is a v1-MVP integrity concern, not a blocker — the bare-arg variant is cheap to add and cheap to remove. Flag for `/plan` to weigh, not a hard cut.

### 2. A0 fixture redaction script is borderline meta-spec

`scripts/redact-persona-attribution-fixture.py` is listed under §Files created. It exists to make A0 testable on a public repo. That's defensible — privacy is in this spec's scope because public release is in this spec's audience constraint.

But the redaction script is a **tooling dependency for one acceptance criterion**, not a deliverable adopters use. Two scope risks:

- It can grow. ("While we're in there, redact the build-cost fixtures too." "Add a CI hook that re-runs redaction on every fixture commit.") The spec doesn't bound what it does — just "lives at scripts/redact-persona-attribution-fixture.py".
- It overlaps with anything BACKLOG #2 (install.sh rewrite) or a future "fixture-management" spec might want.

**Recommendation:** add one sentence to §Files created bounding the script: "single-purpose: reads a real session JSONL, writes a redacted excerpt with prompts/bodies/file-paths stripped; not a general-purpose redaction tool." This kills future scope-creep arguments. No restructure needed.

### 3. Project Discovery cascade is well-bounded but adopter-knob count is at the ceiling

The 3-tier cascade (explicit config file → auto-discovery via `~/Projects/*/docs/specs/` → CLI args with both `--project` and `--projects-root`) is the right design — it gives adopters two escape hatches without forcing config on the median user. But that's now **four configuration entry points** (config file, default scan path, two CLI flag families) for a v1 instrumentation feature.

Watch for:

- Adopter reports "auto-discovery missed my project at `~/work/foo/`" → pressure to add `~/work/`, `~/code/`, `~/dev/` to the default scan list. **Resist.** Tier 1 is the answer.
- Adopter wants per-project disable ("don't aggregate Luna's into my MonsterFlow rankings") → not in spec. Likely the day-after-launch ask given the Privacy section explicitly notes the script reads private-repo `findings.jsonl`.

**Recommendation:** add to §Out of scope: "Per-project exclusion / opt-out from aggregation — adopter removes the path from `~/.config/monsterflow/projects` or doesn't add it. v1 has no allow-list/deny-list mechanism beyond the cascade." This anticipates the day-after ask and gives a clean answer.

### 4. A11 outcome criterion needs a graceful degradation note

A11 says: "After first `/wrap-insights` run on a project with ≥10 historical gate runs, `persona-rankings.jsonl` contains ≥1 row per (persona, gate) pair seen in those runs."

For Justin: fine — MonsterFlow has years of pipeline runs.
For a fresh adopter who installs MonsterFlow today and runs `/wrap-insights` on day 1: they have **zero** historical gate runs. A11 is unsatisfiable not because the script is broken but because the precondition isn't met.

The current wording ("a project with ≥10 historical gate runs") technically scopes A11 only to projects that satisfy the precondition. But for an adopter following the spec to verify their install, A11 reads like "this should produce data" → they get an empty file → they file a bug.

**Recommendation:** add one line to A11: "On a fresh install with zero historical runs, the JSONL is created empty (or absent) and `/wrap-insights` prints `No persona data yet — run a /spec-review, /plan, or /check first.` Verified by `tests/test-fresh-install.sh` (or folded into the existing test-compute-persona-value.sh)." This makes day-1 install behavior an explicit outcome, not a footnote.

## Observations

- **Out of scope list is excellent.** "The logging-shim path if Phase 0 spike fails — that's a separate spec, not in-flight scope expansion here" is exactly the right framing and exactly what round 2 asked for. Scope-discipline persona is happy.
- **BACKLOG routing table.** The table at the top is the cleanest scope-fence I've seen in this repo. Item #3's "after this spec ships and ≥10 validated runs accumulate" trigger is mechanical and audit-able.
- **Phase 0 spike result inline.** Worth noting that v3 carries a *preliminary* spike result with two open questions (Q1, Q2) listed as "must resolve in /plan". This is technically scope-deferral into `/plan`, but it's the right call — the questions are bounded, A1.5 forces resolution, and gating the spec on the spike completing before `/plan` would slip the public release. Watch that `/plan` doesn't quietly punt them again.
- **Hybrid render layer (e9).** The "personas in roster files but not in JSONL render as (never run)" rule is good adopter-facing UX — a fresh install will see all 28 default personas as "(never run)" rather than an empty table. This subtly fixes part of A11's day-1 problem; if A11's wording gets the recommended tweak, the two work together.
- **Survival + uniqueness as separate columns, no composite.** The "consumers compose them however they need" stance is the right MVP move. Resists the inevitable "just give me one number" ask.
- **Cost-attribution pseudocode being conditional on Open Q1.** `/plan` will need a definite path before any code merges. Not a v3 spec problem; just flagging for the planner.

## Verdict

**PASS WITH NOTES** — Round 3 trajectory is clean. All four round-2 important items landed in v3. No critical scope gaps. Four important considerations (drop wrap-insights bare-arg full-table; bound the redaction script's scope in one sentence; add per-project opt-out to out-of-scope; gracefully degrade A11 for day-1 fresh-install) are tunings the planner can absorb in `/plan`, not blockers requiring a v4 spec revision. Ship to `/plan`.
