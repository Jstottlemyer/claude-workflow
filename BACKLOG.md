# MonsterFlow Backlog

Ideas not yet scheduled. Newest at the top. Each item: one-liner, **Why:**, **Size:** (S / M / L), and any concrete entry point.

Move an item to a `docs/specs/<feature>/spec.md` (via `/spec`) when you're ready to work on it; delete from here once it lands.

> **2026-05-04:** install.sh rewrite shipped (v0.5.0) — see CHANGELOG.md.

---

## Pipeline + install discipline (from 2026-05-05 autorun-overnight-policy session)

- **`pipeline-gate-rightsizing` (NEW spec candidate — sibling to permissiveness)** — match gate weight to work class. `/spec` already picks bug-fix / small-change / feature / V2 at Phase 2; downstream gates don't honor that. A 3-line bug fix should not dispatch 6 PRD reviewers + 7 designers + 5 validators (28+ persona invocations). **Six levers in scope:**
  1. **Work-class → gate-intensity mapping.** Bug-fix: skip /spec-review + /plan + /check (go straight to /build). Small-change: 2-reviewer /spec-review, no /plan, 2-validator /check. Feature: full default roster. V2: full + Codex mandatory.
  2. **Which agents per gate per work-class** (not just count — selection). The persona roster has different fitness-for-purpose:
     - Security-flavored work → security-architect + Codex must run; ux/ambiguity/stakeholders skippable
     - UX-polish small change → ux + ambiguity sufficient; security-architect + Codex skippable
     - Architectural feature → completeness + sequencing + scope-discipline + Codex; specialists optional
     - Bug fix → none, OR just one targeted reviewer matching the bug class

     This subsumes part of `account-type-agent-scaling`'s resolver (which today is budget-driven only) — work-class becomes a second resolver input alongside `agent_budget`.
  3. **Codex inclusion per gate is a first-class decision, not "always-on if installed."** Codex is high-cost, high-signal — should run on architectural specs, security work, V2 revisions; should NOT run on docs-only or trivial work. The 4-iteration autorun-overnight-policy session was Codex-load-bearing (caught H2 nonce trust-boundary failure). Future architectural specs (autorun-verdict-deterministic XL, this rightsizing spec L) should mandate Codex; install-sh-backup-uninstall (M, mostly plumbing) does not need it.
  4. **Per-gate skip rules** declared at spec.md frontmatter; honored by gate scripts.
  5. **Adaptive iteration cap by domain.** Hard cap at 2 (from permissiveness) too rigid for security; too loose for typo fixes. Cap of `min(work_class_max, persona_budget_max, 5)`.
  6. **Cost-aware self-skip.** Gates know their token cost (per `holistic-token-cost-instrumentation` instrumentation); a small change shouldn't burn $20 in /check synthesis.
  - **Why:** the autorun-overnight-policy session ran the FULL pipeline 4× over 2 days for what was ultimately ~2,300 LoC of policy framework. About half of the gate cycles were structurally wasted because the work didn't need that much review. ^[inferred] Combined with `pipeline-gate-permissiveness`, rightsizing closes the "stop overweight gating" problem from the other direction (don't over-dispatch in the first place; don't over-halt on what was dispatched).
  - **Entry points:** `commands/{spec,spec-review,check,plan,build}.md` (work-class read + gate-skip honors); spec.md frontmatter schema (`work_class:` field); resolver integration (work-class as another input alongside `agent_budget`); test fixtures for each work-class flow.
  - **Sequencing:** start AFTER `pipeline-gate-permissiveness` lands (rightsizing decides _whether_ to dispatch; permissiveness decides _what to do with findings_ — permissiveness is the unblocked half). Or run them in parallel if the spec authors are different agents.
  - **Size:** L (similar shape to permissiveness; touches same command skills + adds frontmatter schema + resolver integration).
  - See memory `feedback_pipeline_gate_permissiveness.md` (overlapping rationale; rightsizing is the dispatch-side of the same overweight-gating problem).

