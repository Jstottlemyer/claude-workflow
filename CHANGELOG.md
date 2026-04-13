# Changelog

All notable changes to `claude-workflow` are documented here.

## [Unreleased]

### Added

- **`/spec` upgrade** (formerly `/brainstorm`, renamed 2026-04-12 to avoid namespace collision with the deprecated `superpowers` brainstorm command):
  - **Phase 0: Context Exploration** — reads constitution, existing specs, project `CLAUDE.md`, `README`, and the last 20 git commits before the first question. Displays a one-paragraph context summary.
  - **Phase 2: Approach Proposal** (feature-sized work only) — proposes 2-3 distinct approaches with tradeoffs and a recommendation; user picks one before the later Q&A rounds. Skipped for bug-fix and small-change work. If the user declines (*"skip approaches"*), the spec records *"user-directed; no alternatives explored."*
  - **Phase 3: Self-Review Pass** — hybrid behavior after drafting the spec: auto-fixes placeholders and formatting silently; loops one targeted question for semantic contradictions; flags remaining issues in Open Questions.
  - **Recommendation-per-question pattern** — every multiple-choice question includes Claude's lean and reasoning. Codifies what was previously an informal pattern.
  - **Per-command auto-run** — `/spec` can auto-write and auto-invoke `/review` when `auto_enabled` is set AND average confidence ≥ `auto_threshold` (default 0.90) AND minimum single-dimension score ≥ `auto_floor` (default 0.70). Enabled via `--auto` CLI flag or `auto_enabled: true` in the constitution's governance section; CLI overrides.
  - **Symmetry preamble** — `/spec` now carries the same *"Do NOT invoke superpowers skills"* preamble as `/plan`/`/review`/`/check`/`/build`.
- **`/spec`-upgrade feature spec** committed at `docs/specs/spec-upgrade/spec.md` — the specification that drove this upgrade (written via the prior `/spec` command). 0.89 final confidence with 3 Open Questions resolved in this release:
  - User-declines-approaches → record "user-directed" in spec and continue.
  - Auto-run config surface → CLI flag + constitution setting, CLI wins.
  - Commit-read count → fixed at 20 for MVP.
- **Example spec** at `docs/specs/example-feature/spec.md` — reference output demonstrating the upgraded `/spec` flow. Doubles as onboarding documentation.

### Changed

- **`/brainstorm` → `/spec`** — all pipeline commands (`/kickoff`, `/plan`, `/review`, `/check`, `/build`, `/flow`) updated to reference `/spec`. Home `CLAUDE.md` and memory entries updated. Rename was driven by a hard namespace collision with the `superpowers` plugin's deprecated `brainstorm` command; `/spec` is more honest anyway (it produces `spec.md`) and leaves room to extend the command with related spec workflows.

### Deprecated

- None.

### Removed

- None.

### Fixed

- **Namespace collision** between user `/brainstorm` and `superpowers:brainstorm` — resolved by rename.

### Security

- None.

### Known Limitations / Planned for v1.1

- **Approach-proposal trigger heuristic** — during the first smoke-test run (ModelTraining `workflow-map` spec, 2026-04-12), the Phase 2 approach-proposal step **did not fire as a distinct phase** because the feature's structural questions (artifact format, content scope) implicitly carried approach-choice. Need a clearer trigger rule for when the dedicated 2-3-approach proposal runs vs. when structural Qs naturally subsume it. Lean: trigger explicitly when the feature has an architecture / design dimension (e.g., a new service, a new data flow); skip when the feature is essentially "configure X to have shape Y" and structural Qs are the design.
