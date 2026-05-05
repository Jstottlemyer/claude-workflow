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

## Phase 1, step 0: Snapshot + rotate (persona-metrics)

Before reviewer agents dispatch, run the snapshot directive at `commands/_prompts/snapshot.md`:

- Snapshot `docs/specs/<feature>/spec.md` → `docs/specs/<feature>/spec-review/source.spec.md` (atomic write).
- Refuse with `run.json.status: "failed"` if `spec.md` is not git-tracked.
- Validate slug against `^[a-z0-9][a-z0-9-]{0,63}$`.
- Create `docs/specs/<feature>/spec-review/raw/` directory.
- If a prior `findings.jsonl` exists in `docs/specs/<feature>/spec-review/`, rename it to `findings-<UTC-ts>.jsonl` (format `%Y-%m-%dT%H-%M-%SZ`) BEFORE the new emit at Phase 2c. Filename is the only superseded marker — no schema mutation.
- Echo one-line user feedback (`[persona-metrics] snapshot ... (rotated N prior)`).

If snapshot refuses, halt the phase — do not dispatch reviewers.

## Phase 0b: Resolve persona budget (account-type-agent-scaling)

Before dispatching reviewers, run the resolver to determine which personas to dispatch:

```bash
SELECTED=$(bash <REPO_DIR>/scripts/resolve-personas.sh spec-review \
             --feature "<feature-slug>" --emit-selection-json)
RESOLVER_EXIT=$?
```

- If `RESOLVER_EXIT != 0` or stdout is empty: **abort the gate** (do not silently fall back to a hardcoded list — this would defeat the budget).
- Otherwise, dispatch one subagent per line of `$SELECTED` (skipping `codex-adversary`, which is handled by Phase 2b).
- The resolver writes `docs/specs/<feature>/spec-review/selection.json` with the audit row.
- If `~/.config/monsterflow/config.json` is absent or has no `agent_budget`, the resolver emits the full roster — existing behavior preserved.
- Print one line to gate stdout: `Selected: <names> | Dropped: <names>` (read these from `selection.json`).

## Phase 1: Dispatch PRD Reviewer Agents

Read each persona file in `<REPO_DIR>/personas/review/` corresponding to a name in `$SELECTED`, then dispatch one parallel subagent per name using the Agent tool. The legacy hardcoded list (requirements, gaps, ambiguity, feasibility, scope, stakeholders) is the resolver's full-roster fallback — when the user has no budget configured, all six dispatch as before.

Each agent receives:
- The full spec content
- The constitution (if it exists)
- Their persona's role, checklist, and key questions

**As each reviewer agent returns**, persist its raw output to `docs/specs/<feature>/spec-review/raw/<persona>.md` immediately (atomic write via tmp + `os.replace`). This file-backed persistence is the structural fix that retires R1 (raw outputs no longer depend on conversation context surviving truncation). The `findings-emit` step at Phase 2c reads from this directory.

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

**Persist Codex output to disk** (parallel to per-persona raw outputs from Phase 1): if Codex ran successfully, copy `/tmp/codex-spec-review.txt` → `docs/specs/<feature>/spec-review/raw/codex-adversary.md` (atomic write). The `findings-emit` step at Phase 2c reads this file to attribute `codex-adversary` in `personas[]` for any cluster that includes Codex's contribution.

## Phase 2c: Persona Metrics emit

Run the directive at `commands/_prompts/findings-emit.md`. It reads the on-disk `docs/specs/<feature>/spec-review/raw/*.md` files (per-reviewer outputs + optional `codex-adversary.md`), reads the synthesizer's clustering decisions from this turn's context, and atomically writes:

- `docs/specs/<feature>/spec-review/findings.jsonl`
- `docs/specs/<feature>/spec-review/participation.jsonl`
- `docs/specs/<feature>/spec-review/run.json`

Schemas at `schemas/{findings,participation,run}.schema.json`. `prompt_version: "findings-emit@1.0"` recorded on every emitted row.

If the metrics paths are tracked-and-not-gitignored AND `docs/specs/<feature>/.persona-metrics-warned` does not yet exist, print a one-line privacy warning and touch the sentinel file (suppresses warning on subsequent stage emits in the same feature).

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

   [AUTORUN MODE: If AUTORUN=1 is set in your environment, skip this approval prompt. Write all artifacts and proceed immediately to the next stage. Do not output the approval prompt text below.]
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
