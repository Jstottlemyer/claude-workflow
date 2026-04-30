# Checkpoint: Autonomous Overnight Pipeline (`/autorun`)

**Date:** 2026-04-29
**Plan:** docs/specs/autonomous-overnight-pipeline/plan.md
**Reviewers:** completeness, sequencing, risk, scope-discipline, testability

---

## Overall Verdict: GO WITH FIXES

5 of 5 reviewers: PASS WITH NOTES. Zero FAILs. The architecture is sound — spike-first approach correctly front-loads the highest-risk unknown (headless `claude -p` behavioral contract). Eight must-fix items, all resolvable without replanning; they are clarifications, a scope correction, and missing done-criteria.

---

## Reviewer Verdicts

| Dimension | Verdict | Key Finding |
|-----------|---------|-------------|
| Completeness | PASS WITH NOTES | AC #7 untestable; AC #4/5 lack verification steps |
| Sequencing | PASS WITH NOTES | notify.sh dep is wrong; plan.sh must wait for risk-analysis.sh |
| Risk | PASS WITH NOTES | Remote branch cleanup path missing; Codex fix-attempt unspecified |
| Scope Discipline | PASS WITH NOTES | max_api_calls counter violates spec's explicit cost-ceiling removal |
| Testability | PASS WITH NOTES | No test mechanism for retry/rollback; "clean halt" undefined |

---

## Must Fix Before Building (8 items)

### 1. Formally descope AC #7 or add a task for `/spec --auto`
*(Completeness + Testability — convergent)*

AC #7 requires `/spec --auto` which doesn't exist. The plan defers it as an "Open Question" but it remains in the acceptance criteria, making it an untestable false signal of completeness. **Fix:** Either formally descope AC #7 from v1 (note it in plan.md's Open Questions as "deferred to Phase 2, requires `/spec --auto`"), or add a task to build the `--auto` flag first.

### 2. Remove `max_api_calls` from the plan
*(Scope Discipline — unique)*

The spec explicitly removed the cost ceiling as a user decision. Adding `max_api_calls` back under a different name contradicts a locked spec decision without reopening it. **Fix:** Remove from Design Decision #6 and from `autorun.config.json` schema in plan.md. Remove from `defaults.sh` scope. If the user wants a call ceiling, that's a spec amendment, not a plan addition.

### 3. Specify Codex fix-attempt mechanics
*(Risk — unique)*

"One autonomous fix attempt + re-test" appears in the spec but the plan leaves the implementation undefined: What is the prompt? Is it a second `claude -p` invocation with the test output as context? Does it commit to the same branch? What happens if the fix attempt itself fails with a non-zero exit? Without this, task 10's most complex branch has no contract and will be invented inconsistently. **Fix:** Add to plan.md under Design Decision (or as a note in task 10c): `fix_attempt.sh` (or an inline block in run.sh) invokes `claude -p "<autonomy-directive> Fix the failing test. Context: $(cat $ARTIFACT_DIR/build-log.md)" — commits the fix to `autorun/<slug>`, re-runs `test_cmd`. If test still fails: halt, do not retry fix, leave PR open.

### 4. Add remote cleanup path to the rollback sequence
*(Risk — unique)*

`git reset --hard` is local-only. If a build wave pushes to `autorun/<slug>` and opens a PR before the test failure is detected, the local rollback does nothing to the remote branch or PR. The plan must specify: on final retry failure, run `gh pr close $(cat $ARTIFACT_DIR/pr-url.txt) 2>/dev/null`, then `git push origin --delete autorun/<slug> 2>/dev/null`, before writing `failure.md` and notifying. **Fix:** Add this to task 9 (build.sh) scope.

### 5. Add AC #4 "clean halt" verification checklist to task 9's done-criteria
*(Completeness + Testability — convergent)*

"No dirty branch state" is untestable without a definition. **Fix:** Add to plan.md task 9 done-criteria: clean halt = `git status` shows clean working tree, `state.json.stage` matches the last completed wave, no uncommitted files in `autorun/<slug>` branch, `queue/STOP` still present (not auto-removed).

### 6. Add AC #5 test mechanism: `test_cmd="exit 1"`
*(Completeness + Testability — convergent)*

There is no documented way to force a test failure to test retry×3 logic. **Fix:** Add to plan.md task 9 done-criteria (and to `commands/autorun.md`): "To test retry+rollback: set `test_cmd=\"exit 1\"` in `autorun.config.json`. Run against a real spec. Verify 3 retries fire in `build-log.md`, `git reset --hard` executes, `failure.md` written with correct SHA."

### 7. Fix task 3 (notify.sh) dependency — move after schemas are locked
*(Sequencing — unique)*

`notify.sh` reads `failure.md` and `run-summary.md`. Those schemas are defined in task 9 (build.sh) and task 10 (run.sh) respectively. Implementing notify.sh before those schemas are locked guarantees a rework pass. **Fix:** Change task 3's dependency from `1` to `9` (after build.sh schema is locked). notify.sh can run parallel with task 10.

### 8. Fix task 7 (plan.sh) parallel dependency — must wait for risk-analysis.sh
*(Sequencing)*

