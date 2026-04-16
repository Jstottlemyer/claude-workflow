# `/spec` Upgrade Spec

**Created:** 2026-04-12
**Constitution:** none yet for `claude-workflow`; proceeded without constraints (tracked as follow-up)
**Confidence:** 0.89 (proceeded with 3 Open Questions flagged)

## Summary

Upgrade the `/spec` command with three enhancements adapted from the `superpowers:brainstorming` skill — explore project context first, propose 2-3 approaches with tradeoffs when work-size warrants, and run a spec self-review pass before presenting. Add two new patterns alongside: every multiple-choice question carries Claude's recommendation with reasoning; and a per-command auto-run option that auto-writes the spec and auto-invokes `/review` when confidence passes a threshold-with-floor check. All changes preserve the existing `/spec` discipline (confidence gate, constitution-awareness, persistent spec artifacts, pipeline cohesion into `/review → /plan → /check → /build`).

## Scope

### In Scope
- **Context-first exploration** before Q1 — read in order: `docs/specs/constitution.md`, existing specs under `docs/specs/*/spec.md`, project `README`, project `CLAUDE.md`, recent commits (`git log --oneline -20` equivalent where git is available). Display a one-short-paragraph context summary before the first question.
- **Approach proposal** — a pre-draft sub-phase, **gated by work-size**. For feature-sized work, Claude proposes 2-3 approaches with tradeoffs and a recommendation; user picks one before remaining detail questions. Bug-fix and small-change work skip this phase entirely.
- **Spec self-review pass** after the draft is produced, before presenting to the user — **hybrid behavior**: placeholders, formatting issues, and trivial duplicates auto-fix inline; semantic contradictions loop back with one targeted question; if still unresolved after one loop, flag in Open Questions and proceed.
- **Recommendation-per-question pattern** — every multiple-choice question includes Claude's lean and the reasoning. Codifies the pattern already used in practice.
- **Per-command auto-run option** for `/spec`:
  - Trigger: average confidence across 6 dimensions ≥ `auto_threshold` AND no single dimension below `auto_floor`.
  - Defaults: `auto_threshold = 0.90`, `auto_floor = 0.70`, `auto_enabled = false` (must be opted in).
  - Behavior on trigger: write spec, display `"Spec written: <path>. Auto-proceeding to /review — reply to abort."`, auto-invoke `/review` on the next turn unless the user sends a message.
- **Symmetry with existing pipeline commands**: `/spec` picks up the standard `"IMPORTANT: Do NOT invoke superpowers skills from this command"` preamble that `/plan`/`/review`/`/check`/`/build` already carry.

