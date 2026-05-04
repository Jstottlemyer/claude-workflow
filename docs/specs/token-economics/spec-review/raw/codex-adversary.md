**Verdict: FAIL for public-release-ready.** v3 is much tighter, but it still has several design holes that will cause incorrect metrics or unstable implementation. I would not ship this spec as “ready-for-plan” until the data model/run-linkage questions are closed.

**Blockers**

1. **The cost/value join is still under-specified.**

The spec says the window is the most recent 45 `(persona, gate)` invocations, where invocation comes from Agent dispatches, but the value side comes from `docs/specs/*/{spec-review,plan,check}/{findings,survival}.jsonl` and `raw/<persona>.md`.

It never defines a reliable join from:

`Agent tool_use_id / parent_session_uuid / agentId`

to:

`raw/<persona>.md`, `findings.jsonl`, `survival.jsonl`, `run.json.created_at`

Without that, the script cannot know which findings belong to which invocation, especially across historical runs, repeated runs, retries, renamed specs, or overwritten stage directories.

Concrete fix: require every metrics artifact to carry a stable `run_id`, `gate`, `persona`, `agent_tool_use_id` or equivalent dispatch id. If existing artifacts lack that, v1 should explicitly be “best-effort aggregate by artifact directory,” not invocation-windowed.

2. **Content-hash reset is not implementable from current-state persona files alone.**

The spec says persona prompt edits reset the `(persona, gate)` window using `persona_content_hash`. But if historical invocations did not record the persona file hash at dispatch time, the compute script only knows the current hash. It cannot determine which old runs used the old persona content versus the new content.

A4’s test sequence implies the system can drop pre-edit data after one fresh dispatch, but there is no persisted boundary unless dispatch-time hashes already exist.

Concrete fix: either add persona hash capture to gate execution first, or weaken v1 to: “hash changes mark the current row as a new hash; historical attribution may be dropped wholesale unless artifacts include matching hash.”

3. **The rolling 45 window mixes cost-defined invocations with value-defined artifacts.**

If an Agent dispatch exists but the Judge failed, findings are malformed, survival is missing, or `/wrap-insights` never ran, does that invocation count in `runs_in_window`? The spec implies yes for cost, but value denominators depend on artifacts that may not exist.

This will bias survival upward if failed/noisy runs are skipped, or bias rates unpredictably if cost-only runs count with zero emitted.

Concrete fix: define run states explicitly:

- `complete_value`
- `missing_raw`
- `missing_findings`
- `missing_survival`
- `malformed`
- `cost_only`

Then define which states count toward `runs_in_window`, token totals, and each rate denominator.

4. **`raw/<persona>.md` bullet counting is a weak denominator.**

Counting lines starting with `- ` or `* ` under selected headings assumes stable markdown output. It misses wrapped bullets, numbered lists, nested bullets, headings with punctuation changes, and bullets generated outside those headings. It also treats low-signal Observations the same as Critical Gaps.

More importantly, Judge clustering can merge multiple raw bullets into one finding or split one raw bullet into multiple findings, so `judge_survival_rate = findings / bullets` is not a true survival rate. It is a rough compression ratio.

Concrete fix: either rename it to something like `judge_retention_ratio`, or require raw emitted bullets to be written as structured JSONL with stable `raw_bullet_id`, `persona`, `severity`, and `gate`.

5. **The public-release privacy tests are too shallow.**

A10 only checks for title/body canaries and fixture field names like `prompt`, `body`, `text`, `content`. That misses leakage through:

- file paths embedded in IDs or metadata
- user/project names in session ids, descriptions, or filenames
- timestamps that identify private work
- model/provider metadata that adopters may consider sensitive
- persona names from private workflows
- arbitrary nested fields with non-obvious names

Also, `contributing_finding_ids[]` being “sha256-derived” does not guarantee privacy if the hash input is guessable, unsalted, or derived from private titles.

Concrete fix: define an allowlist schema for redacted fixtures and generated rankings. Tests should reject every field not explicitly allowed, not scan for a few bad field names.

**Major Issues**

6. **“ready-for-plan” conflicts with unresolved Phase 0 questions.**

