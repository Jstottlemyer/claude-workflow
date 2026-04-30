Must-fix gaps:

1. **Dirty worktree / branch isolation**: specify hard preconditions before each queue item: clean worktree, current branch, fetch state, unique `autorun/<slug>` branch, and what happens if branch exists. Do not let overnight runs start from ambiguous git state.

2. **Rollback semantics**: “rollback” needs precision. Use `pre_build_sha`, but avoid destructive reset unless the autorun branch owns all changes. Specify whether failed waves commit nothing, commit WIP, or restore via patch/revert. This is a major safety gap.

3. **Test command trust boundary**: `test_cmd` is arbitrary shell. Define where it comes from, whether config/spec may set it, quoting rules, timeout, cwd, env, and max output capture. Treat it as code execution.

4. **PR merge gate**: “Bad wave auto-merges” is listed as accepted risk, but v1 still needs a hard rule: merge only after `test_cmd` passes, Codex review has no blocking findings, PR creation succeeds, and branch is up to date with base.

5. **Concurrency/rate limit behavior**: logging 429s post-hoc is weak. Add retry with exponential backoff or classify 429 as retryable stage failure.

6. **Artifact durability**: queue artifacts are gitignored and ephemeral. Fine, but morning provenance should survive cleanup. Consider copying final summaries into PR body/comments or `docs/specs/<feature>/autorun/`.

Codex fix-attempt mechanics: mostly correct, but specify the exact loop.

Recommended contract:

- Run `codex review` after PR creation or before merge.
- If Codex reports actionable findings, call `claude -p` with:
  - failing test name/output,
  - relevant `build-log.md`,
  - Codex findings,
  - current branch/PR context,
  - explicit instruction to make one focused fix commit.
- Claude must commit the fix.
- Re-run `test_cmd`.
- If it passes, optionally run Codex review once more.
- If the same test fails again, or Claude exits nonzero/no commit is produced, halt and write `failure.md`.

I would cap this at **one Codex-driven fix attempt per queue item**, not per finding, unless you also add a strict global fix-attempt counter.