---
feature: account-type-agent-scaling
stage: spec-review
created: 2026-05-04
reviewers: requirements, gaps, ambiguity, feasibility, scope, stakeholders, codex-adversary
overall_health: Concerns
---

# Review: Account-Type Agent Scaling

**Overall health: Concerns** — the spec is structurally sound (clear scope, thorough edge-case table, honest sequencing), but four resolver-contract decisions are underspecified to the point that two engineers would ship divergent implementations. None of the Concerns require re-spec; they need resolution during `/plan`.

## Reviewer Verdicts

| Dimension | Verdict | Key Finding |
|-----------|---------|-------------|
| Requirements | PASS WITH NOTES | Pin-validation AC, "Tell Claude" protocol, and Codex probe robustness need tightening to make the spec QA-derivable. |
| Gaps | PASS WITH NOTES | Concurrent config write atomicity and install.sh re-run / migration path are unaddressed. |
| Ambiguity | FAIL | Four implementation-blocking ambiguities (dedupe order, qualifying-row, option-3, full-roster sizing). |
| Feasibility | PASS WITH NOTES | Buildable, but qualifying-row definition, ranking sort key, and JSON-parser choice must land in `/plan`. |
| Scope | PASS WITH NOTES | Recommend collapsing 3 reset paths to 2, inlining `docs/budget.md` into QUICKSTART, simplifying install Q&A to a single budget question. |
| Stakeholders | PASS WITH NOTES | No persona-author feedback loop; cold-start lockout silently freezes the bottom of the leaderboard. |
| Codex (adversarial) | n/a | 6 critical gaps; strongest convergence on ranking-source contract and recovery ownership. |

## Before You Build (8 items)

These eight items must be resolved during `/plan`. Each is flagged independently by 2+ reviewers (or by the adversarial Codex pass plus a Claude reviewer); the convergence makes them blocking for code, not for proceeding to plan.

1. **Define "qualifying row" for `persona-rankings.jsonl`** *(Ambiguity, Feasibility, Codex)*. Token-economics v1 ships rows with `insufficient_sample: true` when `runs_in_window < 3`. Resolver must pick one: (a) any row with `gate=<gate>` qualifies, (b) only `insufficient_sample == false` rows qualify. Real rows in `dashboard/data/persona-rankings.jsonl` already exhibit the unstable case. Add a freshness window or explicitly accept stale-rankings-are-fine while you're at it (Stakeholders, Requirements).

2. **Pick the ranking sort key + tiebreaker** *(Feasibility, Codex)*. Rows expose `judge_retention_ratio`, `downstream_survival_rate`, `uniqueness_rate`, `avg_tokens_per_invocation`. Several rows have `judge_retention_ratio: null` and `total_emitted: 0`. Spec says "top-N" but never picks the key or the null/tie rule. `/plan` must lock these and write a unit test against representative rows.

3. **Resolve "full roster" sizing collision** *(Ambiguity, Codex)*. Edge Case row 1 says config-absent → "full roster"; default budget is 6 (Data & State) but plan's seed list has 8 personas. Three readings exist: (a) all available personas for that gate (5/8/5), (b) seed list capped at default-6, (c) something else. Pick one and reconcile AC-1 with AC-2.