At runtime, `plan.sh` reads the merged `review-findings.md` which includes risk-analysis output. The merge must happen in `run.sh` after both spec-review and risk-analysis complete. If task 7 (plan.sh) is built while task 6 (risk-analysis.sh) is still in progress, the context handoff implementation will be written without knowing the full contract. **Fix:** Change task 7's "Parallel?" column from "with 6" to sequential after 6. Task ordering: `5 → 6 → 7 → 8`.

---

## Should Fix (6 items)

1. **Split task 10 into 10a/10b/10c** *(Risk + Scope converge)* — Task 10 bundles 12+ behavioral units. Split: `10a` = orchestrator core (flock, queue loop, state.json, stage sequencing), `10b` = PR creation + provenance block, `10c` = Codex review + fix-attempt gate + squash merge. This matches the natural failure boundaries and makes each piece incrementally testable.

2. **State pre-build SHA write-once invariant explicitly** *(Risk + Testability)* — Add to task 9 done-criteria: "pre-build-sha.txt is written once at Stage 4 entry. On retry 2 and 3, the existing file is preserved (not overwritten). Rollback always uses the capture from the FIRST attempt."

3. **Name the spike fallback if `claude -p` can't dispatch sub-agents** *(Risk)* — If the spike reveals `claude -p` cannot internally parallelize sub-agents, the named fallback is: run each persona as a separate `claude -p` call with an explicit persona prompt injected, then stitch outputs in bash. Add this to plan.md Open Question #2 so the builder knows what to do without stopping.

4. **Add `AUTORUN_DRY_RUN=1` stub mode** *(Testability)* — Highest-leverage missing testability feature. A `AUTORUN_DRY_RUN=1` env var that makes each stage script write a stub output file and exit 0 would let tasks 6–10's wiring be smoke-tested without real API calls. Add to task 1 (defaults.sh) scope.

5. **Add independent verification checklists for tasks 6–8** *(Testability)* — Replicate task 4's spike checklist pattern: 3-item checklist per wrapper (subprocess exits 0, expected output file written, content not empty). Add to plan.md task descriptions.

6. **Mark `AUTORUN_GH_TOKEN` and `autorun wrapper (task 11)` as optional** *(Scope)* — AUTORUN_GH_TOKEN is a best-practice recommendation, not required for any AC. Same for the `autorun start|stop|status` wrapper — AC #1 passes with the raw flock command. Note both as "post-AC optional" to prevent them from blocking the critical path.

---

## Observations

- **`flock` on macOS:** `flock` is available on macOS (`/usr/bin/flock`, standard BSD utility). No fallback needed. The completeness reviewer's concern is not applicable on this platform.
- **AC #6 (macOS notification) is manual-only.** State this explicitly in `commands/autorun.md` so it isn't treated as a blocking gate.
- **Task 5 may expand.** If `$AUTORUN` guards are needed in 3 command files, it's M-L, not S. Budget accordingly.
- **queue/index.md** has no AC mapping — it's nice-to-have UX polish. Demote to post-MVP rather than blocking task 10.
- **mid-crash orphan cleanup:** When orphan state is detected (stale PID), run.sh should delete or reset the `autorun/<slug>` remote branch before re-entering Stage 1. Not a new task — add to task 10a scope.
- **Task 12 should depend on task 11** in practice (autorun.md documents wrapper CLI surface).

---

## Accepted Risks

- **No human gate before auto-merge** — explicit user decision. Documented in `commands/autorun.md`.
- **7 concurrent `claude -p` processes with no rate-limit handling** — accepted risk. run.log captures 429s post-hoc.
- **`timeout 300 claude -p`** — a legitimate wave >5 min will be killed silently. Tradeoff of hung-process protection vs. legitimate long runs. Accepted.
- **git reset --hard is local-only** — documented. Remote cleanup path added as Must Fix #4.
- **`claude -p` parallelism unverified** — spike item 1 will resolve. Overnight-viable either way.

---

## Plan Amendments Required

Before `/build`, update `docs/specs/autonomous-overnight-pipeline/plan.md` with:

1. Descope AC #7 to Phase 2 in Open Questions
2. Remove `max_api_calls` from Design Decision #6 and config schema
3. Add Codex fix-attempt mechanics specification (Design Decision or task 10 note)
4. Add remote cleanup sequence to task 9 scope
5. Add AC #4 "clean halt" verification checklist to task 9 done-criteria
6. Add `test_cmd="exit 1"` as AC #5 test mechanism in task 9 done-criteria
7. Change task 3 dep: `1` → `9`
8. Change task 7: remove parallel with 6, make sequential after 6

---

## Conflicts Resolved

- **max_api_calls: Scope says remove vs. Risk says keep** — Scope wins. The user explicitly closed the cost-ceiling question during spec Q&A. The plan cannot reopen a locked spec decision unilaterally.
- **autorun wrapper: Scope says demote vs. UX says keep** — Compromise: keep the task, mark it optional/post-AC so it doesn't block critical path.
- **queue/index.md: Risk/UX says keep vs. Scope says no AC** — Demote to post-MVP. No AC requires it.
