**Verdict:** PASS WITH NOTES — The core task set is sound and traceable, but three plan additions warrant trimming or demotion, and one bundling risk in task 10 deserves attention.

**Must Fix:**

- **max_api_calls counter (Design Decision #6) is scope creep.** The spec explicitly removed the cost ceiling. Reintroducing it under a different name violates that decision. Either remove it entirely or require explicit user approval to re-open that spec decision before building it.

**Should Fix:**

- **queue/index.md (Design Decision #4) has no AC mapping.** The spec's notification AC is satisfied by mail + osascript + run-summary.md. A morning digest index is pure UX polish — demote to "if time permits" or cut.

- **autorun wrapper (task 11) is convenience, not a hard requirement.** AC #1 doesn't gate on it. The raw `flock -n queue/.autorun.lock bash scripts/autorun/run.sh` command is a complete, testable invocation. Demote task 11 to post-MVP or mark it explicitly optional.

- **Task 10 (run.sh) bundles too many distinct concerns.** Recommend splitting: 10a (orchestrator core: flock, queue loop, state.json, stage sequencing, call counter), 10b (PR + provenance block), 10c (Codex review + blocking-finding gate + merge). Sizes: 10a=M, 10b=S, 10c=S.

**Observations:**

- state.json, running.pid orphan detection, AUTORUN env var export, $TMPDIR, AUTORUN_GH_TOKEN (optional), --system flag test (in spike), run.log JSON lines, wave headers in build-log.md, failure.md schema, queue/.current-stage, autorun.config.json.example — all justified or low-cost. Keep them.
- AUTORUN_GH_TOKEN should be explicitly flagged as optional in the plan — the feature works with the default GH token.
- autorun.config.json.example should not smuggle max_api_calls back in after it's removed from the plan.
