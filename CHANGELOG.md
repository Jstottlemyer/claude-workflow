# Changelog

All notable changes to `claude-workflow` are documented here.

## [Unreleased]

### Added

- **`/spec` Phase 0.2: Adaptive Wiki-Query Callout** (obsidian-wiki integration — **read side of a two-release rollout; write-side `/wrap` Phase 2c ships next**):
  - After Phase 0's context summary, `/spec` invokes the `wiki-query` skill against the raw `$ARGUMENTS` string to surface prior compiled knowledge on the spec topic.
  - Renders a `### Prior wiki knowledge` callout between the context summary and Phase 0.25 / Phase 0.5 Backlog Routing **when `wiki-query` returns ≥1 cited `[[wikilink]]`**. Callout is silent when `wiki-query` returns empty or a "doesn't cover" compensatory tangent — no "no prior wiki" noise.
  - **Max 5 citations** per callout, ranked by `wiki-query`'s own ordering (no re-ranking). Overflow appends *"(N additional pages omitted — run `wiki-query` directly for full results)"*.
  - **Per-page one-liner** sourced from the cited page's `summary:` frontmatter field (capped at 200 chars per obsidian-wiki's contract). Fallback: first non-empty prose line after frontmatter, with leading heading markers stripped, truncated to 200 chars. No agent re-prompting for synthesis at the per-page level.
  - **Stitched-synthesis line** (1-2 sentences across the cited pages) renders **only when the callout has ≥3 citations** — with fewer pages, per-page summaries stand on their own.
  - **Suppress-wins precedence:** if `wiki-query`'s answer contains `"doesn't cover"` / `"not covered"` / `"the wiki doesn't"` phrasing, the callout is suppressed even if wikilinks appear elsewhere. Compensatory "but see..." tangents don't count as affirmative knowledge.
  - **Self-enforced 10s soft timeout.** Claude Code's Skill tool has no runtime timeout primitive — the host agent monitors wall-clock and silently skips the callout if `wiki-query` stalls. On timeout, appends a `QUERY_TIMEOUT` log line to `$OBSIDIAN_VAULT_PATH/log.md` for future latency diagnosis.
  - **Opt-in signal:** existence of `~/.obsidian-wiki/config`. No new config keys, no new env vars. If obsidian-wiki is not installed, Phase 0.2 is a silent no-op.
  - **Host-agent note** added to the top of `spec.md`: the integration assumes Claude Code Skill-tool invocation; other agents (Cursor, Codex, Hermes, OpenClaw) invoke `wiki-query` via their native skill mechanism. Obsidian-wiki already ships per-agent skill discovery via its own `setup.sh`.
- **Spec artifact: `pipeline-wiki-integration`** — full `/spec → /spec-review (2 rounds) → /plan → /check` cycle committed at `docs/specs/pipeline-wiki-integration/`. Documents the integration strategy end-to-end. The planning cycle made a substantive correction during `/plan`: the v1.0 spec's "force-feed source paths into `wiki-update`" mechanism was based on a false assumption about the skill's contract; reading the actual `SKILL.md` revealed `wiki-update` scans cwd + git-delta, not explicit paths. v1.1 redesigned the write-side around host-agent conversational-context steering instead. See `review.md` round 2 for the FAIL → PASS-WITH-NOTES trajectory.
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

- **Obsidian-wiki integration write side (`/wrap` Phase 2c)** — **planned for the next release.** Adds an auto-evaluated 4-trigger (Karpathy) findings block + free-text comment + `sync/skip` gate when `/wrap` detects session-touched `docs/specs/` files and `~/.obsidian-wiki/config` is present. Also reframes `/wrap`'s header from "be fast — user is leaving" to "compile knowledge for future sessions." Gated behind a read-side dogfood cycle per `docs/specs/pipeline-wiki-integration/plan.md` Decision #6 — write-side ships only after the read-side callout has been validated against real vault content in use.

### Notes

- **Symlink-based install:** `claude-workflow/install.sh` creates symlinks from `~/.claude/commands/*.md` → this repo's `commands/*.md`. Edits here propagate to the live commands **immediately after `git pull`** — no re-install required. First-time installs over a pre-existing real file auto-backup to `<name>.bak`. Means you can `git pull` this release and `/spec` Phase 0.2 activates on your next `/spec` invocation.
- **Obsidian-wiki is optional infrastructure.** If `~/.obsidian-wiki/config` is absent, Phase 0.2 is a silent no-op — zero behavior change for `/spec` users who haven't set up obsidian-wiki. Install via the upstream repo's `setup.sh` (see [github.com/Ar9av/obsidian-wiki](https://github.com/Ar9av/obsidian-wiki)).
