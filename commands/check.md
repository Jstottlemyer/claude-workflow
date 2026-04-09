---
description: Gap checkpoint — 5 specialist agents validate the plan before implementation begins
---

**IMPORTANT: Do NOT invoke superpowers skills from this command. This command IS the checkpoint workflow.**

You are the check step in the pipeline: `/brainstorm → /review → /plan → /check → /build`

Your job is to dispatch 5 parallel plan reviewer agents, synthesize their findings into a go/no-go verdict, and present gaps for resolution before implementation begins.

## Pre-flight

1. **Find artifacts**: Load `docs/specs/<feature>/spec.md`, `docs/specs/<feature>/review.md`, and `docs/specs/<feature>/plan.md`.
   - If `$ARGUMENTS` names a feature, use that.
   - If plan doesn't exist: "No plan found. Run /plan first."

2. **Load constitution** (if exists) for constraint checking.

## Phase 1: Dispatch 5 Plan Reviewer Agents

Read the persona files from `~/.claude/personas/check/` and dispatch 5 parallel subagents using the Agent tool. Each agent receives:
- The spec, review findings, and plan
- The constitution (if exists)
- Their persona's role, checklist, and key questions

The 5 reviewers:
1. **completeness** — Are all requirements covered? What's missing?
2. **sequencing** — Is the order right? Are dependencies correct?
3. **risk** — What could go wrong? What are the unknowns?
4. **scope-discipline** — Is there unnecessary work? What can be cut?
5. **testability** — Can we verify the plan worked?

Each agent must return:
- Verdict: PASS / PASS WITH NOTES / FAIL
- Must Fix (blocks implementation)
- Should Fix (important but not blocking)
- Observations (non-blocking notes)

## Phase 2: Synthesize

After all 5 agents return:

1. **Aggregate verdicts** — any FAIL means NO-GO
2. **Consolidate must-fix items** — deduplicate, flag cross-reviewer findings
3. **Determine overall verdict**: GO / GO WITH FIXES / NO-GO

## Phase 3: Present & Write

1. **Present the checkpoint**:
   ```
   === CHECK: [Feature Name] ===

   Overall verdict: [GO / GO WITH FIXES / NO-GO]

   ## Reviewer Verdicts
   | Dimension | Verdict | Key Finding |
   |-----------|---------|-------------|
   | Completeness | PASS/NOTES/FAIL | ... |
   | Sequencing | PASS/NOTES/FAIL | ... |
   | Risk | PASS/NOTES/FAIL | ... |
   | Scope Discipline | PASS/NOTES/FAIL | ... |
   | Testability | PASS/NOTES/FAIL | ... |

   ## Must Fix Before Building ([count] items)
   [Blocking issues that need resolution]

   ## Should Fix ([count] items)
   [Important but won't block build]

   ## Observations
   [Non-blocking notes]

   [If GO]: Ready for /build. (go / hold)
   [If GO WITH FIXES]: Address fixes above, then /build. (fix now / defer to build / hold)
   [If NO-GO]: Revise plan with /plan, then re-run /check.
   ```

2. **Write `docs/specs/<feature>/check.md`** with the full checkpoint results.

## On GO

If Justin says go:
```
Checkpoint passed. Ready for /build.
```

## On Fix Now

Address the must-fix items by updating plan.md, then re-present. Do NOT re-run all 5 reviewers — only re-check the specific dimensions that had FAIL verdicts.

## On NO-GO

```
Checkpoint failed. The plan needs revision.
Key issues: [list the FAIL reasons]

Run /plan to revise, then /check again.
```

## Key Principles

- **This is the last gate before code** — be rigorous
- **Parallel execution** — all 5 reviewers run simultaneously
- **Verdict-driven** — clear PASS/FAIL, not ambiguous
- **Fix gaps here, not during build** — that's the whole point of this step
- **Persistent artifacts** — check.md survives the session

**Arguments**: $ARGUMENTS
