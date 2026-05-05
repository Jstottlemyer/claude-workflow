---
description: Gap checkpoint — 5 specialist agents validate the plan before implementation begins
---

**IMPORTANT: Do NOT invoke superpowers skills from this command. This command IS the checkpoint workflow.**

You are the check step in the pipeline: `/spec → /spec-review → /plan → /check → /build`

Your job is to dispatch 5 parallel plan reviewer agents, synthesize their findings into a go/no-go verdict, and present gaps for resolution before implementation begins.

## Pre-flight

1. **Find artifacts**: Load `docs/specs/<feature>/spec.md`, `docs/specs/<feature>/review.md`, and `docs/specs/<feature>/plan.md`.
   - If `$ARGUMENTS` names a feature, use that.
   - If plan doesn't exist: "No plan found. Run /plan first."

2. **Load constitution** (if exists) for constraint checking.

## Phase 0: Persona Metrics — survival classifier (synthesis-inclusion mode)

Pre-flight before reviewers dispatch. If `docs/specs/<feature>/plan/findings.jsonl` exists, run `commands/_prompts/survival-classifier.md` in **synthesis-inclusion** mode:

- Inputs: `<feature>/plan/findings.jsonl` (design recommendations) + `<feature>/plan.md` (freshly synthesized — NO source snapshot, since `plan.md` is created fresh, not revised).
- Idempotency: if `<feature>/plan/survival.jsonl` exists and every row's `artifact_hash` matches `sha256(plan.md)`, skip. If `artifact_hash` differs, re-classify and overwrite.
- Outcome semantics: `addressed` = design recommendation visibly shaped `plan.md`; `not_addressed` = Judge dropped/demoted; `rejected_intentionally` = `plan.md`'s "Alternatives Considered" / "Rejected" / "Deferred" section explicitly names the recommendation.
- Output: atomic write to `<feature>/plan/survival.jsonl`. Schema: `schemas/survival.schema.json`.
- Echo one-liner if any `outcome: "classifier_error"` rows are written: `[persona-metrics] N findings could not be classified — see plan/survival.jsonl for reasons.`

If `<feature>/plan/findings.jsonl` does not exist (legacy spec or `/plan` skipped), this phase is a silent no-op — no `survival.jsonl` written, no error.

**This phase never blocks the stage** — instrumentation failures continue to Phase 1 review work.

## Phase 1, step 0: Snapshot + rotate (persona-metrics)

Before reviewer agents dispatch, run `commands/_prompts/snapshot.md`:

- Snapshot `docs/specs/<feature>/plan.md` → `docs/specs/<feature>/check/source.plan.md`.
- Refuse with `run.json.status: "failed"` if `plan.md` is not git-tracked.
- Validate slug.
- Create `docs/specs/<feature>/check/raw/`.
- Rotate prior `findings.jsonl` to `findings-<UTC-ts>.jsonl` if present.
- Echo one-line user feedback.

## Phase 0b: Resolve persona budget (account-type-agent-scaling)

Before dispatching reviewer agents, run the resolver:

```bash
SELECTED=$(bash <REPO_DIR>/scripts/resolve-personas.sh check \
             --feature "<feature-slug>" --emit-selection-json)
RESOLVER_EXIT=$?
```

- If `RESOLVER_EXIT != 0` or stdout empty: apply `commands/_prompts/_resolver-recovery.md` (canonical recovery fragment — interactive: 3-option prompt; non-tty/autorun: abort). No silent seed fallback in headless mode.
- Dispatch one subagent per line of `$SELECTED` (skipping `codex-adversary`; Codex runs separately at Phase 2b).
- Resolver writes `docs/specs/<feature>/check/selection.json`.
- No `agent_budget` in config → full roster (existing behavior).
- Print one line: `Selected: <names> | Dropped: <names>`.

## Phase 1: Dispatch Plan Reviewer Agents

Read each persona file in `<REPO_DIR>/personas/check/` corresponding to a name in `$SELECTED`, then dispatch one parallel subagent per name using the Agent tool. The legacy 5-reviewer roster (completeness, sequencing, risk, scope-discipline, testability) is the resolver's full-roster fallback. Each agent receives:
- The spec, review findings, and plan
- The constitution (if exists)
- Their persona's role, checklist, and key questions

**As each reviewer agent returns**, persist its raw output to `docs/specs/<feature>/check/raw/<persona>.md` immediately (atomic write). The Phase 2c emit reads from this directory.

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

## Phase 2: Judge + Synthesize

After all 5 agents return, apply two passes using the personas in `~/.claude/personas/`:

**Pass 1 — Judge** (read `personas/judge.md`):
1. Remove duplicate must-fix items flagged by multiple agents → merge with higher confidence
2. Resolve contradictions (e.g., scope-discipline says cut it, completeness says it's missing) → assess and pick with rationale
3. Demote overly cautious findings that don't match actual risk level
4. Verify severity ratings are proportionate

**Pass 2 — Synthesis** (read `personas/synthesis.md`, use Check output structure):
1. Aggregate verdicts — any FAIL means NO-GO
2. Consolidate must-fix items, deduplicated and prioritized
3. List accepted risks the team is choosing to proceed with
4. **Determine overall verdict**: GO / GO WITH FIXES / NO-GO

## Phase 2b: Codex Adversarial Check (if available)

Silent skip if Codex is not installed or not authenticated — no error, no prompt.

```bash
if command -v codex >/dev/null 2>&1 && codex login status >/dev/null 2>&1; then
  codex exec --full-auto --ephemeral \
    --output-last-message /tmp/codex-check-review.txt \
    "Adversarial plan review: challenge whether this is the right implementation approach. Look for: incorrect sequencing assumptions, missing dependencies, tasks that will take longer than expected, better approaches that weren't considered, and risks the plan doesn't account for." \
    < <plan-path>
fi
```

Replace `<plan-path>` with the resolved path to `docs/specs/<feature>/plan.md`. If `/tmp/codex-check-review.txt` exists after the run:
- If Codex surfaces must-fix or should-fix items not already in the Claude synthesis, add a **Codex Adversarial View** subsection to the checkpoint output.
- If Codex finds nothing new, note "Codex: no additional findings."
- If Codex was skipped (not available), omit the section entirely — no mention of it.

**Persist Codex output to disk:** if Codex ran, copy `/tmp/codex-check-review.txt` → `docs/specs/<feature>/check/raw/codex-adversary.md` (atomic write). The Phase 2c emit reads it for `personas[]` attribution.

## Phase 2c: Persona Metrics emit

Run `commands/_prompts/findings-emit.md`. It reads `docs/specs/<feature>/check/raw/*.md` (per-reviewer + optional `codex-adversary.md`) and the synthesizer's clustering decisions, and atomically writes:

- `docs/specs/<feature>/check/findings.jsonl`
- `docs/specs/<feature>/check/participation.jsonl`
- `docs/specs/<feature>/check/run.json`

Schemas + `prompt_version: "findings-emit@1.0"` recorded as in `/spec-review`.

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
