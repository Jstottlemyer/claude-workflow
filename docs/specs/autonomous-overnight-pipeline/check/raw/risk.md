**Verdict:** PASS WITH NOTES — The plan is structurally sound and the spike-first approach is the right risk-reduction strategy, but several gaps in the failure/cleanup paths and one task sizing underestimate need resolution before execution.

**Must Fix:**

1. **Remote push + PR before rollback detected — no recovery path.** The plan documents that `git reset --hard` is local-only, but stops there. If wave N pushes to `autorun/<slug>`, opens a PR, and then the post-build test fails, `reset --hard` cleans local state but the remote branch and PR remain. run.sh needs an explicit recovery sequence: `gh pr close <pr>`, `git push origin --delete autorun/<slug>`, then proceed to retry or failure.

2. **Mid-crash orphan cleanup path is not specified.** state.json orphan detection writes `failure.md` and re-queues from Stage 1, but the `autorun/<slug>` branch may already exist with partial commits. The plan notes "if branch exists, reset to main" — but only in the build stage context, not in the pre-Stage-1 cleanup path. A stale branch with commits that partially passed review needs explicit cleanup (delete or reset remote branch) before re-entering Stage 1.

3. **Codex fix attempt mechanics are unspecified.** The spec says "one autonomous fix attempt + re-test" but run.sh's implementation is undefined: what is the prompt, is it a second `claude -p` invocation, what context does it receive (test output? the diff?), and how does failure of the fix attempt itself get handled? This is enough implementation surface to be a blocking unknown.

**Should Fix:**

4. **Task 10 (run.sh) is XL, not L.** Responsibilities: flock, queue loop, state.json reads/writes, call counter, parallel spec-review dispatch, context handoff file construction, PR creation, Codex invocation with timeout, fix attempt branch, squash merge, index.md append, notify. That is 12+ distinct behavioral units. Marking it L will cause the build agent to underallocate time and testing effort.

5. **Task 9 (build.sh) retry × rollback complexity is underestimated.** Pre-build SHA capture semantics need explicit statement: does rollback always use the same write-once pre-build-sha.txt (YES), or does each retry re-capture? This invariant must be stated before implementation.

6. **Spike fallback if `claude -p` doesn't support tool use / sub-agent dispatch.** The fallback is documented as "add $AUTORUN guards" — but that addresses approval gates only. If `claude -p` can't dispatch sub-agents, the named fallback is: "run each persona as a separate `claude -p` call with an explicit persona prompt, stitch outputs in bash."

**Observations:**

- Task 5 ("evaluate spike; add $AUTORUN guards if needed") may be L if three command files need surgical edits.
- The `max_api_calls` counter is queue-wide, not per-item — a single slow item could exhaust the budget.
- pre-build-sha.txt as write-once in a retry loop needs explicit handling: if it already exists when retry begins, preserve it (do not overwrite).
- index.md append in run.sh is a race condition if multiple run.sh processes ever coexist — note even if not fixing now.