4. **Specify pin/rankings/seed dedupe in AC-2** *(Ambiguity, Codex, Stakeholders)*. "Pins first, then rankings top-N, then seed fill-up to 3" is ambiguous when a pin already appears in rankings or seed. Spec must say: dedupe by persona name across all three sources in declared order, stopping when budget is reached. Also clarify pin-list-length validation runs **per gate** (Stakeholders #6) — pins are per-gate, budget is global.

5. **Define recovery option-3 ("disable budget for this run")** *(Ambiguity, Requirements, Codex)*. AC-7 says options must not "silently restore full roster on a budgeted session" — but never says what option-3 *does* dispatch. Specify: which roster runs at this gate, and whether the budget reactivates automatically at the next dispatch or stays disabled until reconfigured.

6. **Harden the Codex authentication probe** *(Requirements, Gaps, Ambiguity, Codex)*. Resolver runs `codex login status` on every gate dispatch. Spec says exit-0 = authenticated; spec is silent on (a) timeout (a hung CLI hangs every gate), (b) `codex` binary absent (PATH miss vs non-zero exit), (c) cache between gates in a session. Add a short timeout (~2s), treat timeout/missing-binary as "not authenticated", and consider one-shot caching for the session.

7. **Declare the JSON parsing tool** *(Feasibility)*. `resolve-personas.sh` reads a JSON config and a JSONL rankings file on macOS Bash 3.2 — no associative arrays, `jq` not guaranteed, Python 3.9 vs 3.11 split (per CLAUDE.md). Pick one (`python3` is the safer default given the existing repo dependencies) and gate the `install.sh` Q&A to verify the chosen tool exists before writing config.

8. **Mandate atomic config writes + read-error tolerance** *(Requirements, Gaps)*. `install.sh --reconfigure-budget` and "Tell Claude" both write `config.json`; resolver reads it on every gate dispatch. Concurrent gate runs can hit a half-written file. Require write-via-tmp + `mv -f` (atomic), and define resolver behavior on JSON parse error (likely: warn to stderr + use seed list — same as the rankings-absent path).

## Important But Non-Blocking (10 items)

These should be addressed in `/plan` or as discrete plan deliverables, but they don't block plan progression.

1. **Persona-author feedback loop is missing** *(Stakeholders, Codex)*. Gate stdout shows "Selected: ... | Dropped: ..." but stdout is ephemeral. A persona consistently culled at budget=3 has no persistent signal. Recommend a `dashboard/data/persona-drops.jsonl` (one row per dispatch decision: gate, run_id, selected[], dropped[]) — small append, cheap to add at the resolver, lets `/wrap-insights` surface drop frequency later.

2. **Cold-start lockout for low-ranked personas** *(Stakeholders)*. A persona that ranks 7th can never accrue findings at budget=3 because it never runs. No exploration mechanism (epsilon-greedy slot, periodic full-roster sweep, ranking-decay-on-non-execution). At minimum, document the lockout in `docs/budget.md` so adopters understand the leaderboard freeze; ideally allocate one budget slot to a randomized non-pin/non-top-N persona.

3. **Resolver-absent fallback for gate commands** *(Gaps)*. If `scripts/resolve-personas.sh` is missing (older clone, partial install, deleted), gate commands should fall back to today's hardcoded list with a single warning. Add an AC.

4. **Install.sh re-run / migration path** *(Gaps)*. Re-running `install.sh` on an existing checkout (most common upgrade trigger) is not differentiated from a fresh install. Spec covers config-absent (AC-1) and `--reconfigure-budget` (AC-10) but not "user re-runs `./install.sh` after pulling latest." Adopter-vs-owner default-flip pattern from CLAUDE.md memory applies.

5. **`tests/run-tests.sh` TESTS-array wiring** *(Feasibility)*. CLAUDE.md memory `feedback_test_orchestrator_wiring_gap.md` documents this exact failure mode: tests get written, never registered in the orchestrator, smoke test stays green. `/plan` must include "append `tests/test-resolve-personas.sh` to the TESTS array."

6. **Tilde-expansion gotcha** *(Feasibility)*. CLAUDE.md memory `feedback_tilde_expansion_in_bash_config_reads.md` flags a literal-tilde-tree incident from `/wrap` Phase 2c. The resolver and install.sh use `~/.config/monsterflow/` everywhere; mandate `${HOME}` or `${VAR/#\~/$HOME}` before any `mkdir`/write.

7. **Gate-command splice contract** *(Feasibility, Codex)*. The three gate command files contain prose-not-code persona lists that the model reads and acts on. "Replace hardcoded persona list with resolver output" is not a one-line bash substitution — it's a prompt rewrite. `/plan` must specify: where in each command file the splice happens, what stdout-format-to-prompt-instruction translation looks like, and whether the resolver names map 1:1 to existing persona-file basenames.

8. **Recovery prompt: 3 options vs. "warn + use seed"** *(Scope)*. AC-7 mandates a 3-option interactive prompt, but the non-tty path already specifies "warn + seed list." Two code paths, two test surfaces. Recommend: collapse interactive to "warn + seed" matching non-tty (one path, one tested behavior). If the 3-option UX is kept, option-3 must be defined per item 5 above.

9. **Pro-vs-Max-vs-other tier framing** *(Stakeholders, Ambiguity, Codex)*. Install Q&A asks Pro/yes-no; Max users get the same default-6 path as undeclared. Either ask explicitly (Pro / Max / other) or drop tier framing entirely and just ask "How many personas?" (which is what Scope #3 recommends — collapses to a single question).

10. **`docs/budget.md` testability + scope** *(Requirements, Scope)*. AC-13 enumerates content but no machine-checkable contract. Scope recommends inlining into QUICKSTART. Either is fine; pick one and add either (a) grep-able anchor IDs the test asserts, or (b) drop AC-13 and rely on QUICKSTART changes.

## Observations

- **Edge Cases table is the spec's strongest asset** — most ACs map cleanly to a row, derivation of the test plan is unusually easy. Strong testability foundation (Requirements).
- **Sequencing claim ("ships after token-economics v1 is live") is met today** — `dashboard/data/persona-rankings.jsonl` is populated. No precondition wait (Feasibility).
- **`codex login status` exit-0 verified empirically on this machine** ("Logged in using ChatGPT" returns 0). Spec assumption holds; `/plan` should still cite the verification (Feasibility).
- **Pin double-handling is belt-and-suspenders** — install rejects + runtime truncates with warning. Pick one path; runtime truncation alone suffices if install validation is reliable (Scope).
- **Codex-additive rule is well-scoped** — one conditional line, one exit-code check, no budget arithmetic entanglement. Not a creep vector (Scope).
- **AC-12 literal-zero ambiguity** — Edge Cases says runtime treats `0` as floor=1; AC-1 says unset → full roster. Spec needs to say which wins for a literal `"agent_budget": 0` (Ambiguity).
- **AC-9 stdout format unspecified** — UX shows comma-separated; tests will need to assert format (Ambiguity).
- **No AC for budget=8 ceiling** — covers `=1`, `=3`, unset, `>8`. Add one (Requirements).
- **XDG_CONFIG_HOME** — adopters with this set expect `$XDG_CONFIG_HOME/monsterflow/`. AC-13 hardcodes the literal path. Minor (Stakeholders).
- **`--reconfigure-budget` overwrites without backup or diff** — adopter who tuned pins manually loses them. Consider a one-line `cp config.json config.json.bak` before write (Stakeholders).
- **Backlog-routing item #1 is not "unrelated"** — the entire feature is a token-economics mitigation; per-plugin cost is the next layer down. Routing decision (defer) still correct, but the framing is loose (Codex).

## Codex Adversarial View

Codex independently surfaced 6 critical gaps; 5 of 6 are reflected in the consolidated **Before You Build** list above (qualifying-row, full-roster sizing, ranking selection, recovery ownership, Codex probe). One distinct contribution:

- **Recovery ownership unclear**: `Integration` says `resolve-personas.sh` exits non-zero only on unrecoverable error; `Recovery on resolver failure` says the prompt fires "on resolver script error." But the gate command, not the resolver, likely owns fallback dispatch. AC-7/AC-8 don't say whether the prompt is implemented in shell, in the gate command's natural-language instructions, or both. **Resolution direction:** the gate command (which already brackets reviewer dispatch) is the right owner; the resolver should print a structured `STATUS=ok|seed-fallback|error` line that the gate command parses to decide whether to prompt. Lock this contract in `/plan`.

## Conflicts Resolved

- **Requirements vs Ambiguity on AC-12 floor**: Requirements treats it as testable-as-written; Ambiguity flags the literal-zero-vs-unset collision. Ambiguity's framing is correct — kept as Observation row "AC-12 literal-zero".
- **Scope vs Stakeholders on the install Q&A**: Scope recommends collapsing to a single budget question (drop tier framing); Stakeholders recommends asking Pro/Max/other explicitly. Surface decision: collapse is simpler and removes the asymmetry Stakeholders flagged — kept as Item 9 (single question) with Stakeholders' Pro-vs-Max concern as the rationale.
- **Scope vs Requirements on `docs/budget.md`**: Scope says inline into QUICKSTART, Requirements says specify a machine-checkable contract. Both fine — kept as Item 10 with two sub-options.
- **Gaps vs Requirements on concurrent writes**: Gaps treats as critical, Requirements as important. Convergent signal makes it a Before-You-Build item (#8); the atomic-write requirement is cheap to add and defends against a real failure mode.

## Reviewer Output Locations

Raw per-persona reviews are persisted at:
- `docs/specs/account-type-agent-scaling/spec-review/raw/{requirements,gaps,ambiguity,feasibility,scope,stakeholders,codex-adversary}.md`

Source snapshot: `docs/specs/account-type-agent-scaling/spec-review/source.spec.md` (sha256 captured in `run.json`).