- **`pipeline-gate-permissiveness` (NEW spec candidate)** — apply autorun's per-axis warn/block policy framework to /spec-review, /check, /plan, /build gates. Default to GO_WITH_FIXES + apply-inline for documentation/contract/test findings; only architectural/security/integrity findings should re-cycle the user. Cap re-cycles at 2-3. Surface routing decision in verdict block. Same `--mode=permissive|strict` CLI preset shape as autorun.
  - **Why:** autorun-overnight-policy ran 4 /check iterations (v1-v3 NO-GO, v4 GO_WITH_FIXES). Iteration 4's two MFs were both documentation/framing — could have been routed as warns from v3 → 1 fewer iteration → 1 fewer "fix now / defer / hold" prompt. The 17 SFs across 4 iterations were almost all build-time items. Halt-on-anything bombards the user with re-cycle questions.
  - **Entry points:** `commands/{spec-review,check,plan,build}.md` (verdict logic + routing); `personas/{review,check}/judge.md` + synthesis (classification: architectural / contract / docs / tests / scope / polish); new schema for finding `class` field; possibly a `PIPELINE_DEGRADED` sticky bit promoted from autorun's `RUN_DEGRADED`.
  - **Sequencing:** can start any time; benefits from the autorun-overnight-policy infrastructure landing first (PR #6) so the structural pattern is in code to reference. Pairs naturally with `autorun-verdict-deterministic` (also from this session) — they're sibling concerns about what synthesis output is trustworthy and what gates should halt on.
  - **Size:** L (touches 4 command skills + persona docs + finding schema + tests; conceptually similar to autorun-overnight-policy's per-axis framework).
  - **Codex review mandatory at /check.** This spec defines what halts the user vs what becomes a build-time follow-up — wrong call here cascades to every future pipeline run. Adversarial review needed.
  - See memory `feedback_pipeline_gate_permissiveness.md` for the design rationale and concrete evidence from this session.

- **`install-sh-backup-uninstall` (NEW spec candidate)** — install.sh currently modifies adopter defaults (CLAUDE.md, .claude/settings.json, .claude/agents/, commands/, hooks, doctor.sh, queue scaffolding) without backups or a revert path. Add (a) pre-flight banner with explicit consent gate explaining we're making opinionated changes, (b) backup every modified file to `.monsterflow-backups/<timestamp>/manifest.json` BEFORE modification, (c) ship `scripts/uninstall.sh` that reads the manifest and reverts (idempotent; supports `--restore-from <timestamp>`), (d) document revert path in README + CHANGELOG as a trust signal.
  - **Why:** adopters who try MonsterFlow and decide it's not for them are stuck cleaning up by hand. Reversibility is a trust signal. The pipeline + agents + hooks are *opinionated* defaults — without explicit messaging adopters may not realize how much we're stamping on their existing config.
  - **Entry points:** `install.sh` (banner + backup machinery); new `scripts/uninstall.sh`; `README.md` + `CHANGELOG.md` updates; smoke test `tests/test-install-uninstall-roundtrip.sh`.
  - **Sequencing:** independent of other backlog items. Can start any time.
  - **Size:** M (mostly file enumeration + JSON manifest + reverter; ~200-400 LoC + tests).
  - **Codex review optional** — mostly plumbing (file enumeration + JSON manifest + reverter). Standard /check roster is sufficient; Codex would be belt-and-suspenders on a low-architectural-risk spec.
  - See memory `project_install_sh_backup_uninstall.md` for the file-surface enumeration and design notes.

---

## Autorun follow-ups (deferred from autorun-overnight-policy v4-v5)

- **`autorun-verdict-deterministic` (NEW spec, follow-up to autorun-overnight-policy v6)** — replace synthesis-emits-sidecar pattern with deterministic verdict aggregation from structured reviewer outputs. Closes the v2-MF6 residual class (single-fence prompt-injection: synthesis omits its own fence; reviewed content quotes a single fake; count==1 forged GO ships) that v6 documents as known v1 limitation.
  - **Why:** check v3 Codex H2 demonstrated that any model-echoed secret (the v4 nonce attempt) is not a trust boundary against adaptive prompt injection. The architectural answer is to remove the LLM from the verdict-emission path: each reviewer persona emits structured `sev:security` and verdict tags in raw output; `check.sh` aggregates `check-verdict.json` deterministically (any reviewer NO_GO → NO_GO; any sev:security → security_findings populated; else GO_WITH_FIXES if any FAIL else GO). Synthesis call writes prose only.
  - **Acceptance bullets** (per check v4 Codex M2 — sizing-driven):
    - New reviewer-output schema (e.g., `schemas/reviewer-output.schema.json`) — current `check-verdict.schema.json` cannot be reused as the trust boundary (Codex M3); persona outputs need their own structured contract.
    - Deterministic aggregation precedence pinned: any `verdict: NO_GO` → NO_GO; any `sev:security` tag → security_findings populated (hardcoded block); else `GO_WITH_FIXES` if any FAIL; else GO. Order independent across reviewers.
    - Migration from existing `check-verdict` fences: one-release back-compat with explicit deprecation; `extract-fence` retained for legacy synthesis outputs but post-processor prefers reviewer-aggregated path.
    - Adversarial single-fence fixture (deterministic equivalent of v1 fixture (e)): asserts that even a perfectly-crafted forged `check-verdict` fence in reviewer output cannot bypass aggregation, because the aggregator does not consume synthesis JSON.
    - Manual `/check` behavior: synthesis writes prose only; aggregator runs over reviewer raws (works for both autorun and manual /check; collapses the v1 mode-fork concern).
  - **Sequencing:** *do not start* until autorun-overnight-policy v6 ships. This spec inherits its `_policy_json.py` + `_policy.sh` infrastructure.
  - **Entry points:** `commands/check.md` synthesis section (rewrite to "prose only"); `personas/check/*.md` (each persona output structured-emission schema); `scripts/autorun/check.sh` (aggregator); `schemas/reviewer-output.schema.json` (NEW); `schemas/check-verdict.schema.json` (becomes aggregator-output, not synthesis-output).
  - **Size:** **XL** (changes the trust model + reviewer output contract + synthesis role + aggregation rules + schema semantics + tests + migration/back-compat + manual `/check` behavior — substantially more than a local refactor).
  - **Codex review mandatory at /spec-review and /check.** This spec replaces a security mechanism (the v4 nonce) that Codex H2 already proved unsound — same caliber of adversarial review must validate the deterministic-aggregation design before code lands.

- **Stage-boundary STOP-check inside `run.sh`** — current `autorun-batch.sh` honors STOP only at iteration boundaries (an in-flight `run.sh` finishes its slug after STOP is touched). Adding a STOP-check inside `run.sh` between stages would cut overnight halt latency from "next slug" to "next stage."
  - **Why:** R15 documented at autorun-overnight-policy/plan.md v4 — iteration-boundary semantics are correct but coarse. Adopters expecting STOP to halt mid-slug will be surprised.
  - **Entry points:** `scripts/autorun/run.sh` `update_stage()` function; add `[[ -e queue/STOP ]]` check after each stage transition.
  - **Size:** S.

- **Promote `tests/test-policy-json.sh` to its own file** — currently 5.2's `_policy_json.py` audit + extract-fence + validator tests live in `test-autorun-policy.sh`. Splitting isolates Python failures from shell failures.
  - **Why:** Codex /check v2 SF — keeping Python CLI/schema/fence tests inside the shell policy suite slows debugging when one breaks.
  - **Size:** S (mostly file split + run-tests.sh wiring).

---

## Token economics (cross-cutting)

> **2026-05-04:** Per-persona instrumentation (cost + survival + uniqueness as separate columns) promoted to `docs/specs/token-economics/spec.md` (instrumentation-only after `/spec-review` round 1 narrowed scope). Per-plugin cost measurement and roster-scaling action stay here, both depending on the instrumentation spec landing first. Items #4 (Agent Teams) and #2 (Onboarding) remain unscheduled.

- **Per-plugin cost measurement** — extend `scripts/session-cost.py` (or sister script) to attribute token spend by enabled plugin (superpowers, vercel, codex, context7, etc.). Required before "plugin scoping per gate" below has any data to act on.
  - **Why:** External user feedback (2026-05-03) hypothesized superpowers' per-message skill-description injection is the dominant cost; instrumentation spec round-1 review verified there is no per-plugin marker in session JSONL and `attributionSkill` is per-message, not per-plugin. Methodology is genuinely undecided — needs design (baseline-vs-installed diffing? a logging shim around plugin loads? something else?).
  - **Sequencing:** *do not start* until `token-economics/spec.md` Phase 0 spike completes — that spike answers whether MonsterFlow has per-subagent JSONL access at all, which is a precondition.
  - **Entry points:** `scripts/session-cost.py`, `dashboard/data/plugin-costs.jsonl` (proposed sister artifact, not mixed with `persona-rankings.jsonl`).
  - **Size:** M (methodology design dominates; instrumentation itself is small once the signal source is identified).

- **Plugin scoping per gate (action half — depends on per-plugin cost measurement)** — once per-plugin cost data exists, decide which plugins to scope out of which gates (e.g., disable superpowers SessionStart skill for non-`/build` subagents). Pure cost-vs-value action that the data unlocks.
  - **Why:** Friend on Pro plan diagnosed superpowers as the main rate-limit consumer; if data confirms, scoping superpowers to `/build`-time only would directly reduce Pro-tier spend. Per global CLAUDE.md, superpowers is already supposed to be `/build`-only; the harness doesn't currently enforce that per-gate.
  - **Sequencing:** *do not start* until per-plugin cost measurement above has shipped ≥10 runs of data.
  - **Entry points:** `settings/settings.json` `enabledPlugins`, possibly per-gate plugin overrides if Claude Code supports them (verify), `commands/{spec-review,plan,check}.md` if scoping is dispatch-time.
  - **Size:** S–M (small if `enabledPlugins` is gate-scopable; medium if we have to wrap dispatch).

- **Holistic token-cost instrumentation + value-vs-benefit judging** *(partially promoted → docs/specs/token-economics/spec.md — per-persona dimension only; per-plugin and per-/wrap dimensions remain here)* — measure where MonsterFlow's token budget actually goes, then make scope-trimming decisions on data instead of guesses. Per-persona half is now a real spec; per-plugin and per-`/wrap insights` cost dimensions still need their own specs (above and below).
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

## Pipeline

- **Account-type agent scaling** *(deferred — depends on token-economics/spec.md instrumentation landing first; combined-spec attempt rolled back 2026-05-04 after `/spec-review` round 1 found 7 blockers)* — auto-detect the active Claude account tier (Pro vs Max vs API) and scale agents-per-gate accordingly. Max/API can run the full 6+6+5 roster; Pro hits rate limits faster and should use a reduced roster (e.g. 3+3+3). The `/spec-review` round-1 findings (`docs/specs/token-economics/spec-review/findings.jsonl`) inform this spec when it gets written: (a) tier-detection cascade must be designed against verified CLI surface, not guesses; (b) the resolver should ship in report-only mode first per Codex's recommendation; (c) summary↔ceiling defaults must be reconciled (Max≠full if ceiling<roster size); (d) value formula must include severity weighting and a divisor floor; (e) deterministic tie-break required.
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
  - **Prior research (2026-05-05):** docs reread + reframe captured. Memory: `project_agent_teams_refit.md` (debate-not-fan-out framing, 3 concrete fits: adversarial /check, personas-as-subagent-defs, hook-enforced invariants). Wiki: `_raw/2026-05-05-1037-agent-teams-refit-monsterflow.md` (general Claude Code primitives, splits at ingest). Read these before opening a `/spec` so we don't restart from a blank page.
