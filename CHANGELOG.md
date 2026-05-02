# Changelog

All notable changes to `MonsterFlow` are documented here.

## [0.2.0] — Persona Metrics measurement layer

### Added

- **Persona Metrics measurement layer** — every multi-agent gate (`/spec-review`, `/plan`, `/check`) now emits structured artifacts that record which personas raised which findings, whether those findings were unique or shared, and whether they survived revision (or made it through synthesis at `/plan`). Surfaced in `/wrap-insights` as a Persona Drift section showing per-persona `load_bearing_rate`, `survival_rate`, and `silent_rate` across a rolling 10-feature window. The pipeline becomes a measurement loop — *the optimization loop (tiering rules, probe sampling, conditional invocation) lands in the follow-up `persona-tiering` spec.*
  - **Six new artifact types per feature per stage:** `source.<artifact>.md` (pre-review snapshot), `raw/<persona>.md` (per-persona raw output, persisted to disk to retire harness-context-access risk), `findings.jsonl` (clustered, attributed), `participation.jsonl` (every persona that ran, with status), `run.json` (manifest with `run_id`, `prompt_version`, hashes), `survival.jsonl` (next-stage classification).
  - **Three new prompt files** under `commands/_prompts/`: `snapshot.md`, `findings-emit.md`, `survival-classifier.md` (the classifier supports two outcome-semantics modes — addressed-by-revision at `/plan` and `/build`, synthesis-inclusion at `/check`).
  - **Four JSON Schema files** under `schemas/` (draft 2020-12) — machine-checkable contracts referenced by the prompt files.
  - **`/wrap-insights` Phase 1c (Persona Drift)** — diff render against the prior 10-feature window with `↑/↓/→` arrows (5pp deadband). Bare-arg `/wrap-insights personas` renders the full table with `load_bearing_rate` and `survival_rate` side-by-side.
  - **`PERSONA_METRICS_GITIGNORE=1` env var** — adopter-install default flips to opt-in-to-commit (gitignored by default in adopter projects; `MonsterFlow`'s own repo overrides via name-detection in `install.sh`). Protects against accidental commits of verbatim review prose to public repos.
  - **`finding_id` derived from `normalized_signature`** — sha256 of NFC-normalized, lowercased, whitespace-collapsed, sorted source persona-output substrings. Best-effort stable across LLM re-syntheses given identical raw inputs; canonicalization function is deterministic and fixture-tested by `scripts/doctor.sh`.
  - **README and `docs/index.html` mermaid diagrams** updated with the new `Judge · Dedupe · Synth` interstitials between gates and the `Persona Metrics` side observer; all three Judges feed the metrics layer (Tight-C visual recipe).
  - **Spec artifacts:** `docs/specs/persona-metrics/{spec,review,plan,check,diagrams}.md` document the full pipeline cycle. Scope (b) was adopted post-checkpoint via diagram review feedback — `/plan`'s synthesis-inclusion semantics is the new structural piece.

## [Unreleased]

### Added

- **Automation infrastructure: hooks, subagents, skills, test suite** (2026-05-01):
  - **PostToolUse hooks** (`scripts/post-edit-shellcheck.sh`, `scripts/post-edit-json-validate.sh`) wired into `settings/settings.json`. Advisory-only — emit `systemMessage` on findings, never block edits. Catch the PIPESTATUS / quoting / JSON syntax bugs that the recent autorun reviews surfaced *before* commit time.
  - **Subagents** at `.claude/agents/`:
    - `autorun-shell-reviewer` — codifies the 13-pitfall checklist for `scripts/autorun/*.sh` (PIPESTATUS index, `\|\| true` reset, `grep -c` arithmetic, branch invariant, STOP race, slug regex, eval scope, SSH/HTTPS remote, AppleScript injection, `--auto` merge ambiguity, empty-PR loophole, truncated diff, quoting). Returns High/Medium/Low findings with file:line.
    - `persona-metrics-validator` — validates JSONL schema + foreign-key joins + `artifact_hash` freshness across `docs/specs/*/{spec-review,plan,check}/`.
  - **User-only skills** at `.claude/skills/` (both `disable-model-invocation: true` since they have side effects):
    - `autorun-dryrun` — runs the full autorun pipeline in `AUTORUN_DRY_RUN=1` against an isolated tmp git repo with a fixture spec, asserts every artifact lands.
    - `bump-version` — semver bump `VERSION` + commit + annotated tag with dirty-tree / branch / pre-existing-tag pre-conditions and `--dry-run` support.
  - **Test suite** at `tests/` — 5 files, 30+ assertions, all green:
    - `run-tests.sh` (CI runner), `test-hooks.sh`, `test-agents.sh`, `test-skills.sh`, `test-bump-version.sh` (12 assertions), `autorun-dryrun.sh` (full pipeline smoke test).
    - Fixture: `tests/fixtures/autorun-dryrun/sample.spec.md`.
  - **`build.sh` dry-run completeness fix** — stub now writes `pre-build-sha.txt` and invokes `verify.sh` (which has its own dry-run stub) so the full artifact graph lands. Caught by the `autorun-dryrun` test — previously dry-run was a partial simulation.

- **Autorun pipeline correctness — 31 fixes across 3 review rounds** (Sonnet/Opus/Codex, 2026-05-01):
  - **Post-build spec compliance verifier** (`scripts/autorun/verify.sh`) — runs inside the build retry loop after tests pass, checks the cumulative git diff against spec requirements via a second `claude -p` call, injects unmet requirements (`[FAIL]` lines) as explicit context into the next attempt's prompt. Closes the false-done loophole where "routes load + tests pass" was treated as compliance for requirements specifying UI elements / access gates / data fields.
  - **`PIPESTATUS` correctness** — `build.sh:157` now reads `${PIPESTATUS[1]}` (claude) instead of `${PIPESTATUS[0]}` (printf, always 0); `verify.sh` captures inside the `\|\| VAR=...` branch instead of the broken `\|\| true; VAR=${PIPESTATUS[1]}` cross-statement pattern.
  - **`grep -c \|\| echo 0`** replaced with `\|\| true` + `${VAR:-0}` everywhere — prevents "integer expression expected" pipeline aborts when grep finds zero matches.
  - **Branch invariant** — `verify.sh` now fails compliance if `HEAD` is not on `autorun/$SLUG` (catches agents that checked out a different branch).
  - **STOP file race** — `build.sh` re-checks `queue/STOP` after each successful wave; `run.sh` re-checks before PR creation.
  - **Empty-PR loophole** — `verify.sh` now writes `VERDICT: INCOMPLETE` and exits 1 when no commits exist since pre-build SHA, instead of silently exiting 0.
  - **`install.sh` adopter detection** — owner-vs-adopter discriminator changed from `basename "$REPO_DIR"` to `$PWD == $REPO_DIR`. Adopter projects now correctly receive `queue/.gitignore` (previously written only inside the engine repo); persona-metrics gitignore default-flip is robust to clones named "MonsterFlow".
  - **`gh pr merge --auto` state query** — exit 0 means auto-merge *enabled*, not *merged*; `run.sh` now queries `gh pr view --json state` and logs `merge-auto-enabled` if not yet `MERGED`.
  - **SSH remote handling in `gh pr create --repo`** — uses `gh repo view --json nameWithOwner` first, with regex fallback handling both HTTPS and SSH (`git@github.com:owner/repo.git`) URL forms.
  - **AppleScript injection** in `notify.sh` — escapes backslashes and double-quotes before passing the body to `osascript`.
  - **`test_cmd` scope** — `build.sh` and `run.sh` now run `test_cmd` inside `(cd "$PROJECT_DIR" && eval ...)` so adopter tests don't accidentally execute against the engine repo.
  - **Slug regex enforcement** — `run.sh` validates the documented `^[a-z0-9][a-z0-9-]{0,63}$` regex before processing each queue item.
  - **`spec-review` artifact requirement** — `run.sh` treats a missing `review-findings.md` as a failure (was silently allowing risk-analysis to append to a never-created file).
  - **PR-creation failure** now writes `failure.md` (was leaving items in limbo with neither `failure.md` nor `run-summary.md`, causing infinite re-runs).
  - **Stale main fetch** — `run.sh` does `git fetch origin main` and bases the autorun branch on `origin/main` so overnight runs start from a current base.
  - **Codex review context** — both initial and fix-attempt Codex reviews receive the actual `git diff` plus build-log tail (was only the build-log narration, same class of false-done as the original bug).
  - **Webhook JSON escaping** — `notify.sh` uses `python3 json.dumps` for the Slack-compatible payload (was hand-rolled escaping that mangled multi-line content with quotes).
  - **Diff truncation signal** — verifier prompt now warns when the 3000-line cap was hit, so requirements implemented past line 3000 are marked `[FAIL]` rather than silently `[PASS]`.

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

- **`/autorun` cross-project support** — the `autorun` CLI and all stage scripts (`run.sh`, `build.sh`, `spec-review.sh`, `plan.sh`, `check.sh`, `risk-analysis.sh`) now cleanly separate `ENGINE_DIR` (where scripts live, always `MonsterFlow`) from `PROJECT_DIR` (the target repo, defaults to `$PWD`). Previously all paths used a single `REPO_DIR` that pointed to `MonsterFlow`, so running `/autorun` from any other project silently operated on the wrong directory. Stage scripts fall back to `REPO_DIR` when `PROJECT_DIR` is unset, so existing single-repo setups are unaffected.
- **`autorun` not on PATH** — `install.sh` now symlinks `scripts/autorun/autorun` → `~/.local/bin/autorun`. Previously the binary was never added to `PATH`, so `autorun start` produced "command not found" outside the repo directory.
- **`autorun` symlink resolution on macOS** — `dirname "$0"` on a symlinked binary resolves to the symlink's directory, not the script's real location. The wrapper now uses a `while [ -L ]` loop (macOS-safe; `readlink -f` is unavailable on stock macOS) to find `ENGINE_DIR` before any path calculation.
- **`/autorun` in-session simulation** — `commands/autorun.md` lacked an explicit action instruction; Claude read the pipeline documentation and attempted to orchestrate each stage interactively. Added an `## Action` block at the top of the command that explicitly delegates to `autorun start` and prohibits in-session simulation.
- **`index.md` PR column placeholder** — `run.sh` was writing `(see 10b)` (a leftover development note) instead of the actual PR URL in the queue summary table. Fixed to read `pr-url.txt`.
- **Namespace collision** between user `/brainstorm` and `superpowers:brainstorm` — resolved by rename.

### Security

- None.

### Known Limitations / Planned for v1.1

- **Approach-proposal trigger heuristic** — during the first smoke-test run (ModelTraining `workflow-map` spec, 2026-04-12), the Phase 2 approach-proposal step **did not fire as a distinct phase** because the feature's structural questions (artifact format, content scope) implicitly carried approach-choice. Need a clearer trigger rule for when the dedicated 2-3-approach proposal runs vs. when structural Qs naturally subsume it. Lean: trigger explicitly when the feature has an architecture / design dimension (e.g., a new service, a new data flow); skip when the feature is essentially "configure X to have shape Y" and structural Qs are the design.

- **Obsidian-wiki integration write side (`/wrap` Phase 2c)** — **planned for the next release.** Adds an auto-evaluated 4-trigger (Karpathy) findings block + free-text comment + `sync/skip` gate when `/wrap` detects session-touched `docs/specs/` files and `~/.obsidian-wiki/config` is present. Also reframes `/wrap`'s header from "be fast — user is leaving" to "compile knowledge for future sessions." Gated behind a read-side dogfood cycle per `docs/specs/pipeline-wiki-integration/plan.md` Decision #6 — write-side ships only after the read-side callout has been validated against real vault content in use.

### Notes

- **Symlink-based install:** `MonsterFlow/install.sh` creates symlinks from `~/.claude/commands/*.md` → this repo's `commands/*.md`. Edits here propagate to the live commands **immediately after `git pull`** — no re-install required. First-time installs over a pre-existing real file auto-backup to `<name>.bak`. Means you can `git pull` this release and `/spec` Phase 0.2 activates on your next `/spec` invocation.
- **Obsidian-wiki is optional infrastructure.** If `~/.obsidian-wiki/config` is absent, Phase 0.2 is a silent no-op — zero behavior change for `/spec` users who haven't set up obsidian-wiki. Install via the upstream repo's `setup.sh` (see [github.com/Ar9av/obsidian-wiki](https://github.com/Ar9av/obsidian-wiki)).
