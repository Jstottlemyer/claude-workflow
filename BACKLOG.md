# MonsterFlow Backlog

Ideas not yet scheduled. Newest at the top. Each item: one-liner, **Why:**, **Size:** (S / M / L), and any concrete entry point.

Move an item to a `docs/specs/<feature>/spec.md` (via `/spec`) when you're ready to work on it; delete from here once it lands.

---

## Token economics (cross-cutting)

- **Holistic token-cost instrumentation + value-vs-benefit judging** — measure where MonsterFlow's token budget actually goes (per-gate agent fan-out, per-session plugin injection, per-command persona reads, per-/wrap insights), then make scope-trimming decisions on data instead of guesses. Surface results in the Judge dashboard so the cost-vs-finding-yield of each persona/plugin is visible over time.
  - **Why:** External user feedback (forwarded 2026-05-03) — friend on Claude $20 Pro plan ran two prompts in MonsterFlow and went from 3% → 60% of the rate-limit budget. Their own Claude session diagnosed the superpowers plugin as the main consumer ("injects all those skill descriptions on every message") and offered to disable superpowers + vercel + codex from `enabledPlugins`. So: (a) the cost is real and measurable, (b) the heaviest tax may be plugin auto-injection, not agent fan-out, (c) we currently have no way to *prove* which lever matters most. Without instrumentation we'll keep guessing wrong.
  - **What to investigate:**
    - Per-message system-prompt size by enabled plugin (superpowers, vercel, codex, context7, etc.) — measure once, compare against value each delivers in the pipeline.
    - Per-gate agent-fan-out cost (6 reviewers × full spec read) vs. finding-yield from `findings.jsonl`.
    - Per-/wrap insights cost vs. signal value.
    - Cost-of-Codex-adversarial vs. unique findings it surfaces (already partially measurable from `codex-adversary.md` files).
  - **Already taken (free wins, no data needed):**
    - **2026-05-03:** Disabled `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` in `~/.claude/settings.local.json` (renamed to `_DISABLED_…` with inline `_NOTE_AGENT_TEAMS` explaining why). The flag spawns full independent CC instances per teammate ("token-intensive" per official docs) and our pipeline uses zero peer-messaging / shared-task-list / TeammateIdle hooks. Pure cost, no benefit.
  - **Possible levers (in order of likely impact, to be confirmed by data):**
    1. Slim or scope-narrow `enabledPlugins` for pipeline use — superpowers might be turn-able-off outside the execution-discipline phase of `/build`.
    2. Reduced persona roster on Pro accounts (overlaps with the agent-scaling item below — likely solved together).
    3. Skip `/insights` on Pro by default (already opt-in via `/wrap-insights`).
    4. Lazy-load personas — only read the persona md inside the agent that runs it, not in the orchestrator.
  - **Where the metric lives:** extend Judge dashboard with a "Token economics" tab (per gate: prompt tokens in, completion tokens out, findings emitted, cost-per-finding). Same `dashboard-append.sh` plumbing.
  - **Tightly related to:** "Account-type agent scaling" below — the data this produces tells us the right Pro roster size, so investigate first.
  - **Entry points:** `dashboard/`, `scripts/judge-dashboard-bundle.py` (extend run.json read to pull token counts if Anthropic SDK exposes them), `commands/wrap.md` (Phase 1 already records cost via `session-cost.py` — extend), `settings/settings.json` `enabledPlugins`.
  - **Size:** M–L (instrumentation + dashboard tab + decision framework).

## Onboarding

