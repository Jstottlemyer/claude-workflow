**Verdict:** PASS WITH NOTES — the plan has one well-defined test mechanism (task 4 spike checklist) but leaves several ACs with no stated verification path and relies on full-pipeline manual runs as the primary integration test.

**Must Fix:**

- **AC #5 (retry + rollback): No documented mechanism for forcing a test failure.** `test_cmd=""` skips tests entirely. The plan needs a named escape hatch (e.g., `test_cmd="exit 1"`) so retry×3 and rollback can be exercised without requiring an actual broken test suite. Without this, rollback logic ships untested until something genuinely fails.

- **AC #4 (STOP kill-switch): "Clean" is undefined.** "No dirty branch state" needs a verification checklist: `git status` clean, `state.json.stage` reflects last completed wave, no orphaned temp branches. Must be written before task 9 is considered done.

- **AC #7 (.prompt.txt → `/spec --auto`): Un-testable in v1.** Either descope AC #7 from v1 acceptance criteria explicitly, or add a task for the `--auto` flag. Leaving an un-testable AC in the acceptance list is a false signal of completeness.

**Should Fix:**

- **No DRY_RUN mode.** Every integration test of run.sh, build.sh, and the orchestrator invokes real `claude -p` calls. `AUTORUN_DRY_RUN=1` that stubs stage scripts to `exit 0` would let tasks 6–10 be smoke-tested without API cost. Highest-leverage missing testability feature.

- **Tasks 6–8 have no independent verification checklists.** Each should have a 2–3 item checklist analogous to task 4's spike checklist (subprocess exits 0, expected output file written, schema valid).

- **max_api_calls counter has no test path.** A counter that never fires is indistinguishable from one that is correctly tracking. Add a test case with `max_api_calls=2` on a pipeline that would make more calls.

- **autorun.config.json validation has no invalid-config test case.** Add: one missing required key, one out-of-range value, verify run.sh exits non-zero with human-readable error.

**Observations:**

- Task 4's 6-item spike checklist pattern should be replicated for tasks 9 and 10.
- AC #6 (macOS notification) is likely manual-only — state this explicitly.
- AC #3 (squash merge) has no short-circuit for testing without real Codex execution — a stub mode (`queue/.codex-stub.json`) would allow merge logic to be tested independently.
- state.json pre-build-sha write-once behavior needs a verification assertion: on re-invoke mid-build, existing SHA should be preserved, not overwritten.
