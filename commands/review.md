---
description: Parallel PRD review — 6 specialist agents analyze the spec for gaps, risks, and ambiguity
---

**IMPORTANT: Do NOT invoke superpowers skills (writing-plans, brainstorming, executing-plans, etc.) from this command. This command IS the review workflow.**

You are the review step in the pipeline: `/brainstorm → /review → /plan → /check → /build`

Your job is to dispatch 6 parallel PRD reviewer agents against the spec, consolidate their findings, and present them for approval.

## Pre-flight

1. **Find the spec**: Check conversation context for a just-completed brainstorm. If not, look for the most recent spec in `docs/specs/*/spec.md`. If `$ARGUMENTS` names a feature, look in `docs/specs/<feature>/spec.md`.

2. **No spec found**:
   ```
   No spec to review.
   Start with: /brainstorm <idea>
   ```

3. **Load constitution** (if `docs/specs/constitution.md` exists) for constraint checking.

## Phase 1: Dispatch 6 PRD Reviewer Agents

Read the persona files from `~/.claude/personas/review/` and dispatch 6 parallel subagents using the Agent tool. Each agent receives:
- The full spec content
- The constitution (if it exists)
- Their persona's role, checklist, and key questions

The 6 reviewers:
1. **requirements** — Success criteria and acceptance conditions
2. **gaps** — What hasn't been thought through yet
3. **ambiguity** — What's unclear, contradictory, or underspecified
4. **feasibility** — Is this buildable? What are the hard problems?
5. **scope** — What's in/out and where scope creep will happen
6. **stakeholders** — Who's affected and whether needs conflict

Each agent must return their findings structured as:
- Critical Gaps (must answer before building)
- Important Considerations (should address but not blocking)
- Observations (non-blocking notes)
- Confidence Assessment (High/Medium/Low)

## Phase 2: Synthesize

After all 6 agents return:

1. **Deduplicate** — identify findings flagged by multiple reviewers (higher confidence)
2. **Prioritize** — must-answer-before-build vs important-but-not-blocking
3. **Check for conflicts** — do reviewers disagree on anything?

## Phase 3: Present & Write

1. **Present consolidated review**:
   ```
   === REVIEW: [Feature Name] ===

   Overall health: [Good / Concerns / Significant Gaps]

   ## Before You Build ([count] items)
   [Prioritized list of critical questions/gaps]

   ## Important But Non-Blocking ([count] items)
   [Should address, won't block]

   ## Observations
   [Non-blocking notes worth considering]

   ## Reviewer Confidence
   | Dimension | Score | Key Finding |
   |-----------|-------|-------------|
   | Requirements | H/M/L | ... |
   | Gaps | H/M/L | ... |
   | Ambiguity | H/M/L | ... |
   | Feasibility | H/M/L | ... |
   | Scope | H/M/L | ... |
   | Stakeholders | H/M/L | ... |

   Approve to proceed to /plan? (approve / refine <what to change>)
   ```

2. **Write `docs/specs/<feature>/review.md`** with the full consolidated review.

## On Approve

Update the spec with any critical gaps that were resolved during review discussion. Announce:
```
Review approved. Spec updated. Ready for /plan.
```

## On Refine

Address the feedback, update the spec, re-run affected reviewers if needed, re-present.

## Key Principles

- **Show artifacts, not process** — present findings, not how they were produced
- **One approval at a time** — don't combine review with planning
- **Justin controls the pace** — he decides when to approve
- **Parallel execution** — all 6 reviewers run simultaneously
- **Persistent artifacts** — review.md survives the session

**Arguments**: $ARGUMENTS
