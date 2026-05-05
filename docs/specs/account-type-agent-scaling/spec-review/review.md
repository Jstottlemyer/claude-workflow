# Spec Review — account-type-agent-scaling

**Reviewed:** 2026-05-04
**Reviewers:** ambiguity feasibility gaps requirements scope stakeholders

---

## ambiguity

# Ambiguity Review — account-type-agent-scaling

## Critical Gaps

1. **"top-N personas from persona-rankings.jsonl" — selection algorithm undefined.** What field is ranked on? What's the sort order? What does a "qualifying row" mean? The Edge Cases table says "< 1 qualifying row" triggers seed fallback, but "qualifying" is never defined. Two engineers will implement different filters (gate-match only? recency window? minimum sample size? score threshold?).

2. **Pin + ranking + seed merge order is ambiguous at the boundary.** AC #2 says "pins first, then rankings top-N, then seed fill-up to 3." But: if a pin is also in the rankings top-N, is it deduped (it must be, but not stated)? If pins=2 and budget=3, do we pull rankings[0] regardless of whether it's also a pin? What if rankings list a persona that no longer exists on disk? The "Persona in pins no longer exists" row covers pins but not rankings.

3. **"Codex authenticated" check timing and caching unspecified.** `codex login status` is invoked per gate dispatch — is it cached? What's the timeout? If `codex` binary is absent vs. present-but-unauthenticated, both should behave identically (silently omit), but the spec only addresses "not authenticated." Missing-binary is a separate failure mode.

4. **"Full roster" is undefined.** Edge Cases row 1 ("config.json absent → Full roster dispatched") and Acceptance #1 use "full roster" without defining it. Is it the seed list? All personas on disk? The current hardcoded list in each command file? The Data section says "File does not exist → full roster up to 6 (default)" — so default is 6, but the seed lists show 6/8/5 personas per gate. Does "full roster up to 6" mean cap-to-6 or seed[0:6]?

## Important Considerations

5. **"Default: 6" vs "Default: 3 (Pro)" interaction with ceiling.** If user answers "yes Pro" → default 3, but they could enter 8. If "no" → default 6. The Pro question is purely cosmetic for the default — the same 1–8 range applies. Worth stating explicitly that the Pro answer only changes the suggested default, nothing else, or users will assume it gates the ceiling.

6. **"Minimal questions; defer deep tuning to --reconfigure-budget"** — but the install Q&A asks one pin per gate (3 pins). `--reconfigure-budget` re-runs "steps 2–6" which is the same flow. So what's "deep tuning" deferred to? This phrase suggests a richer reconfigure mode that doesn't exist.

7. **AC #7: "none of them silently restore full roster on a budgeted session."** "Disable budget for this run" (option 3) — does that restore full roster or not? If it disables budget, the natural behavior is full roster. The AC seems to forbid the option it just defined. Either option 3 means something else, or the AC needs rewording.

8. **`persona_pins` schema vs. validation.** Spec says "Each list must fit within budget" but pins are per-gate and budget is global. If budget=3 and `plan` has 3 pins but `check` has 5 pins, install.sh rejects — fine. But what if user lowers budget from 5 to 3 later via `--reconfigure-budget` and existing pins are 4? Truncation rule exists at runtime but not at reconfigure time.

9. **"Gate stdout shows selected + dropped personas"** — format is illustrated once (`Selected: ... | Dropped: ...`) but not specified as a contract. Will tests grep for this exact format? If so, lock it.

10. **"Tell Claude to reconfigure" path** — Claude reads config.json and "runs Q&A inline." Whose Q&A? The same prompts as install.sh? Hardcoded where? If the prompts live only in `install.sh`, Claude will paraphrase and drift.

## Observations

11. **"Maximum: 8 (enforced at write time with a warning)"** vs. **"Runtime cap enforced at 8"** — double enforcement is fine, but the warning text "8 is the maximum — using 8" implies a silent cap, not a hard reject. Consistent with intent; just note that this differs from the `≤ 0` rejection (which is a hard error). Asymmetric treatment is reasonable but worth calling out.

12. **`session_roster: defaults-only`** in frontmatter, plus "Roster Changes: No roster changes" at the bottom — redundant but harmless.

