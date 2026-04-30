---
description: Execute the implementation plan with parallel agents
---

**IMPORTANT: Do NOT invoke superpowers planning skills from this command. Superpowers execution skills (debugging, verification) ARE used during build.**

You are the build step in the pipeline: `/spec → /spec-review → /plan → /check → /build`

Your job is to execute the implementation plan using parallel agents where possible, with superpowers discipline skills active.

## Pre-flight

1. **Find artifacts**: Load `docs/specs/<feature>/plan.md` and optionally `docs/specs/<feature>/check.md`.
   - If `$ARGUMENTS` names a feature, use that.
   - If plan doesn't exist: "No plan found. Run /plan first."
   - If check doesn't exist: "Plan not checked. Run /check first, or proceed without checkpoint? (Skipping /check increases rework risk.)"
   - If check exists and verdict was NO-GO: "Checkpoint failed. Fix the plan with /plan first."

2. **Load constitution** (if exists) and spec for context.

## Phase 0: Persona Metrics — survival classifier (addressed-by-revision mode)

Pre-flight before execution. If `docs/specs/<feature>/check/findings.jsonl` exists, run `commands/_prompts/survival-classifier.md` in **addressed-by-revision** mode:

- Inputs: `<feature>/check/findings.jsonl` + `<feature>/check/source.plan.md` (pre-snapshot) + current `<feature>/plan.md` (post-revision).
- **Pre-revision warning:** if `mtime(plan.md) < mtime(check/findings.jsonl)`, emit a warning that `plan.md` hasn't been edited since `/check`. Run anyway.
- Idempotency: skip if recorded `artifact_hash` matches `sha256(plan.md)`; re-classify otherwise.
- Outcome semantics: addressed-by-revision (substance NOT in source.plan.md but IS in plan.md after revision).
- Output: atomic write to `<feature>/check/survival.jsonl`. Echo one-liner if any `classifier_error` rows are written.

If `<feature>/check/findings.jsonl` does not exist, silent no-op.

**This phase never blocks the build.**

## Phase 1: Present Execution Plan

Parse the plan's task breakdown and present:

```
=== BUILD: [Feature Name] ===

Tasks: [total count]
Waves: [count based on dependency analysis]

Wave 1: [tasks with no dependencies] ([count] parallel agents)
Wave 2: [tasks depending on Wave 1] (blocked until Wave 1 completes)
...

Execution discipline:
- Debugging: superpowers:systematic-debugging
- Verification: superpowers:verification-before-completion
- Testing: write thorough tests

[AUTORUN MODE: If AUTORUN=1 is set in your environment, skip this approval prompt. Write all artifacts and proceed immediately to the next stage. Do not output the approval prompt text below.]
Launch Wave 1? (go / hold)
```

## Phase 2: Execute Waves

On go:

1. **Dispatch Wave 1** — launch parallel agents for independent tasks using the Agent tool.
   - Each agent receives: the spec, plan, relevant plan tasks, constitution
   - Each agent writes thorough tests alongside implementation
   - Each agent reports: DONE, DONE_WITH_CONCERNS, NEEDS_CONTEXT, or BLOCKED

2. **Monitor Wave 1** — as agents complete:
   - DONE: mark task complete, unblock Wave 2 dependents
   - DONE_WITH_CONCERNS: review concerns, decide whether to proceed
   - NEEDS_CONTEXT: provide context and resume
   - BLOCKED: investigate, unblock or reassign

3. **Launch subsequent waves** as dependencies resolve.

4. **Between waves**: brief status update to Justin.

## Phase 3: Verification

After all waves complete:

1. Run verification checks (build, tests, lint)

2. **Codex implementation review (if available)** — silent skip if not installed/authenticated:

   ```bash
   if command -v codex >/dev/null 2>&1 && codex login status >/dev/null 2>&1; then
     codex exec review --uncommitted --full-auto --ephemeral \
       --output-last-message /tmp/codex-build-review.txt \
       "Challenge the implementation. Look for: security issues, deviations from the plan, better approaches that weren't taken, and correctness problems the tests might not catch."
   fi
   ```

   If `/tmp/codex-build-review.txt` exists and contains findings, include a **Codex Review** section in the build complete summary. If skipped or no findings, omit.

3. **Run `/preship`** — pre-commit gate before declaring done:
   - `git status` for uncommitted WIP
   - Verify any CLI flags suggested this session
   - Audit numbered instructions from the user (all ✓ before reporting done)

4. Present results:
   ```
   === BUILD COMPLETE: [Feature Name] ===

   Tasks completed: [count]
   Tests: [pass/fail count]
   Build: [pass/fail]

   Concerns raised during build:
   - [any DONE_WITH_CONCERNS items]

   Codex review: [findings summary, or "skipped / no additional findings"]

   Next steps:
   - Code review: superpowers:requesting-code-review (quick) or /code-review (PR)
   - Wrap up: /wrap
   ```

## Key Principles

- **Wave-based execution** — respect dependency order
- **Parallel where possible** — independent tasks run simultaneously
- **Justin controls pace** — approval before each wave (can be overridden with "go all")
- **Superpowers for execution** — debugging, verification skills are active here
- **Report, don't hide** — surface concerns immediately

**Arguments**: $ARGUMENTS
