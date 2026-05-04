# Sequencing — Check Review

**Verdict:** PASS WITH NOTES — DAG is clean and acyclic, critical path correctly front-loads the spike + A1.5 forcing function, but two task dependency declarations are dishonest in opposite directions (one over-declared, one under-declared) and should be corrected before /build.

## Must Fix

None. No circular dependencies. No task starts before a hard prerequisite exists. Δ6 (don't modify `session-cost.py`) is handled correctly: the contract lives in spec v4.1 + plan decision #14, and the first import-site (task 1.3) notes the constraint inline, with no Wave 0 task touching `session-cost.py`. The chain that matters most — spike (0.1) → fixtures (0.5) → cost walk (1.3) → A1.5 forcing function (1.4) → bundle emit (1.8) — is correctly serialized so A1.5 fires *before* anything commits to a canonical token source.

## Should Fix

1. **Task 1.5 (value walk) under-declares its fixture dependency.** Plan lists 1.5 deps as "1.1, 1.2" — but 1.5 walks `findings.jsonl` / `survival.jsonl` / `run.json` / `raw/<persona>.md` per artifact directory and is genuinely undevelopable/untestable without the cross-project fixtures from 0.4. Compare with 1.3, which correctly declares 0.5 as a dep for the same reason. Add **0.4** to 1.5's "Depends On" column. Without this, a parallel agent could pick up 1.5 the moment Wave 0 task 0.1+0.2 close, before 0.4 ships, and discover mid-task that there's nothing to walk.

2. **Task 3.7 (`docs/persona-ranking.md`) over-declares its dependency on 3.1.** Plan lists 3.7 deps as "3.1, 3.6". 3.7 documents the Project Discovery cascade (implemented in 1.1), the pre-commit hook (3.6), and retention-vs-survival semantics. None of those documentation surfaces depend on test *results* — they depend on implementations *existing*. The honest dep is **1.1 + 1.6 + 3.6** (or just "all Wave 1 + 3.6"), not 3.1. As written, 3.7 idles waiting for the largest test task to pass when it could ship in parallel with 3.1–3.5.

## Observations

- **Wave 0 spike-vs-schema parallelism works as advertised.** 0.1 (spike) + 0.2 (schema) + 0.4 (cross-project fixtures) all start cold. 0.3 (redact helper) waits on 0.2 (it is schema-bound). 0.5 (persona-attribution fixtures) waits on 0.1 + 0.3 — correct, because 0.5 reuses the probe file 0.1 identifies and runs it through the 0.3 redactor. The "in parallel with schema design per wave-sequencer" framing is honored: schema design (0.2) and the spike (0.1) run side by side; 0.5's serialization is the natural fan-in, not a violation.

- **1.3 (cost walk) lists 1.1 (Discovery) as a dep, but the cost root is `~/.claude/projects/*/` — a fixed path, not a discovered MonsterFlow project root.** The dep is a soft over-declaration (Discovery's `validate_project_root` is reused for safety, plausibly), not blocking. Could parallelize 1.3 with 1.1 if pressed for wall-clock; not worth restructuring.

- **2.3 (renderer) sequential after 2.2 is conservative but defensible.** Plan decision #18 locks the function-name contract (`window.__renderPersonaInsightsView`) and the `data-mode="personas"` key, so 2.2 (HTML wiring) and 2.3 (JS renderer) could parallelize. The plan's serialization avoids a class of integration bugs (rename drift, mode-handler key drift) at the cost of a small parallelism opportunity. Reasonable tradeoff for a 2-subagent wave.

- **Wave 1 → Wave 2 hand-off is implicit but workable.** Wave 2 tasks 2.1 (wrap.md) and 2.3 (renderer JS) consume `persona-rankings.jsonl`. 2.1 correctly deps 1.8. 2.3 only deps 2.2, but Wave 0 task 0.4 already provides the fixture trees, and running 1.8 once produces the JSONL the renderer reads. No explicit "checked-in sample JSONL for renderer dev" task — adopters will rely on running the engine end-to-end against fixtures. Acceptable; not worth a new task.

- **Critical path estimate:** 0.1 → 0.5 → 1.3 → 1.4 → 1.8 → 2.1 → 3.3. Phase 0 spike is correctly front-loaded as the highest-risk early task. A1.5 (1.4) is the single point where the spike Open Q1 closes; if it fails, the engine has no canonical token source and `/plan` re-opens — risk is appropriately positioned to surface in Wave 1, not Wave 3.

- **No hidden circular dependencies.** Walked every "Depends On" forward and back; the DAG is acyclic.

- **Risk-front-loading: good.** Wave 0 spike close, Wave 1 A1.5 forcing function, Wave 1 path-validation test, Wave 1 allowlist test all run before any rendering surface. Privacy + correctness gates fire before any user-visible artifact, matching the "privacy ships *with* the engine, not deferred" decision (#5).
