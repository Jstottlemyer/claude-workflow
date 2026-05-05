---
description: Design and implementation planning — 6 specialist agents explore architecture, then produce an implementation plan
---

**IMPORTANT: Do NOT invoke superpowers skills from this command. This command IS the planning workflow.**

You are the plan step in the pipeline: `/spec → /spec-review → /plan → /check → /build`

Your job is to dispatch 7 parallel design agents, synthesize their analysis into an implementation plan, and present it for approval.

## Pre-flight

1. **Find artifacts**: Load `docs/specs/<feature>/spec.md` and `docs/specs/<feature>/review.md`.
   - If `$ARGUMENTS` names a feature, use that.
   - If neither exists: "No spec or review found. Run /spec first."
   - If spec exists but no review: "Spec found but not reviewed. Run /spec-review first, or proceed without review? (Skipping review increases rework risk.)"

2. **Load constitution** (if exists) for constraint checking.

## Phase 0: Persona Metrics — survival classifier (addressed-by-revision mode)

Pre-flight before design agents dispatch. If `docs/specs/<feature>/spec-review/findings.jsonl` exists, run `commands/_prompts/survival-classifier.md` in **addressed-by-revision** mode:

- Inputs: `<feature>/spec-review/findings.jsonl` + `<feature>/spec-review/source.spec.md` (pre-snapshot) + current `<feature>/spec.md` (post-revision).
- **Pre-revision warning:** if `mtime(spec.md) < mtime(spec-review/findings.jsonl)`, emit a warning: `[persona-metrics] WARNING: spec.md hasn't been edited since /spec-review. Did you mean to revise the spec before running /plan? Running classifier anyway (most findings will likely show not_addressed).` Add `"spec-not-revised-since-review"` to `run.json.warnings[]`.
- Idempotency: if `<feature>/spec-review/survival.jsonl` exists and every row's `artifact_hash` matches `sha256(spec.md)`, skip. If `artifact_hash` differs, re-classify and overwrite.
- Outcome semantics: `addressed` = the revision changed the artifact in a way that resolves the finding (substance NOT in source.spec.md but IS in spec.md); `not_addressed` = no visible revision-driven change; `rejected_intentionally` = revised `spec.md`'s `## Open Questions` / `## Out of Scope` / `## Backlog Routing` / `## Deferred` section explicitly names the finding.
- Output: atomic write to `<feature>/spec-review/survival.jsonl`. Echo one-liner if any `classifier_error` rows are written.

If `<feature>/spec-review/findings.jsonl` does not exist (legacy spec or `/spec-review` skipped), this phase is a silent no-op.

**This phase never blocks the stage.**

## Phase 0b: Resolve persona budget (account-type-agent-scaling)

Before dispatching design agents, run the resolver:

```bash
SELECTED=$(bash <REPO_DIR>/scripts/resolve-personas.sh plan \
             --feature "<feature-slug>" --emit-selection-json)
RESOLVER_EXIT=$?
```

- If `RESOLVER_EXIT != 0` or stdout empty: apply `commands/_prompts/_resolver-recovery.md` (canonical recovery fragment — interactive: 3-option prompt; non-tty/autorun: abort). No silent seed fallback in headless mode.
- Dispatch one subagent per line of `$SELECTED` (skipping `codex-adversary`; Codex runs separately).
- Resolver writes `docs/specs/<feature>/plan/selection.json`.
- No `agent_budget` in config → full roster (existing behavior).
- Print one line: `Selected: <names> | Dropped: <names>`.

## Phase 1: Dispatch Design Agents

Read each persona file in `<REPO_DIR>/personas/plan/` corresponding to a name in `$SELECTED`, then dispatch one parallel subagent per name using the Agent tool. The legacy 7-designer roster (api, data-model, ux, scalability, security, integration, wave-sequencer) is the resolver's full-roster fallback. Each agent receives:
- The spec content
- The review findings (if available)
- The constitution (if exists)
- Their persona's role, checklist, and key questions

**As each design agent returns**, persist its raw output to `docs/specs/<feature>/plan/raw/<persona>.md` immediately (atomic write). The Phase 2c emit reads from this directory. (Note: no snapshot step at `/plan` — `plan.md` is synthesized fresh at this stage, not revised; there is no pre-state to snapshot.)

The 7 designers:
1. **api** — Interface design and developer/user ergonomics
2. **data-model** — Data model, storage, and migrations
3. **ux** — User experience and ergonomics
4. **scalability** — Performance at scale and bottlenecks
5. **security** — Threat model and attack surface
6. **integration** — How it fits existing system
7. **wave-sequencer** — What ships in what wave; data contract precedence (three-gate default: data → UI → tests)

Each agent must return:
- Key Considerations
- Options Explored (with pros/cons/effort)
- Recommendation
- Constraints Identified
- Open Questions
- Integration Points with other dimensions

## Phase 2: Judge + Synthesize into Implementation Plan

After all 7 agents return, apply two passes using the personas in `~/.claude/personas/`:

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

## Phase 2c: Persona Metrics emit

Run `commands/_prompts/findings-emit.md`. It reads `docs/specs/<feature>/plan/raw/*.md` (per-design-persona outputs persisted in Phase 1) and the synthesizer's clustering decisions, and atomically writes:

- `docs/specs/<feature>/plan/findings.jsonl` — one row per design-recommendation cluster, with `personas[]` listing the design personas (api / data-model / ux / scalability / security / integration / wave-sequencer) that contributed.
- `docs/specs/<feature>/plan/participation.jsonl`
- `docs/specs/<feature>/plan/run.json` — `artifact_hash: sha256(plan.md)` (the freshly synthesized plan, not a source snapshot).

`stage: "plan"` recorded on every emitted row. `prompt_version: "findings-emit@1.0"`. The next stage's classifier (`/check` Phase 0 in synthesis-inclusion mode) reads this `findings.jsonl` and judges which design recommendations made it through Judge into `plan.md`.

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

   [AUTORUN MODE: If AUTORUN=1 is set in your environment, skip this approval prompt. Write all artifacts and proceed immediately to the next stage. Do not output the approval prompt text below.]
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

- **Parallel execution** — all 7 designers run simultaneously
- **Concrete over abstract** — tasks should be implementable, not vague
- **Show tradeoffs** — why approach A vs B
- **YAGNI** — cut anything not needed for the current scope
- **Persistent artifacts** — plan.md survives the session

**Arguments**: $ARGUMENTS
