---
name: autorun-dryrun
description: Run the autorun pipeline in DRY_RUN mode against a fixture spec and assert each expected artifact landed. Use as a smoke test after editing scripts/autorun/* to confirm orchestration wiring still works without burning API cost.
disable-model-invocation: true
---

# /autorun-dryrun

Smoke-test the MonsterFlow autorun pipeline in DRY_RUN mode.

## What it does

1. Stages a fixture spec (`tests/fixtures/autorun-dryrun/sample.spec.md`) into a temporary `queue/` directory under `$TMPDIR`.
2. Runs `AUTORUN_DRY_RUN=1 bash scripts/autorun/run.sh` against that queue.
3. Asserts every expected artifact landed in `queue/sample/`:
   - `review-findings.md` (or stub equivalent)
   - `risk-findings.md`
   - `plan.md`
   - `check.md`
   - `pre-build-sha.txt`
   - `build-log.md`
   - `verify-gaps.md` containing `VERDICT: COMPLIANT`
   - `state.json`
4. Cleans up the temp queue.
5. Reports pass/fail summary with diffs to expected artifact list.

## Execution

Invoke via the user's terminal (not in-session — the skill runs the actual pipeline):

```bash
bash tests/autorun-dryrun.sh
```

The runner script (`tests/autorun-dryrun.sh`) is the canonical implementation. This SKILL.md exists so the user can invoke `/autorun-dryrun` and Claude knows to execute that script and surface the output.

## When to invoke

- After any edit to `scripts/autorun/*.sh` — confirms orchestration still works end-to-end
- Before tagging a release — final smoke test
- When debugging stage handoff issues — isolates whether the wiring is broken vs the stage logic

## Output

Pass:
```
✓ all 8 artifacts present
✓ verify-gaps.md contains VERDICT: COMPLIANT
✓ state.json valid
PASS — autorun dry-run complete in 3.2s
```

Fail:
```
✗ missing: queue/sample/check.md
✗ verify-gaps.md does not contain VERDICT: COMPLIANT (got: VERDICT: INCOMPLETE)
FAIL — 2 assertions failed
```

## Implementation note

This skill is `disable-model-invocation: true` because it has side effects (writes/deletes a temp queue, executes shell pipeline). Only the user can fire it via `/autorun-dryrun`.