Open Q1 and Q2 directly affect implementation shape, test fixtures, runtime cost, and project discovery. Calling the spec public-release-ready while saying the logging-shim path may become a separate spec is risky. If the parent annotation differs from subagent totals or worktree layout breaks, this spec’s implementation path changes materially.

Concrete fix: make Phase 0 a required pre-plan deliverable, then revise the spec once Q1/Q2 are actually closed.

7. **Project discovery is over-broad for a public tool.**

Scanning `~/Projects/*/docs/specs/` will pick up any repository with that shape, including private forks, experiments, or non-MonsterFlow docs. The spec says this is useful, but for public release the safer default is explicit opt-in.

Concrete fix: default to current repo only plus `~/.config/monsterflow/projects`. Make `~/Projects/*` scanning opt-in via flag or config.

8. **`last_seen` from `run.json.created_at` assumes a file the spec does not otherwise define.**

The value artifacts listed are `findings.jsonl` and `survival.jsonl`; `run.json` appears only in `last_seen`. If older runs lack `run.json`, or if multiple gates share one run file, ordering the 45-window becomes ambiguous.

Concrete fix: specify the exact location and schema of `run.json`, fallback behavior, and whether missing timestamps exclude rows or sort last.

9. **Freshness race check is not sufficient.**

“Compare `last_seen` of new vs old; if older, abort” can drop valid updates. Example: run A computes through May 2 with many personas; run B computes through May 2 plus one malformed-file skip. Same `last_seen`, different rows. Or two different gates have different max timestamps.

Concrete fix: use a lock file, or compare a deterministic source high-water mark per project/gate. Last-writer-wins with atomic replace is acceptable if documented; the freshness check as written creates false confidence.

10. **Totals without averages are awkward for cost comparison.**

The spec says dashboard divides if it wants, but the dashboard columns only list `total_tokens`, not `avg_tokens_per_run`. Ranking “lowest total cost” penalizes frequently used personas and rewards rarely used ones, even with `runs_in_window >= 3`.

Concrete fix: include `avg_tokens_per_invocation` as a first-class derived field or require dashboard/wrap text to rank cost by average, with total shown separately.

11. **Downstream survival depends on artifact timing and pipeline type.**

The spec includes plan/check/code as possible downstream artifacts, but only defines a join through `survival.jsonl`. It does not say when survival is considered final, how delayed downstream artifacts update previous rows, or whether different gates have comparable survival semantics.

Concrete fix: add `survival_artifact_type`, `survival_observed_at`, and a `pending_downstream` state. Otherwise low downstream survival may just mean “not evaluated yet.”

**Non-Blocking But Worth Fixing**

12. **The dashboard “never run” hybrid layer needs a canonical roster source.**

It says current `personas/` files, but the session roster is “defaults-only (28 pipeline personas).” If files exist but are disabled, experimental, or gate-inapplicable, they will render as never-run noise.

13. **Deleted-persona behavior conflicts with content-hash reset.**

Deleted personas get `persona_content_hash: null`, but if the hash is part of the identity/reset boundary, null collapses all deleted historical versions together.

14. **A9 checks the wrong privacy target.**

It checks `docs/specs/<feature>/spec-review/findings.jsonl` and `dashboard/data/persona-rankings.jsonl` are ignored. But the spec also creates `tests/fixtures/persona-attribution/`, which is explicitly committed. That fixture path needs the strictest privacy gate.

15. **Open Q3 says “if linkage breaks under load” but gives no abort criterion.**

For public release, define a minimum linkage success threshold. Example: “If fewer than 99% of Agent dispatches with persona prompts resolve to `(agentId, persona, gate, tokens)`, the script exits non-zero unless `--best-effort` is passed.”

**Bottom Line**

The most serious remaining problem is that v3 talks as if invocation-level metrics are available, but the value artifacts appear to be artifact-level and possibly overwritten or only loosely tied to Agent dispatches. Fix the run identity contract first. After that, simplify privacy defaults, make project discovery opt-in, and rename or restructure the bullet-count “survival” metric so users do not overinterpret it.