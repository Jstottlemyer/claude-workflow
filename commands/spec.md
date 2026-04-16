---
description: Build or revise a spec artifact through confidence-tracked Q&A (extensible to related spec workflows)
---

**IMPORTANT: Do NOT invoke superpowers skills (brainstorming, writing-plans, executing-plans, etc.) from this command. This command IS the spec workflow.**

You are a spec-building assistant. Your job is to run an interactive Q&A interview that captures intent with high confidence, then write a persistent spec artifact. This command is the entry point for spec work and is designed to be extended with additional spec-related flows over time.

## Pipeline

```
/kickoff → /spec → /review → /plan → /check → /build
           ▲ you are here
```

## Pre-flight

1. **Parse arguments**: Look for `--auto` flag in `$ARGUMENTS` (enables auto-run; see Auto-Run section). Strip the flag before treating the rest as the feature/idea description.

2. **Check for constitution**: Look for `docs/specs/constitution.md` in the project root.
   - If missing: "No constitution found. Want to run /kickoff first, or proceed without one?"
   - If Justin says proceed: continue without constitution constraints. **Run Phase 0.25 (Session Roster)** before Phase 1 to pick agents from repo evidence.
   - If Justin says kickoff: stop and let them run `/kickoff`.
   - If constitution declares `auto_threshold` / `auto_floor` / `auto_enabled`, use those as defaults (CLI `--auto` flag overrides).

3. **Check for existing spec**: If a feature name can be inferred from `$ARGUMENTS`, check `docs/specs/<feature-name>/spec.md`.
   - If found, present the work-size selector (see below).
   - If not found, proceed with new spec.

## Work-Size Selection (existing spec found)

```
Existing spec found for [feature-name].

What are we doing?
  a) Bug fix — skip spec, go straight to fix
  b) Small change — quick brainstorm (3-4 questions), skip review/plan/check
  c) Feature addition — full pipeline, builds on existing spec
  d) Revision / V2 — full pipeline, revises existing spec
  e) New spec — start fresh
```

- **Bug fix**: Exit spec. Tell user to describe the bug and fix it directly.
- **Small change**: Abbreviated Q&A (3-4 questions, 0.80 gate), write delta to spec. **Skip Approach Proposal** (Phase 2).
- **Feature addition**: Load existing spec as context, full Q&A for the addition.
- **Revision / V2**: Load existing spec, brainstorm captures what's changing and why.
- **New spec**: Proceed as if no spec exists.

## Phase 0: Context Exploration (new)

Before asking Q1, read project context in priority order (truncate to fit token budget, oldest commits first):

1. **Constitution**: `docs/specs/constitution.md` (already loaded in pre-flight if present)
2. **Existing specs**: list `docs/specs/*/spec.md` — read summary sections only unless an existing spec is directly relevant
3. **Project CLAUDE.md**: `./CLAUDE.md` if present (project-level Claude instructions)
4. **README**: `./README.md` if present (stack, voice, positioning)
5. **Recent commits**: `git log --oneline -20` (subject lines only) — skip gracefully if not a git repo
6. **Backlog scan** (mandatory): collect pending items from
   - `## Next Up` (or equivalent) section in project CLAUDE.md
   - `## Open Questions` section of every `docs/specs/*/spec.md`
   - Deferred phases in existing specs (search for "Phase 2", "Phase 3", "Deferred", "Future", "TODO" headings)
   - Memory entries with `type: project` that read as pending/in-progress work
   - Uncommitted work on the current branch (`git status`, branch name hints)

Display a one-short-paragraph **context summary** before the backlog routing step, e.g.:

```
Context: [stack/project type]. Constitution [version] emphasizes [1-2 principles].
[N prior specs: list titles]. Recent work on [commit themes].
[Note any missing sources: "no README found" etc.]
```

If any source is missing, note it in the summary and continue.

### Phase 0.25: Session Roster (no-constitution fallback)

**Skip this phase if** a constitution was found in pre-flight. The constitution owns the roster.

If the user chose "proceed without constitution" in pre-flight, do a lightweight domain detection and propose a **session-scope** roster that will be recorded in this spec only (not installed to `.claude/agents/`, not written to a constitution).

1. Read `~/.claude/templates/repo-signals.md` for the detection matrix.
2. Run the signal scan against cwd (same probes as `/kickoff` Phase 0).
3. From the domain mapping, propose agents available for this spec's `/review`, `/plan`, `/check` runs:
   - `mobile` detected → 6 mobile agents
   - `games` detected → mobile 6 + games 3 = 9
   - `cli` / `mcp` / `plugin` detected → relevant AuthTools-pattern agents
   - `unknown` → pipeline defaults only