13. **Sequencing note** says ranking-based selection requires "≥1 completed run" but the Edge Cases say "< 1 qualifying row" triggers fallback. "Completed run" and "qualifying row" should use the same vocabulary.

14. **Codex additivity at budget=8.** Total dispatched = 9 personas (8 Claude + Codex). Worth confirming this is intentional and doesn't blow past any rate-limit assumption baked into the Pro=3 default.

15. **`docs/budget.md` is required by AC #13** but `QUICKSTART.md` is also updated (Scope). Make sure they don't drift — pick one as canonical and have the other link.

## Verdict

**FAIL** — Critical Gaps 1–4 (ranking selection algorithm, merge dedup order, Codex check semantics, definition of "full roster") will cause divergent implementations and AC interpretation disputes. These are small clarifications, not redesigns; spec can return to PASS with a short revision pass.

---

## feasibility

# Technical Feasibility Review — account-type-agent-scaling

## Critical Gaps

1. **`codex login status` is unverified.** Spec hinges on this exit code as the Codex-additive trigger. Memory has `codex exec review --uncommitted` but no evidence `codex login status` exists or returns 0/non-0 cleanly. If the subcommand is `codex auth status`, `codex whoami`, or doesn't exist, the entire Codex-additive path silently fails (or worse, errors out and trips the recovery prompt every run). **Required:** run `codex --help` / `codex login --help` and quote the actual subcommand before implementation. Per CLAUDE.md "Verify Before Shipping" rule, this is non-negotiable.

2. **"Qualifying row" in persona-rankings.jsonl is undefined.** Edge-case table says "Rankings absent / < 1 qualifying row → seed fallback." But what makes a row qualify? Gate match? Recency window? Min sample count? Without a definition the resolver can't be built, and the seed-vs-rankings boundary is the central decision the script makes.

3. **persona-rankings.jsonl schema is not in this spec.** Spec says "ships after token-economics v1 is live and producing ranking data" — but the resolver script reads that file and the schema is documented nowhere in this spec. If token-economics ships with a schema that doesn't include per-gate keys, ranking-by-gate is impossible. **Required:** either inline the schema contract here or block this spec on token-economics v1 being merged first with documented schema.

4. **Persona name mismatch risk between pin list and disk.** Seed list uses bare names (`requirements`, `risk`, `scope-discipline`) but actual personas live in `personas/<gate>/<name>.md` and the autorun architecture (per CLAUDE.md) does disk-discovery. If a seed name doesn't match the actual filename (e.g., `risk` vs `risk-management.md`), budget=1 dispatches zero personas. **Required:** add an acceptance criterion that every seed-list entry is verified against `personas/<gate>/` at spec-finalization time, or have the resolver glob disk and intersect.

## Important Considerations

5. **Bash 3.2 + JSON parsing.** macOS ships bash 3.2, no native JSON. Resolver must either require `jq` (add to install.sh dependency check) or shell out to `python3` (already a dep per token-economics). Decision should be explicit; ad-hoc `grep '"agent_budget"'` parsing will break on whitespace variants. Memory note on tilde expansion (`${VAR/#\~/$HOME}`) applies to any path read out of config.json.

6. **TTY detection in claude-dispatched shell.** Recovery prompt assumes `[ -t 0 ]` distinguishes interactive from headless. When `claude -p` invokes the gate command, stdin is typically piped from the parent — so the resolver will *always* see non-tty even in interactive sessions. Net effect: recovery prompt never fires; users always silently get the seed list on resolver error. Need a different signal (e.g., `$CLAUDE_INTERACTIVE` env var, or detect `/dev/tty` writability).

7. **Pin-vs-budget race when user lowers budget.** Spec covers truncate-with-warning but doesn't say *which* pins survive truncation when len(pins) > budget. First-N? User-prompt? Truncating arbitrarily silently drops user-pinned personas, defeating the pin contract.

8. **Budget=1 + Codex with Pro limits.** Spec frames Pro accounts as wanting tight budgets, but Codex-additive means even budget=1 dispatches 2 reviewers. If the original motivation for budget was Claude rate limits, Codex-additive doesn't help — but if the motivation is *Claude* persona count specifically, this is fine. Worth surfacing the framing in `docs/budget.md` so users don't miscalibrate.

