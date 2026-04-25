---
description: Parallel PRD review — 6 specialist agents analyze the spec for gaps, risks, and ambiguity
---

**IMPORTANT: Do NOT invoke superpowers skills (writing-plans, brainstorming, executing-plans, etc.) from this command. This command IS the review workflow.**

You are the review step in the pipeline: `/spec → /spec-review → /plan → /check → /build`

Your job is to dispatch 6 parallel PRD reviewer agents against the spec, consolidate their findings, and present them for approval.

## Pre-flight

1. **Find the spec**: Check conversation context for a just-completed brainstorm. If not, look for the most recent spec in `docs/specs/*/spec.md`. If `$ARGUMENTS` names a feature, look in `docs/specs/<feature>/spec.md`.

2. **No spec found**:
   ```
   No spec to review.
   Start with: /spec <idea>
   ```

3. **Load constitution** (if `docs/specs/constitution.md` exists) for constraint checking.

## Phase 1: Dispatch 6 PRD Reviewer Agents

Read these 6 persona files, then dispatch 6 parallel subagents using the Agent tool:
- `~/.claude/personas/review/requirements.md`
- `~/.claude/personas/review/gaps.md`
- `~/.claude/personas/review/ambiguity.md`
- `~/.claude/personas/review/feasibility.md`
- `~/.claude/personas/review/scope.md`
- `~/.claude/personas/review/stakeholders.md`

Each agent receives:
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
- Verdict: PASS / PASS WITH NOTES / FAIL

## Phase 2: Judge + Synthesize

After all 6 agents return, apply two passes:

**Pass 1 — Judge** (read `~/.claude/personas/judge.md`):
1. Remove duplicate findings flagged by multiple agents → merge into one with higher confidence
2. Resolve contradictions between agents → pick one with rationale
3. Demote vague or speculative findings that aren't actionable
4. Promote findings with convergent signal (2+ agents flagged independently)
5. Check proportionality — is the severity appropriate for actual risk?

**Pass 2 — Synthesis** (read `~/.claude/personas/synthesis.md`, use Review output structure):
1. Organize by topic, not by agent — reader shouldn't need to know which agent said what
2. Identify themes multiple agents converged on
3. Identify gaps no agent covered
4. Write in direct language — no hedging

## Phase 2b: Codex Adversarial Check (if available)

Silent skip if Codex is not installed or not authenticated — no error, no prompt.

```bash
if command -v codex >/dev/null 2>&1 && codex login status >/dev/null 2>&1; then
  codex exec --full-auto --ephemeral \
    --output-last-message /tmp/codex-spec-review.txt \
    "Adversarial spec review: challenge the assumptions, tradeoffs, and design decisions in this spec. Look for missing failure modes, incorrect assumptions, better alternatives that weren't considered, and scope that will cause problems later." \
    < <spec-path>
fi
```

Replace `<spec-path>` with the resolved path to the spec file. If the file exists at `/tmp/codex-spec-review.txt` after the run:
- If Codex surfaces findings not already in the Claude synthesis, add a **Codex Adversarial View** subsection to the consolidated review with those findings.
- If Codex finds nothing new, note "Codex: no additional findings."
- If Codex was skipped (not available), omit the section entirely — no mention of it.

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

   ## Reviewer Verdicts
   | Dimension | Verdict | Key Finding |
   |-----------|---------|-------------|
   | Requirements | PASS/NOTES/FAIL | ... |
   | Gaps | PASS/NOTES/FAIL | ... |
   | Ambiguity | PASS/NOTES/FAIL | ... |
   | Feasibility | PASS/NOTES/FAIL | ... |
   | Scope | PASS/NOTES/FAIL | ... |
   | Stakeholders | PASS/NOTES/FAIL | ... |

   ## Conflicts Resolved
   [Any agent disagreements and how they were resolved]

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
- **You control the pace** — you decide when to approve
- **Parallel execution** — all 6 reviewers run simultaneously
- **Persistent artifacts** — review.md survives the session

**Arguments**: $ARGUMENTS