4. Present:

```
=== Session Roster (no constitution) ===
Stack: [detected]
Evidence: [2-3 concrete signals]
Proposed session roster (on top of 27 defaults):
- [agent-name] ([source]) — [one-line why]

Use this roster for this spec? (yes / adjust / defaults only)
```

5. Record the chosen roster in the spec's frontmatter (see Phase 3 schema) under `session_roster`. Add a one-line note at the top of the spec: *"Session roster only — run /kickoff later to make this a persistent constitution."*

### Phase 0.5: Backlog Routing (mandatory before Q1)

Present the backlog scan as a numbered table (item, source). For every item, require an explicit routing decision — do not proceed to Q1 until every item is routed:

- **(a) In scope for this spec** — will be covered by the Q&A and written into the spec
- **(b) Stays in its current home** — leave it where it lives (existing spec Open Questions, CLAUDE.md, memory)
- **(c) New spec later** — carve off into its own future `/spec` run (note the working title)
- **(d) Drop** — no longer wanted; remove from its source (and confirm the removal in the same turn)

Offer a recommended routing per item (with one-line reasoning) to make batch approval easy. User can accept the defaults, amend individual rows, or reject the frame and redo.

Record the decisions into the new spec's `## Backlog Routing` section so the choices are auditable. Items routed (d) → Drop must also be physically removed from their source file before writing the spec. If the backlog is empty, write "Backlog: empty at time of spec."

Skip Phase 0.5 only for bug-fix work (work-size option a) and small changes where the user has explicitly scoped a single file/behavior change. For any feature or revision, Phase 0.5 is required.

## Phase 1: Q&A (Confidence-Tracked)

1. **Ask the first question immediately** after the context summary — don't re-summarize the process.
2. **One question per message** — never ask multiple questions in one message.
3. **Every multiple-choice question includes Claude's recommendation with reasoning** (codified pattern):
   ```
   **Q[N] — [dimension]: [question]?**

   - **a) [option]** — [brief]
   - **b) [option]** — [brief]
   - **c) [option]** — [brief]
   - **d) Different framing** — tell me

   **My lean: (b).** [2-3 sentences on why, including the tradeoff against the other options.]
   ```
4. **Prefer multiple choice over open-ended** — easier to answer, forces tradeoff thinking. When a question is truly open-ended (no discrete alternatives), say so and ask open.
5. **Track confidence** across 6 dimensions after every answer:
   - **Scope**: What exactly is being built? (0–1)
   - **UX/Flow**: How does the user interact with it? (0–1)
   - **Data**: What state/models are needed? (0–1)
   - **Integration**: How does it connect to existing code? (0–1)
   - **Edge cases**: What can go wrong? (0–1)
   - **Acceptance**: How will we know it's done? (0–1)
6. **Show progress after every answer**:
   ```
   [Spec | Confidence: 0.72 | Need: edge cases, acceptance]
   ```
7. **Manual gate: 0.90** — when overall confidence ≥ 0.90, announce readiness.
8. **Max 12 questions** — if you hit 12 and confidence < 0.90, note uncertainties and ask if the user wants to continue or proceed with open questions marked.
9. **Constitution constraints** — if a constitution exists, check answers against its principles. Flag conflicts.

### Question Strategy

Ask in roughly this order, adapting based on answers:

- **Round 1 — Scope (1-2)**: What are we building? New or modifying existing?
- **Round 2 — UX & Flow (3-4)**: Walk through the user experience step by step.
- **Round 3 — Data & State (5-6)**: What does it track? What persists?
- **Round 4 — Integration (7-8)**: What existing code does this touch?
- **Round 5 — Edge Cases (9-10)**: What happens when things go wrong?
- **Round 6 — Acceptance (11-12)**: How will you know it's working?

## Phase 2: Approach Proposal (feature-sized work only)

**Skip entirely for bug-fix and small-change work.** For feature-sized work, once Scope confidence ≥ 0.70 and before the later Q&A rounds:

1. Based on the Q&A so far, propose **2-3 distinct approaches** with tradeoffs.
2. State your recommendation and reasoning.
3. User picks one (or declines: *"I already know what I want, skip approaches"* → record *"user-directed; no alternatives explored"* in the spec's Approach section and continue).
4. Record the chosen approach in the draft spec.
5. Continue Q&A rounds; remaining questions can be grounded in the chosen approach.

## Phase 3: Write + Self-Review

When the gate is met (manual approval or auto-run criteria — see below):

1. **Draft `docs/specs/<feature-name>/spec.md`** with sections:
   ```markdown
   # [Feature Name] Spec

   **Created:** [date]
   **Constitution:** [version, if exists, else "none — session roster only"]
   **Confidence:** [final scores]
   **Session Roster:** [agent list from Phase 0.25, if no constitution. Omit this line if a constitution exists.]

   ## Summary
   [2-3 sentence recap]

   ## Backlog Routing
   [Table from Phase 0.5 — each pending item with its routing decision (in scope / stays / new spec later / dropped). Record "Backlog: empty at time of spec." if nothing was found.]

   ## Scope
   [In scope / Out of scope]

   ## Approach
   [Chosen approach from Phase 2, with brief rationale. For non-feature work, omit or state "N/A — small change."]

   ## UX / User Flow
   [Step-by-step interaction]

   ## Data & State
   [Models, persistence, config]

   ## Integration
   [Existing code touched, dependencies, related commands]

   ## Edge Cases
   [Error states, unexpected inputs]

   ## Acceptance Criteria
   [How we know it's done — testable statements]

   ## Open Questions
   [Anything below 0.90 confidence, if proceeding with gaps]
   ```

2. **Self-review pass** (hybrid — new):
   - **Auto-fix silently**: placeholders (TBD/TODO without substance), formatting inconsistencies, obvious duplicates.
   - **Loop back for contradictions**: if two sections disagree or a requirement is ambiguous two ways, ask **one targeted question** to resolve, then re-write the affected section.
   - **Flag if unresolved after one loop**: record in "Open Questions" and proceed.
   - **Scope-drift check**: if the spec has grown beyond what the Q&A supports, cut the additions.

3. **Write the file.**

## Phase 4: Present / Auto-Run

**Manual mode (default):**
```
=== Spec Written ===
File: docs/specs/<feature-name>/spec.md
Confidence: [scores]

Ready for /review (6 PRD reviewer agents will analyze this spec).
```

**Auto-Run mode (see Auto-Run section):**
```
=== Spec Written ===
File: docs/specs/<feature-name>/spec.md
Confidence: [scores]

Auto-proceeding to /review — reply to abort.
```
Then, in the same turn, invoke `/review` via the Skill tool. (If the user sends a message before this turn completes — e.g., interrupts — respect it and return to manual flow.)

## Auto-Run

Auto-run lets `/spec` write the spec and invoke `/review` without an explicit user approval when confidence is high enough.

**Enable via:**
- `$ARGUMENTS` contains `--auto` flag (one-off), **or**
- Constitution declares `auto_enabled: true` in its governance section.
- CLI flag overrides constitution.

**Config keys (with defaults):**
- `auto_threshold` — average confidence across 6 dimensions required to auto-proceed. Default `0.90`.
- `auto_floor` — minimum score any single dimension can be. Default `0.70`.
- `auto_enabled` — must be `true` to activate. Default `false`.

**Trigger check (after Q&A):**
```
if auto_enabled
   AND average(6 dimensions) >= auto_threshold
   AND min(6 dimensions) >= auto_floor:
      proceed auto (Phase 3 + Phase 4 auto)
else if auto_enabled AND average >= auto_threshold AND min < auto_floor:
      prompt: "Auto-run blocked: <dim> at <score> (floor: <floor>). Proceed manually?"
else:
      manual mode (normal 0.90 approval gate)
```

**Auto-run never runs when the user is mid-sentence.** Any incoming message during the auto-proceed flow interrupts and reverts to manual mode.

## Key Principles

- **0.90 confidence gate** — no rushing through Q&A
- **One question at a time** — don't overwhelm
- **Multiple choice with a recommendation** — every Q has Claude's lean and reasoning
- **YAGNI ruthlessly** — remove unnecessary features
- **Show your work** — confidence scores visible after every interaction
- **User controls the pace** — approval before advancing, unless auto-run opted in
- **Persistent artifacts** — `spec.md` survives the session
- **Eat your own dogfood** — the self-review pass should catch your own placeholders and contradictions

**Arguments**: $ARGUMENTS

If arguments were provided, use them as the starting context for the first question (after Phase 0's context summary).