9. **`install.sh --reconfigure-budget` interaction with adopter-vs-owner default-flip.** Per memory note, install.sh uses `$PWD == $REPO_DIR` to detect owner and flip privacy defaults. New flag handler must short-circuit *before* that detection or it'll prompt for unrelated owner-flip questions every reconfig.

10. **Gate stdout dropped-personas line — where does it land in autorun logs?** `scripts/autorun/*.sh` already has tight quoting/grep-c rules. Adding a "Selected: ... | Dropped: ..." line to gate stdout could collide with autorun log parsers. Check whether autorun greps gate output for persona names anywhere; if so, the dropped-line is a false-positive vector.

## Observations

11. **No upgrade path documented.** When a user adds a new persona to `personas/check/` after configuring pins, do their pins still apply? Implicit answer is yes (pins are just names), but a new persona with a high ranking could displace pinned personas only if pins are consulted first — spec says pins-first which is fine, but worth an explicit acceptance criterion (#15: "new persona added to disk shows up in dispatch when budget allows; existing pins unaffected").

12. **`docs/budget.md` plus QUICKSTART.md plus `--reconfigure-budget` plus tell-Claude-to-reconfigure plus manual edit** = five reset paths. Test matrix is large; `tests/test-resolve-personas.sh` covers resolver but not the install.sh Q&A or the Claude-driven Q&A. Consider an integration test for at least the install.sh path.

13. **Wave-sequencer in plan seed list (8 personas) exceeds visible roster.** Verify `personas/plan/wave-sequencer.md` exists; if it's aspirational, drop it from seed.

14. **`agent_budget=8` ceiling is silent guesswork.** Spec doesn't justify 8 vs the actual roster size. If plan has 8 personas and check has 5, budget=8 means "no cap" for plan but "all available" for check — fine, but the cap should probably be `max(roster_size_per_gate)` not a hardcoded 8.

15. **Headless autorun behavior is the silent risk.** Most actual gate runs in this repo go through `scripts/autorun/`, which is non-tty. Per AC #8, headless = seed list on resolver error, gate continues. Combined with consideration #6 (tty detection broken), in practice *every* run that hits a resolver error silently uses the seed list. That's the autorun-shell-reviewer's documented "false-done" pitfall family — a stage that "succeeds" with degraded behavior. Consider exit-non-zero-on-resolver-error as the autorun default.

## Verdict

**FAIL** — three critical gaps (unverified `codex login status` command, undefined "qualifying row," and missing persona-rankings.jsonl schema contract) block implementation; the resolver script cannot be written deterministically against the current spec, and per the Verify-Before-Shipping rule the Codex subcommand must be confirmed against `--help` before this can move to /plan.

---

## gaps

# Missing Requirements Review — account-type-agent-scaling

## Critical Gaps

**1. Concurrent gate runs racing on `config.json`**
Spec doesn't address two gates (or two terminals) running `resolve-personas.sh` while `install.sh --reconfigure-budget` is mid-write. JSON read could see a truncated file. No mention of write-via-tempfile-then-rename, advisory locking, or read-retry. Likely production incident: a `/build` running parallel agents trips the resolver at the wrong millisecond and the gate dispatches 0 personas.

**2. Backwards compatibility for existing users — actual migration path unspecified**
Spec says "config.json absent → full roster, no change" but token-economics v1 is a precondition and rankings.jsonl will already exist on upgraded machines. What happens on the *first* gate run after this ships for a user who has rankings data but no `agent_budget` set? Does it use rankings? Use full roster? The "absent → full roster" rule contradicts the value prop for users who have data but haven't run install.sh again.

**3. Persona-pin validity on roster drift**
Edge case "Persona in pins no longer exists → skipped with warning" covers deletion. Not covered: persona renamed (common during pipeline evolution — see `feedback_skip_token_self_collision` in memory). No spec for how a renamed persona's pin gets migrated, nor for surfacing stale pins at install time so users can fix them.

**4. Audit logging — no record of what actually ran**
Gate stdout shows selected/dropped at dispatch, but nothing persists. When persona-metrics drift surfaces in `/wrap-insights` Phase 1c, the validator can't tell whether a persona shows 0% participation because it was *budget-dropped* vs *failed to run*. Need a per-gate JSONL append (or a `selected_personas` field on existing artifacts) so persona-metrics-validator can join correctly.

## Important Considerations

**5. `--reconfigure-budget` overwrite semantics**
Spec says "overwrites config.json." Does it preserve unrelated keys a future version might add? Recommend read-modify-write with key allowlist, not full overwrite, to keep forward-compat with token-economics or future configs that share the file.

**6. "Tell Claude to reconfigure" path is under-specified for non-interactive sessions**
What if the user invokes this inside a `/build` subagent or a remote routine? Claude can't run interactive Q&A there. Need an explicit "this only works in interactive top-level sessions" guardrail, or a non-interactive form (`reconfigure --budget=3 --pin spec-review=requirements`).

**7. `codex login status` exit-code contract not pinned**
Spec assumes exit 0 = authenticated. Codex CLI flags drift (memory: `feedback_codex_uncommitted_target`). Verify with `codex login status --help` and quote actual behavior, including what happens when Codex is installed but config-corrupted (could exit 0 with a stale token).

**8. macOS-only, but `~/.config/...` is XDG (Linux convention)**
Path choice is fine but worth noting: macOS-native would be `~/Library/Application Support/monsterflow/`. Picking XDG is a good call for cross-platform later, but the spec should say so explicitly so a future Linux port doesn't relocate the file and break in-place upgrades.

**9. Admin / support debugging story missing**
When a user reports "my gate only ran 1 persona, I expected 6," what does support look at? Need: a `--why` or `--explain` flag on the resolver that prints config path, parsed budget, pins, rankings rows considered, and final selection. Currently a user has to read JSON + JSONL + the script to diagnose.

**10. Rate limiting / abuse — not applicable but worth a one-liner**
Single-user local tool, no rate-limit surface. Spec should explicitly state "no rate limiting needed — local config" so it's clear it was considered, not missed.

**11. Empty/zero acceptance scenario for pin lists**
What if `persona_pins.spec-review = []`? Acceptance criteria don't cover empty pin list (vs absent key). Should behave identically to absent — confirm explicitly.

**12. Test coverage gap: orchestrator wiring**
Memory note `feedback_test_orchestrator_wiring_gap` warns that parallel build agents create test files but forget to wire them into `tests/run-tests.sh`. Spec creates `tests/test-resolve-personas.sh` — explicit acceptance criterion needed: "test count in `tests/run-tests.sh` increases by 1; new test runs in CI."

## Observations

- The 8-persona ceiling matches today's `plan` gate (which lists 8 in seed). If `plan` ever grows a 9th persona, ceiling needs to move — call this out as a deliberate coupling.
- "Pro plan" vs default budget Q&A (3 vs 6) hardcodes Anthropic's current tier structure. When tiers change, install.sh needs editing. Low-risk but worth a comment in the script.
- Stage stdout line `Selected: ... | Dropped: ...` is good UX. Consider also emitting the *reason* a persona was dropped (budget cap vs ranking) so users learn the system.
- `docs/budget.md` is the only new doc. Cross-link from `QUICKSTART.md`, `personas/README.md` (if it exists), and the persona-metrics spec — otherwise it's orphan-documentation.
- No mention of how `/wrap-insights` Phase 1c interprets a budget-limited run. If a persona was dropped by budget, its absence shouldn't count as drift. This needs a coordination note in the persona-metrics spec OR an explicit "future work" line here.

## Verdict

**PASS WITH NOTES** — Spec is well-scoped and the seed/rankings/pins/Codex model is coherent, but the concurrent-write race (Gap 1), the audit-trail gap that breaks persona-metrics joins (Gap 4), and the upgraded-user behavior contradiction (Gap 2) should be resolved before `/plan` rather than after.

---

## requirements

## Critical Gaps

1. **Malformed `config.json` behavior undefined.** Edge cases cover *absent* file and *missing keys*, but not invalid JSON (a hand-edit breaks a brace). Resolver behavior must be specified: hard fail? Treat as absent? Recovery prompt? Same applies to `persona-rankings.jsonl` being malformed vs absent.
2. **"≥1 qualifying row" is ambiguous.** Edge case says rankings fallback triggers when "< 1 qualifying row for the gate." Spec never defines what makes a row *qualify* (gate-match? minimum sample size? recency window?). Without this, criterion #6 isn't testable.
3. **Acceptance #11 ("Tell Claude to reconfigure") is not machine-verifiable.** A QA engineer can't write an automated test for "Claude runs Q&A inline." Either reframe as a documented manual procedure, or specify the deterministic surface (e.g., Claude must call resolve-personas.sh in --validate mode after writing).

## Important Considerations

1. **Config-file permissions unspecified.** Not a secret, but `~/.config/monsterflow/config.json` should have an explicit mode (likely 644). Worth stating to avoid drift.
2. **Resolver performance budget missing.** Script runs on every gate dispatch; no latency target. Suggest "< 250ms p95" so it doesn't compound gate startup time.
3. **Pin-references-missing-persona path under-tested.** Edge case says "skipped with warning, remaining budget filled from rankings/seed" — but no acceptance criterion verifies the fill-up actually happens. Add an AC.
4. **Upgrade behavior for existing users.** Spec says "config absent → full roster, no change." But seed list for `plan` has 8 entries while default budget is 6 — once a user *creates* a config, they silently lose 2 personas. Call out this transition explicitly in `docs/budget.md`.
5. **Concurrency on config writes.** Two `--reconfigure-budget` runs (or Claude + install.sh) could race. Either lock or document "last writer wins."

## Observations

- `session_roster: defaults-only` header — confirm this is a recognized frontmatter key in the pipeline, not just descriptive.
- Codex-adversary is treated as a special case in ~6 places; consider one named constant (`ADDITIVE_REVIEWERS`) so future additive reviewers don't require spec edits.
- No observability requirement (e.g., log selected/dropped persona counts to a JSONL for later analysis). Could feed back into rankings quality. Out of scope is fine, but worth a backlog note.
- Sequencing dependency on token-economics v1 is in Summary but not in Dependencies section — promote it for clarity.

## Verdict

**PASS WITH NOTES** — Acceptance criteria are largely binary and edge cases thorough; tighten malformed-input handling, define "qualifying row," and reframe AC #11 before implementation.

---

## scope

# Scope Analysis — account-type-agent-scaling

## Critical Gaps

**1. Pin validation rule for non-existent personas at install time is unspecified.**
Edge Cases handles "persona in pins no longer exists" at runtime, but `install.sh` Q&A doesn't say whether it validates pin names against the actual `personas/<gate>/` directory. If a user typos `requirments`, does install reject, accept silently, or warn? This is a config-write path — runtime fallback isn't enough.

**2. "Pro plan" prompt branch has no behavioral consequence beyond a different default.**
Steps 2–4 in install Q&A ask Pro yes/no, but the only difference is default 3 vs 6. The config file stores no `plan_tier` field. Either store it (so `--reconfigure-budget` remembers context) or drop the question and ask budget directly with one default. Current design asks a question whose answer is discarded.

## Important Considerations

**3. "While we're in there" risk: gate stdout transparency.**
Acceptance #9 ("selected + dropped personas before dispatch") is a UX addition not strictly required by budgeting. It's small, but it's an example of bundled scope — if the resolver wiring is the MVP, transparency could be phase 2. Worth flagging because it touches all three command files.

**4. Per-gate seed lists embed an opinion that will be re-litigated.**
The seed orderings (e.g. plan: risk, integration, api, data-model, security, ux, scalability, wave-sequencer) are presented as fact but they're a ranking. Day-after-launch question: "why is `risk` ahead of `integration` for plan?" Recommend either (a) document the rationale in `docs/budget.md`, or (b) note these are starting points and rankings will replace them after first run.

**5. Phase-2-in-disguise: `persona_pins` per-gate at install.**
Step 5 prompts pins per gate at first install — three extra questions before the user has any rankings data to inform the choice. MVP could ship with pins **disabled at install** (write empty pin lists, document how to add later) and still hit acceptance criteria 1–14. Pins are useful but they're tuning, and tuning before data is guesswork.

**6. Dependency on token-economics v1 is stated but not gated.**
Spec says "ships after token-economics v1 is live and producing ranking data" but the feature works without rankings (seed fallback). What's the actual ship gate — token-economics merged, or token-economics producing data? If the seed fallback is a first-class path, this could ship independently and benefit from rankings later.

**7. Overlap with existing kickoff/constitution flow.**
`/kickoff` builds a constitution that selects a persona roster. This spec adds a *second* roster-shaping mechanism (budget + pins) at install time. Stakeholders will ask: "does my constitution roster override the budget, or vice versa?" Spec says `session_roster: defaults-only` so this run sidesteps it, but the long-term interaction between constitution roster and `agent_budget` is undefined.

## Observations

**8. MVP could be smaller.** The smallest version that delivers value: `agent_budget` integer + seed-list selection + `--reconfigure-budget`. That's it. Pins, rankings integration, recovery prompt, and Codex additivity could each be a follow-up. Not arguing for that cut, but the spec doesn't articulate what's MVP vs. nice-to-have, so cuts will be ad-hoc if scope pressure hits.

**9. "Tell Claude to reconfigure" is an unusual integration point.**
A natural-language path that mutates a config file. Worth documenting *which* skill/command surface this lives in, or it'll quietly become "Claude does it however it feels" each run. Could be a thin slash-command wrapper around `install.sh --reconfigure-budget` to keep one path.

**10. Linux exclusion is fine but worth a one-line reason in `docs/budget.md`.**
"macOS-only" without rationale will get asked. Likely just "matches token-economics v1 platform target."

**11. `~/.config/monsterflow/` is a new XDG-style location.**
Repo currently uses `~/.claude/` and project-local paths. Worth confirming this is the desired direction (it's clean, but it's a new convention this spec introduces).

**12. Codex additivity rule is buried.**
The "Codex never counts against budget" rule shows up in Summary, UX, Data, and Acceptance #4 — good — but `docs/budget.md` deliverable should call it out as a top-line section, since it's the single most surprising behavior.

## Verdict

**PASS WITH NOTES** — Scope is well-bounded with explicit out-of-scope statements and backlog routing; the two critical gaps (pin validation at install, Pro-plan question with no stored consequence) are small and fixable inline without restructuring the spec.

---

## stakeholders

# Stakeholder Analysis — account-type-agent-scaling

## Critical Gaps

**1. Existing users with in-flight runs are unrepresented.**
The spec says "config.json absent → no behavior change," but does not address users who *upgrade* MonsterFlow mid-pipeline. If a user is between `/spec` and `/plan` when they pull a new version and run `install.sh`, will the budget Q&A interrupt them? Will `/plan` suddenly dispatch a different roster than `/spec-review` did? Add an explicit acceptance criterion: install.sh budget Q&A is skippable (e.g., `--skip-budget-config`) for users who don't want to be prompted on upgrade, AND mid-pipeline behavior is documented (does the budget apply per-feature or per-invocation?).

**2. The Codex stakeholder is silently coupled to authentication state.**
`codex login status` is checked at every gate dispatch. If a user's Codex auth expires (token rotation, machine change, plan downgrade), Codex silently disappears from their reviewer roster. The spec offers no notification path. A user could ship a feature thinking they got Codex's plan-vs-reality drift check (a documented strength per `feedback_codex_catches_plan_vs_reality_drift.md`) when they actually didn't. Add: when Codex is *expected but unauthenticated*, surface a one-line warning ("Codex not authenticated — run `codex login` to restore adversarial review"). "Expected" can be inferred from the last successful gate run that included Codex, stored in config or a sidecar.

**3. Pin-vs-rankings conflict resolution is underspecified.**
Acceptance #2 says "pins first, then rankings top-N, then seed fill-up." But what if a pinned persona is *also* the lowest-ranked? At budget=2 with one pin, you dispatch the pin + rankings #1 — but the user pinned that persona for a reason (probably overriding rankings). This is fine. The gap: what if the pin list contains a persona that has been *removed* from `personas/<gate>/`? Edge case row says "skipped with warning, remaining budget filled" — but the user explicitly pinned it. They should be told *which pin* was dropped, not just that one was, so they can update config.json. Make the warning name-specific.

## Important Considerations

**4. Operators / debugging stakeholders.**
When a `/check` run produces an unexpected NO-GO, the first debugging question is "which personas ran?" Acceptance #9 (stdout shows selected + dropped) is good, but stdout is ephemeral — the wrap-insights / persona-metrics flow reads JSONL artifacts. Confirm that the resolver's selection decision is captured in the gate's output artifact (e.g., `check.md` frontmatter or sidecar `selection.json`) so persona-drift analysis isn't blind to budget effects. Otherwise `persona-metrics-validator` will see "persona X at 0% participation" and not know whether X was dropped by budget or by failure.

**5. The `install.sh` adopter-vs-owner distinction is not addressed.**
Per `feedback_install_adopter_default_flip.md`, `install.sh` flips defaults based on `$PWD == $REPO_DIR`. The owner (Justin) running install in MonsterFlow itself probably wants different budget defaults than an adopter. The spec defaults (Pro: 3, non-Pro: 6) are reasonable for adopters but Justin himself uses the full roster — should owner-run installs default to "no budget set" so the existing roster is preserved without prompting? Worth one acceptance criterion.

**6. QA / testability — `tests/run-tests.sh` orchestrator wiring.**
Per `feedback_test_orchestrator_wiring_gap.md`, parallel /build agents reliably forget to register new test files in the orchestrator. The spec lists `tests/test-resolve-personas.sh` as a created file. Add an explicit acceptance criterion: `bash tests/run-tests.sh` invokes `test-resolve-personas.sh` and the test count in CI/preship matches `ls tests/test-*.sh | wc -l`. Otherwise the test exists but never runs.

**7. Customer support / first-question stakeholders.**
The most likely confused-user question is *"Why did my /check only run 1 reviewer?"* — an adopter sets budget=1 during install (because the Pro prompt sounded scary), forgets, and weeks later sees a degraded check. The spec has the data to answer this (stdout selected/dropped) but not the *discoverability* path. Add to `docs/budget.md`: a "Why am I seeing only N personas?" troubleshooting section that points at config.json and the reconfigure flag.

**8. Codex-as-stakeholder veto.**
Codex being "always additive, never counted against budget" is a strong design choice that gives Codex implicit veto-by-default at any budget level. If a user genuinely wants a Codex-free run (cost, privacy, offline work), there's no opt-out. Consider: add `codex_enabled: true` (default) to config.json schema, with `false` suppressing Codex regardless of `codex login status`. Low-cost addition, prevents future support tickets.

## Observations

**9. Documentation stakeholder — `docs/budget.md` and `QUICKSTART.md` are listed but the wrap/install docs (`docs/index.html`, README budget section if any) aren't.** Worth a sweep at build time to find any other doc that lists "6 personas per gate" as a fact.

**10. Per-project override is explicitly out of scope.** Reasonable for v1, but team users (if any) on shared machines will hit this. Note in `docs/budget.md` as a known v1 limitation so it doesn't become a support escalation.

**11. The "Tell Claude to reconfigure" path** depends on Claude correctly reading and writing JSON to a tilde-expanded path. Per `feedback_tilde_expansion_in_bash_config_reads.md`, this has bitten before. Make sure the Claude-driven Q&A path uses `$HOME` not `~` literals when writing.

**12. `dashboard/data/persona-rankings.jsonl`** is a public-repo data artifact concern (per `feedback_public_repo_data_audit.md`). This spec doesn't change that, but if budget config influences which personas accumulate ranking data, the rankings file may skew over time toward whatever pins users set. Worth a note in the token-economics spec follow-up, not a blocker here.

## Verdict

**PASS WITH NOTES** — Stakeholder coverage is strong on the primary axes (user, install path, Codex), but operator-debugging visibility into selection decisions (#4), the test-orchestrator wiring (#6), and the Codex opt-out gap (#8) should be addressed before `/build`; the upgrade-path question (#1) is the only true blocker.