- **Opinionated, idempotent install.sh that leaves the user able to actually use MonsterFlow** — current `install.sh` is a *checker* (lists what's missing, asks "Continue anyway?", then symlinks files). It does not install anything. New adopters end up with a working symlink graph but no `gh`, no `shellcheck`, no `jq`, no PATH entry, no clue what to run next. Pivot to: detect → install (idempotent) → verify → onboard.
  - **Why:** the friction between "ran install.sh" and "actually used the pipeline" is the dominant adopter drop-off. Tools listed under RECOMMENDED degrade silently — the user doesn't know they're degraded until something doesn't work. We want the post-install state to be *demonstrably working*, with the user knowing the next three commands to type.
  - **Auto-install REQUIRED + RECOMMENDED, idempotently:**
    - For each missing tool, check `brew list <tool> >/dev/null 2>&1` first; install only if absent. Same shape as the existing `has_cmd` check, just one layer down.
    - Brew bundle approach: write a `Brewfile` and run `brew bundle --file=$REPO_DIR/Brewfile` — brew handles idempotency natively and the file is the manifest.
    - Skip auto-install if `--no-install` flag passed (CI / restricted environments).
    - Don't auto-install OPTIONAL (codex) — keep it user-driven.
  - **Auto-detect pip vs pip3:** add a `python_pip()` helper that prefers `pip3`, falls back to `pip`, errors with a clear "neither found, brew install python" if both absent. Use it everywhere (currently `bootstrap-graphify.sh` and venv-installs hardcode `pip3`, but that's per global CLAUDE.md preference — verify across all scripts). Mirrors the `has_cmd` helper pattern already in install.sh.
  - **Onboarding flow at end of install.sh:**
    - Run `scripts/doctor.sh` to verify everything is wired (already exists, just call it).
    - Print a "what to do next" panel: 3-5 numbered commands the user can copy-paste to do their first run, e.g. `1. cd into a project   2. /flow to see the workflow card   3. /spec to start your first feature   4. open ~/Projects/MonsterFlow/dashboard/index.html`.
    - Optionally offer to run `bootstrap-graphify.sh` against `~/Projects/` (with confirmation prompt) so the dashboard has data on first open.
    - Offer to run `gh auth login` if `gh` is installed but not authenticated (`gh auth status` check).
    - Surface the codex opt-in as a single line: "Want adversarial review? Run `/codex:setup` after install."
  - **Idempotency hard rules** (keep this list as the test plan when implementing):
    - Running install.sh twice in a row produces the same output, no errors, no duplicate symlinks, no duplicated PATH lines in `.zshrc`.
    - Running on a fully-installed system: prints "everything already in place" and exits 0 in <2s.
    - Running on a fresh macOS: installs git/python/gh/shellcheck/jq/tmux via brew, links files, runs doctor, prints onboarding panel.
    - Re-running after a `brew uninstall jq`: detects, re-installs, doesn't touch unrelated state.
  - **Out of scope for v1:** Linux support (the `brew` assumption is macOS-only; Linux can wait until there's a real Linux adopter).
  - **Entry points:** `install.sh` (rewrite the prereq + install section), new `Brewfile`, possibly new `scripts/onboard.sh` for the post-install panel, `scripts/doctor.sh` (already exists).
  - **Size:** M (mostly mechanical, but the idempotency test plan is the real work — needs a clean-VM smoke test or a shell test harness).
  - **Testing requirement:** must add a `tests/test-install.sh` that runs the four idempotency cases above against a temp $HOME so we don't regress.

## Pipeline

- **Account-type agent scaling** — auto-detect the active Claude account tier (Pro vs Max vs API) and scale agents-per-gate accordingly. Max/API can run the full 6+6+5 roster; Pro hits rate limits faster and should use a reduced roster (e.g. 3+3+3).
  - **Why:** Pro accounts hit rate limits mid-gate and the run aborts, leaving partial artifacts. A budget-aware roster keeps the pipeline usable on Pro without forcing every adopter onto Max.
  - **External signal:** Pro user forwarded feedback 2026-05-03 — two prompts moved their rate-limit budget 3% → 60% in MonsterFlow flows. Their own Claude session pinpointed the superpowers plugin's per-message skill-description injection as the main consumer (see token-economics item above). Confirms Pro is the constrained tier worth designing for.
  - **Detection signal:** check `claude config` or env for account type, or expose a `PIPELINE_AGENT_BUDGET` override.
  - **Entry points:** `commands/spec-review.md`, `commands/plan.md`, `commands/check.md` (the persona-list section in each).
  - **Size:** S–M (mostly slicing the persona list + reading one env var).
  - **Sequencing note:** wait on the token-economics investigation above before picking the Pro roster size — measure first, then trim.

## Future architecture (research-grade, not near-term)

- **Inter-agent debate via Claude Code Agent Teams** — investigate whether the Judge stage produces meaningfully better findings if reviewer personas can message each other directly during a gate (e.g., scope-discipline challenges completeness in real time, two personas converge on a merge before reaching the orchestrator) instead of all reconciliation happening post-hoc in Judge + Synthesis.
  - **Why:** Today every reviewer is a one-shot return to the orchestrator; Judge does dedup/contradiction-resolution after the fact, often with less context than the original reviewer had. Real peer messaging could surface stronger merges and stronger disagreements with audit trails.
  - **Mechanism:** `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (CC ≥ v2.1.32, currently research preview) enables peer messaging by name, shared task list, and `TeammateIdle` / `TaskCreated` / `TaskCompleted` hooks. Each teammate is a full independent CC session — own context, own CLAUDE.md, own MCP/skills. Token cost scales linearly with team size.
  - **Disabled today:** the flag was on without us using any of its primitives, pure cost-no-benefit (see token-economics "Already taken" note). Stays off until/unless this experiment is approved.
  - **What to test:** A/B a single `/spec-review` gate with team-mode peer messaging vs. the current orchestrator-mediated flow. Measure: (a) finding quality (does Judge have less work to do?), (b) token cost delta, (c) wall-clock time, (d) whether `Agent Disagreements Resolved` becomes richer.
  - **Entry points:** `commands/spec-review.md` (Phase 1 dispatch section), `personas/judge.md`, `personas/synthesis.md`. Would need a separate `commands/spec-review-team.md` variant to A/B against, not a destructive rewrite.
  - **Sequencing:** *do not start* until token-economics + account-scaling items above are done. This adds cost; we need the budget framework in place first.
  - **Size:** L (research project, not a feature ship).
