---
description: Design and implementation planning — 6 specialist agents explore architecture, then produce an implementation plan
---

**IMPORTANT: Do NOT invoke superpowers skills from this command. This command IS the planning workflow.**

You are the plan step in the pipeline: `/brainstorm → /review → /plan → /check → /build`

Your job is to dispatch 6 parallel design agents, synthesize their analysis into an implementation plan, and present it for approval.

## Pre-flight

1. **Find artifacts**: Load `docs/specs/<feature>/spec.md` and `docs/specs/<feature>/review.md`.
   - If `$ARGUMENTS` names a feature, use that.
   - If neither exists: "No spec or review found. Run /brainstorm first."
   - If spec exists but no review: "Spec found but not reviewed. Run /review first, or proceed without review? (Skipping review increases rework risk.)"

2. **Load constitution** (if exists) for constraint checking.

## Phase 1: Dispatch 6 Design Agents

Read the persona files from `~/.claude/personas/plan/` and dispatch 6 parallel subagents using the Agent tool. Each agent receives:
- The spec content
- The review findings (if available)
- The constitution (if exists)
- Their persona's role, checklist, and key questions

The 6 designers:
1. **api** — Interface design and developer/user ergonomics
2. **data-model** — Data model, storage, and migrations
3. **ux** — User experience and ergonomics
4. **scalability** — Performance at scale and bottlenecks
5. **security** — Threat model and attack surface
6. **integration** — How it fits existing system

Each agent must return:
- Key Considerations
- Options Explored (with pros/cons/effort)
- Recommendation
- Constraints Identified
- Open Questions
- Integration Points with other dimensions

## Phase 2: Judge + Synthesize into Implementation Plan

After all 6 agents return, apply two passes using the personas in `~/.claude/personas/`:

**Pass 1 — Judge** (read `personas/judge.md`):
1. Remove duplicate recommendations across agents → merge into one
2. Resolve contradictions (e.g., security vs UX tradeoff) → pick one with rationale, or flag for human input
3. Demote speculative concerns that don't apply to current scope
4. Promote recommendations with convergent signal (2+ agents aligned)

**Pass 2 — Synthesis** (read `personas/synthesis.md`, use Plan output structure):
1. Produce unified architecture summary from all agent recommendations
2. Compile key design decisions with rationale
3. Surface open questions requiring human input
4. Build consolidated risk register
5. **Produce implementation plan** with:
   - Ordered task breakdown
   - Dependencies between tasks
   - Which tasks can run in parallel
   - Estimated complexity per task (S/M/L)

## Phase 3: Present & Write

1. **Present the plan**:
   ```
   === PLAN: [Feature Name] ===

   ## Design Decisions
   [Key choices made and rationale]

   ## Implementation Tasks
   | # | Task | Depends On | Size | Parallel? |
   |---|------|-----------|------|-----------|
   | 1 | ... | — | S | — |
   | 2 | ... | 1 | M | — |
   | 3 | ... | 1 | M | Yes (with 2) |

   ## Open Questions
   [Decisions needing Justin's input]

   ## Risks
   [Top risks from design analysis]

   Approve to proceed to /check? (approve / adjust <what to change>)
   ```

2. **Write `docs/specs/<feature>/plan.md`** with the full plan.

## On Approve

```
Plan approved. Ready for /check (5 plan reviewer agents will validate before build).
```

## On Adjust

Modify the plan as requested, re-run affected design agents if needed, re-present.

## Key Principles

- **Parallel execution** — all 6 designers run simultaneously
- **Concrete over abstract** — tasks should be implementable, not vague
- **Show tradeoffs** — why approach A vs B
- **YAGNI** — cut anything not needed for the current scope
- **Persistent artifacts** — plan.md survives the session

**Arguments**: $ARGUMENTS