### Out of Scope
- **Context-backend evaluation** (Graphify, Obsidian-Wiki, llm-wiki-compiler) — deferred to a dedicated future spec. `/spec` stays file-read-based for this upgrade.
- **Extending auto-run to `/review`/`/plan`/`/check`/`/build`** — per-command, one at a time, after `/spec` ships and the pattern is proven.
- **Changes to the `spec.md` output format** — the generated spec artifact keeps its current structure; existing specs remain valid without migration.
- **Visual companion** (superpowers' browser-based mockups) — not included.
- **Automated test harness** for `/spec` — manual smoke test suffices for this release; automation of an interactive Q&A is its own future project.

## UX / User Flow

1. User invokes `/spec <idea>` (or `/spec` without args).
2. **Pre-flight** (existing): constitution presence check; existing-spec detection; work-size selector.
3. **Context exploration** (new): read the context sources listed above and display a one-paragraph summary, e.g. *"Context: Swift/SpriteKit game project, constitution v1.2 emphasizes accessibility-first, 4 prior specs in `docs/specs/`, recent work on scoring system."*
4. **Q&A phase**:
   - One question per message.
   - Each question is multiple-choice where possible, with Claude's recommendation and reasoning.
   - Confidence scores across 6 dimensions displayed after every answer.
5. **Approach proposal** (new, feature-sized work only): once scope is clear, Claude proposes 2-3 approaches with tradeoffs and a recommendation. User picks before remaining detail questions.
6. **Confidence gate**:
   - Manual mode: at ≥ 0.90, announce readiness, user approves.
   - Auto mode (if enabled): check `avg ≥ auto_threshold` AND `min ≥ auto_floor`; if met, proceed to step 7 without explicit approval; if not, fall back to manual gate.
7. **Draft + self-review** (new): draft the spec, run the self-review pass (auto-fix / loop / flag hybrid), then present.
8. **Present**:
   - Manual: `"Spec written: <path>. Ready for /review."`
   - Auto: `"Spec written: <path>. Auto-proceeding to /review — reply to abort."` Next turn auto-invokes `/review` if no user message interrupts.

## Data & State

### Files Modified
- `~/.claude/commands/spec.md` — command prompt updated with new phases, patterns, and auto-run logic.

### Files Created
- `CHANGELOG.md` (root of `claude-workflow`) — versioned entry describing this upgrade.
- `docs/specs/example-feature/spec.md` — committed example of upgraded `/spec` output; doubles as OSS documentation.

### Config Keys (new)
- `auto_threshold` — average confidence required to auto-proceed. Default `0.90`.
- `auto_floor` — minimum acceptable score for any single dimension. Default `0.70`.
- `auto_enabled` — must be explicitly set true to enable auto-run. Default `false`.

No external state; the command file is self-contained. Config surface (CLI flag, constitution setting, or both) is an Open Question.

## Integration

### Relationship to `/kickoff`
- `/kickoff` reads constitution, `CLAUDE.md`, personas, and template to **bootstrap project principles**. Runs once per project.
- `/spec` now also reads `CLAUDE.md` — deliberate overlap, no shared cache, live reads (staleness is worse than re-reading).
- `/kickoff` writes `docs/specs/constitution.md`. `/spec` reads it. Each command's read-list is its own concern.

### Relationship to downstream commands
- `/review`, `/plan`, `/check`, `/build` — unchanged by this upgrade.
- Auto-run mode auto-invokes `/review` as the next pipeline step.

### Relationship to `superpowers:brainstorming`
- **NOT delegated to.** The superpowers planning skills are redundant with this pipeline.
- The three ideas we adopted (context-first, approach-proposal, self-review) are adapted into `/spec`'s own flow; they do not invoke the superpowers skill.
- The new `"Do NOT invoke superpowers skills"` preamble reinforces separation.

### Backwards Compatibility
- `spec.md` output format unchanged; prior specs remain valid without migration.
- Work-size selector behavior preserved.
- Constitution constraints still applied.

## Edge Cases

- **Missing constitution**: existing behavior — prompt to run `/kickoff` or proceed without constraints. Unchanged.
- **No git / no README / no CLAUDE.md**: context exploration gracefully skips missing sources; context summary notes which sources were absent (e.g., *"no README found; proceeding"*).
- **Self-review auto-fix fails on a placeholder**: fall through to the contradiction-loop path (one targeted question).
- **Self-review finds a contradiction**: loop with one targeted question. If still unresolved after the loop, flag in Open Questions and proceed.
- **Auto-threshold average met but one dimension below floor**: do NOT auto-proceed. Prompt: *"Auto-run blocked: <dimension> at <score> (floor: <floor>). Proceed manually?"*
- **User message during auto-proceed notice window**: any incoming message interrupts auto-invocation of `/review`; Claude returns to manual approval flow.
- **Approach proposal for small-change or bug-fix work**: skipped entirely; Q&A proceeds directly.
- **Context-read exceeds token budget**: priority order `constitution > existing specs > CLAUDE.md > README > commits`; truncate commits first (subjects only), then oldest-first.

## Acceptance Criteria

1. **Smoke test passes** — run `/spec` on a dummy feature in `claude-workflow`; verify each upgrade fires:
   - Context summary appears before Q1, includes constitution / README / CLAUDE.md / recent commits signals.
   - Every question is multiple-choice with a recommendation and reasoning.
   - For a feature-sized prompt, the approach-proposal phase triggers; for a small-change prompt, it does not.
   - Self-review pass runs after drafting (visible as a step before presenting), auto-fixes a planted placeholder, loops for a planted contradiction.
   - With `auto_enabled=true`, `/spec` auto-writes and auto-invokes `/review` when thresholds are met; with a planted low-floor dimension, auto-run is blocked as designed.
2. **CHANGELOG entry** — `CHANGELOG.md` in `claude-workflow` has a versioned entry describing the upgrade.
3. **Example spec committed** — `docs/specs/example-feature/spec.md` exists and demonstrates the upgraded flow's output.
4. **Backwards compatibility** — running `/spec` against a feature with a prior `spec.md` does not require migration.
5. **Findings note** — short `findings.md` in the feature directory recording what the smoke test verified and anything surprising.

## Open Questions

1. **User declines approach proposal**: if the user says *"I already know what I want, skip the approaches"* during the approach-proposal phase, does `/spec` skip it entirely, or record it as *"user-directed; no alternatives explored"* in the spec? Resolve at build time.
2. **Auto-run config surface**: is `auto_enabled` exposed as a CLI flag, a constitution setting, or both? Lean: both — CLI flag for one-off runs; constitution setting for project-wide default. Confirm at build time.
3. **Commit-read count configurability**: the draft uses 20 recent commits; is this fixed for MVP, or configurable via constitution? Lean: fixed at 20 for MVP; revisit only if feedback indicates the count is wrong.

## Confidence

| Dimension | Score |
|---|---|
| Scope | 0.92 |
| UX/Flow | 0.88 |
| Data | 0.90 |
| Integration | 0.88 |
| Edge cases | 0.85 |
| Acceptance | 0.88 |
| **Overall** | **0.89** |

Proceeded to write with 3 Open Questions flagged per explicit approval at 0.89.
