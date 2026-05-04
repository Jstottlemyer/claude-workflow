# Implementation Plan: account-type-agent-scaling

**Created:** 2026-05-04
**Spec:** `docs/specs/account-type-agent-scaling/spec.md`
**Review:** `docs/specs/account-type-agent-scaling/review.md` (Significant Gaps — 10 blockers, 20 important, 8 risks)
**Mode:** autorun headless — plan resolves spec-review blockers inline rather than bouncing back to `/spec`.

## Synthesis Summary

The feature inserts a single shell helper (`scripts/resolve-personas.sh`) into the pre-flight of three pipeline gates. The resolver reads a machine-local JSON config + a rankings JSONL produced by token-economics v1 and prints the persona roster the gate should dispatch. The spec is salvageable but ten design-level decisions were under-specified; the plan resolves each one as an explicit implementation choice, then layers three risk mitigations (resolver SPOF, headless silent-degradation, config corruption) on top.

**Architecture in one paragraph:** Gate command → `resolve-personas.sh <gate>` → JSON output `{selected:[...], dropped:[...], codex_additive:bool, fallback_reason:null|string}` → gate prints `Selected: ... | Dropped: ...` banner → gate dispatches selected personas plus Codex when `codex_additive=true`. Config write paths (install.sh, "tell Claude", manual edit) all funnel through `scripts/lib/budget-validate.py` for schema validation, atomic write, and `.bak` rotation. Defaults (budget, ceiling, seed lists) live in one canonical file (`scripts/resolve-personas/seeds.json`) read by both runtime and docs-consistency tests.

## Design Decisions (resolves spec-review B1–B10)

| # | Blocker | Decision | Rationale |
|---|---------|----------|-----------|
| D1 | B1 — `risk` invalid for `/plan` | Plan budget=1 default is **`wave-sequencer`**; full plan seed = `wave-sequencer, security, integration, api, data-model, scalability, ux` (7, matches `commands/plan.md`). | `wave-sequencer` is on-disk and is the closest analogue to "risk-shaped" thinking at plan time. Verified via `ls personas/plan/`. |
| D2 | B2 — Rankings algorithm undefined | **Sort key:** `(downstream_survival_rate DESC, total_unique DESC, persona ASC)`. **Filter:** `gate == <gate>` AND `insufficient_sample == false` AND `runs_in_window >= 3`. Codex-adversary is excluded from this ranking pass (it's added separately as additive, see D6). | Survival rate is the outcome metric; total_unique breaks survival-rate ties; alphabetical persona is final deterministic tie-break. The 3-run minimum filters out brand-new personas. Pinned in `scripts/resolve-personas.sh` and `docs/budget.md` as pseudocode. |
| D3 | B3 — pin/rank/seed merge order | **Algorithm (pseudocode):** `slots=budget; result=[]; for p in pins[gate]: if p in roster and p not in result: result.append(p); slots-=1; for p in ranked[gate] (top-down): if slots==0: break; if p not in result: result.append(p); slots-=1; for p in seeds[gate] (in order): if slots==0: break; if p not in result: result.append(p); slots-=1; return result`. Pins consume budget. Dedup by name. | Single deterministic pass; matches AC #2 wording ("pins first, then rankings, then seed fill-up"). |
| D4 | B4 — AC #7 vs UX option (3) | **Drop UX option (3)** "disable budget for this run". Recovery prompt has exactly **two** options: (1) reconfigure now, (2) continue with seed list. Updates spec AC #7 wording in the plan's acceptance section. | The contradiction is unfixable as worded. Two clean options is enough; users who really want to bypass can `RESOLVE_PERSONAS_BYPASS=1` (R1 mitigation, also covers AC #7's intent). |
| D5 | B5 — "no behavior change" inconsistency | **When config.json is absent OR `agent_budget` is unset:** resolver outputs the verbatim pre-feature roster for each gate (6/7/5 personas) AND emits `fallback_reason: "no_config"`. The gate command **suppresses the Selected/Dropped banner** in this state — byte-identical stdout to today. Banner appears only when a budget is actually applied. AC #1 stays. | Banner-when-no-config was the only contradiction; suppressing it preserves "no behavior change" for upgraders. |
| D6 | B6 — Codex-at-plan contract | **Codex-additive applies at `/spec-review` and `/check` only.** At `/plan`, the resolver omits codex-adversary regardless of auth state. `commands/plan.md` is unchanged with respect to Codex (it has no Codex phase today). | Schema docs and `findings.jsonl`/`survival.jsonl` only model Codex at the two existing stages; extending to `/plan` would require schema work that's out of scope. Documented in `docs/budget.md` and the resolver source. |
| D7 | B7 — Convergence at budget=1 | Document in `docs/budget.md` under "Tradeoffs at low budgets": "At budget=1 every Claude finding is single-source by construction — Judge cannot promote on convergence. Codex-adversary (where applicable) is treated as a convergence partner of weight ≥1 with the Claude persona." Judge persona file gets a one-line addendum. | Spec-review B7 is real but small. Doc-only fix. |
| D8 | B8 — Selected/Dropped contract | **Resolver output is JSON to stdout** (single line, machine-parseable): `{"selected":["requirements","gaps"],"dropped":["scope","ambiguity","feasibility","stakeholders"],"codex_additive":true,"fallback_reason":null,"rankings_mtime_days":3,"banner_suppressed":false}`. Gate command parses with `python3 -c "import json,sys; d=json.load(sys.stdin); ..."`. Stderr is reserved for human-readable warnings. | One contract for all three callers; `dropped[]` is computed inside the resolver, not by the gate. Stable format pinned in `docs/budget.md`. |
| D9 | B9 — token-economics "live" precondition | **Live ≡ `dashboard/data/persona-rankings.jsonl` exists AND has ≥3 rows where `insufficient_sample == false`.** Resolver checks; if fewer, fallback to seed list with `fallback_reason: "rankings_insufficient"`. | Concrete, file-checkable, no human judgment. |
| D10 | B10 — participation drift contamination | **Add field `dispatch_status` to `schemas/participation.schema.json`** (enum: `dispatched`, `budget-dropped`, `not-applicable`). Change `additionalProperties: false` migration via `schema_version: 2`. Persona-metrics emit writes one row per *roster* persona at each gate, not per *dispatched* persona, with `dispatch_status` reflecting the resolver decision. `validate-personas.py` and `persona-metrics-validator` subagent updated. | Without this, dropped personas show as silent in `/wrap-insights`. Schema bump is the cleanest fix. |

## Risk Mitigations (R1–R3 must be in plan per risk analysis)

| Risk | Mitigation in this plan |
|------|------------------------|
| R1 — Resolver SPOF | (a) `RESOLVE_PERSONAS_BYPASS=1` env var documented in `docs/budget.md` short-circuits to pre-feature roster; (b) every external call (`codex login status`, `python3`) wrapped in `timeout 2`; (c) gate caller treats empty stdout AND non-zero exit BOTH as fallback triggers; (d) `tests/test-resolve-personas.sh` smoke-tests all three gates against fixture configs. |
| R2 — Headless silent degradation | Resolver appends one JSON line to `dashboard/data/budget-events.jsonl` on every fallback (`{ts, gate, fallback_reason, selected_count, expected_count}`). `scripts/autorun/report.sh` (or wherever the autorun completion summary is rendered) counts these lines and prints `⚠ N gate runs fell back to seed list — see budget-events.jsonl` when >0. |
| R3 — config.json corruption | All writers funnel through `scripts/lib/budget-validate.py`: validate JSON parse → validate against `schemas/budget-config.schema.json` → atomic `mktemp + mv -f` → rotate previous file to `config.json.bak`. Schema includes `schema_version: 1`. `install.sh --reconfigure-budget` detects corruption and offers `.bak` restore. |
| R4 — Stale persona files | Resolver `test -f "$persona_file"` for every emitted persona name; misses skip with stderr warning and fill from next ranked/seed candidate. |
| R5 — Stale rankings file | `rankings_mtime_days` in resolver output. Banner shows `(rankings stale: Nd)` when ≥14 days. Stderr warning when ≥30 days. |
| R6 — Defaults drift | `scripts/resolve-personas/seeds.json` is the canonical source for budget default, ceiling, per-gate seed lists, and budget=1 fallbacks. `docs/budget.md` says "see seeds.json" rather than re-stating values. `tests/test-defaults-consistency.sh` greps install.sh + docs and asserts they reference seeds.json or match its values. |
| R7 — install.sh idempotency | Skip Q&A when `config.json` exists AND `schema_version` matches installer's expected version. On mismatch, run a migration prompt. `tests/test-install-idempotent.sh` runs install.sh twice and asserts second run is a no-op on config.json. |
| R8 — Banner becomes accidental contract | `docs/budget.md` documents the banner format as stable, and `dashboard/data/budget-events.jsonl` is offered as the structured downstream target. |

## Implementation Tasks

> ⚠ **MF1 — NEEDS REWORK BEFORE BUILD:** Tasks #4 and #15 must not be executed as written.
> - **Task #4** (`schemas/participation.schema.json` v1→v2 bump): breaks every existing `participation.jsonl` row repo-wide — `additionalProperties: false` already conflicts with rows containing `prompt_version`/`verdict` fields. The D10 contamination problem it solves (budget-dropped personas flagging as drift) should instead be a 3-line addendum to `.claude/agents/persona-metrics-validator.md`: "before flagging a persona at 0%, cross-check `dashboard/data/budget-events.jsonl`; if `dispatch_status == budget-dropped`, exclude." No schema bump needed.
> - **Task #15** (`scripts/autorun/report.sh` update): that file does not exist. Verified: only `autorun, build.sh, check.sh, defaults.sh, notify.sh, plan.sh, risk-analysis.sh, run.sh, spec-review.sh, verify.sh` are present. Task needs a real target file before build can proceed.
> Fix these before starting Wave 1. See `queue/account-type-agent-scaling/check.md` MF1 for full detail.

Five waves. Wave 1 (data + canonical sources) blocks everything; Wave 2–3 (resolver + integrations) can parallelize; Wave 4 (docs) parallelizes with Wave 3; Wave 5 (verification) runs last.

| # | Task | Wave | Depends On | Size | Parallel? |
|---|------|------|-----------|------|-----------|
| 1 | Create `scripts/resolve-personas/seeds.json` (canonical defaults: budget=6, ceiling=8, per-gate seed lists per D1, budget=1 fallbacks per gate). Use D1's plan seed: `wave-sequencer, security, integration, api, data-model, scalability, ux`. | 1 | — | S | — |
| 2 | Create `schemas/budget-config.schema.json` (draft 2020-12, `schema_version`, `agent_budget`, `persona_pins`, additionalProperties:false). | 1 | — | S | Yes (with #1) |
| 3 | Create `scripts/lib/budget-validate.py` (parse → schema-validate → atomic write with `.bak` rotate). Used by all three writers (R3). | 1 | 2 | M | — |
| 4 | Migrate `schemas/participation.schema.json` to `schema_version: 2`, add `dispatch_status` enum (D10). Update `validate-personas.py` and emit prompt(s) under `commands/_prompts/findings-emit.md`. | 1 | — | M | Yes (with #1, #2) |
| 4a | **[MF6]** Capture pre-feature stdout baseline for all three gates into `tests/fixtures/baseline/{spec-review,plan,check}.stdout` from the parent commit (before Wave 3 lands). `tests/test-resolve-personas.sh` diffs against these in the no-config case to verify AC #1 byte-identity. Must run before Wave 3 modifies any gate command. | 1 | — | S | Yes (with #1, #2, #4) |
| 5 | Implement `scripts/resolve-personas.sh`: bash 3.2 compatible; calls `python3` for JSON I/O (per MEMORY entry I1); reads `$HOME/.config/monsterflow/config.json` + `dashboard/data/persona-rankings.jsonl` + `seeds.json`; **[MF3] bypass check is the literal first executable line** after arg-parse: `if [[ "${RESOLVE_PERSONAS_BYPASS:-0}" == "1" ]]; then emit_pre_feature_roster "$1"; exit 0; fi` — no python3 call, no file read, no seeds.json parse before this; **[MF2]** honors `$MONSTERFLOW_CODEX_AUTH_CACHED` when pre-set (0 or 1) — skips its own `codex login status` call; falls back to `command -v codex && timeout 2 codex login status` only when the var is unset; runs algorithm D3; emits JSON-to-stdout per D8; writes fallback line to `dashboard/data/budget-events.jsonl` (R2); per-persona `test -f` (R4); rankings mtime emitted (R5). | 2 | 1, 2 | L | — |
| 5b | **[MF2]** Update `scripts/autorun/run.sh`: after existing pre-flight, run `command -v codex && timeout 5 codex login status >/dev/null 2>&1 && export MONSTERFLOW_CODEX_AUTH_CACHED=1 || export MONSTERFLOW_CODEX_AUTH_CACHED=0` once in the parent shell before any stage fork. All stage child shells inherit the exported var; resolver skips its own check. Add a fixture test asserting resolver makes zero `codex login status` calls when var is pre-set. | 2 | — | S | Yes (with #5) |
| 6 | Write `tests/test-resolve-personas.sh`: fixture configs (no-config, budget=1, budget=3, budget=8, pins, missing rankings, stale rankings, codex-on, codex-off, corrupted config, persona file missing, bypass env var). Use PATH-stub mocking for `codex` (per MEMORY: PATH-stub > export -f). Assert JSON shape of stdout. **[MF7]** Include explicit fixture `plan-codex-on-must-be-additive-false`: invoke `resolve-personas.sh plan` with `MONSTERFLOW_CODEX_AUTH_CACHED=1` and assert `codex_additive: false` in output — Codex is never dispatched at `/plan` regardless of auth (D6). | 2 | 5 | L | Yes (with #5 wave) |
| 7 | Wire #6 into `tests/run-tests.sh` explicitly (per MEMORY: orchestrator wiring gap). Add `tests/test-defaults-consistency.sh` and `tests/test-install-idempotent.sh` to the orchestrator at the same time. | 2 | 6 | S | — |
| 8 | Modify `commands/spec-review.md` pre-flight: call `bash scripts/resolve-personas.sh spec-review`, parse JSON, dispatch only `selected[]` Claude personas + Codex (when `codex_additive==true`), print Selected/Dropped banner unless `banner_suppressed==true` (D5). | 3 | 5 | M | — |
| 9 | Modify `commands/plan.md` pre-flight: same as #8 but for `plan`; resolver omits codex per D6 — gate dispatches only selected Claude personas. | 3 | 5 | M | Yes (with #8) |
| 10 | Modify `commands/check.md` pre-flight: same as #8 but for `check`. | 3 | 5 | M | Yes (with #8, #9) |
| 11 | Add `install.sh` budget Q&A block + `--reconfigure-budget` flag handler. Calls into `scripts/lib/budget-validate.py` (#3). Skip-on-existing-schema-match per R7. Single `[Y/n]` short-circuit for "use defaults" per I12. Pro path defaults to 3, non-Pro to 6 (resolves I8 by treating Pro answer as a budget *hint*, not an override of D5/D9). Reject ≤0; warn-and-cap at 8. Use `${VAR/#\~/$HOME}` for tilde expansion (per MEMORY entry on tilde expansion). | 3 | 3 | L | Yes (with #8–#10) |
| 12 | Create `docs/budget.md`: schema, valid values, defaults (linked to `seeds.json`), per-gate seed lists, Codex rule (only at spec-review/check, additive, never counted), three reset paths, banner format pinned, tradeoffs at budget=1, `RESOLVE_PERSONAS_BYPASS=1` documented, stale-rankings warning behavior, `XDG_CONFIG_HOME` not honored note. | 4 | 1 | M | Yes (with Wave 3) |
| 13 | Update `QUICKSTART.md` "Agent Budget" section: 1-paragraph summary, link to `docs/budget.md`. Update README to defer fixed-persona-count claims (per O9). **[MF8] Sequential after #12** — cannot run parallel with #12 since it links to `docs/budget.md` which #12 creates. | 4 | 12 | S | No — after #12 |
| 14 | **[MF5]** Add a "Tell Claude to reconfigure" prompt artifact at `commands/_prompts/budget-qa.md` and document the trigger phrase ("reconfigure my agent budget") in `docs/budget.md`. AC #11 is **docs-existence only** — verification is: (a) `commands/_prompts/budget-qa.md` exists, (b) `docs/budget.md` contains the trigger phrase. No behavioral end-to-end test required. | 4 | 11 | S | Yes (with #12, #13) |
| 15 | Update `scripts/autorun/report.sh` (or equivalent autorun completion-summary script) to count `budget-events.jsonl` fallback lines for the run window and surface a yellow flag (R2). | 4 | 5 | S | Yes (with Wave 3) |
| 16 | Update `commands/_prompts/findings-emit.md` and `commands/_prompts/snapshot.md` (only if needed) so emitted `participation.jsonl` rows include `dispatch_status` per D10. Update `persona-metrics-validator` subagent doc (`.claude/agents/persona-metrics-validator.md`) to know about the new field. | 4 | 4 | M | Yes (with Wave 3) |
| 17 | Run `bash tests/run-tests.sh` end-to-end. Validate each AC against fixture data. Run `/preship` skill to confirm typecheck/git status. Then run a real `/spec-review` against this very plan as smoke (dogfood the resolver). | 5 | 7, 8, 9, 10, 11, 16 | M | — |

**Wave parallelism:** Wave 1 = #1, #2, #4 in parallel; #3 follows #2. Wave 2 = #5 alone (large), #6 starts when #5 stabilizes; #7 follows #6. Wave 3 = #8/#9/#10/#11 all in parallel after #5 + #3. Wave 4 = #12/#13/#14/#15/#16 all in parallel. Wave 5 = #17 sequentially.

## Acceptance Criteria (with plan-level revisions)

Original spec has 14 ACs. The plan revises three to absorb design decisions:

- **AC #1 (D5):** *"`config.json` absent or `agent_budget` unset → gate produces byte-identical stdout to pre-feature behavior (no banner, full pre-feature roster, no banner suppression message)."*
- **AC #4 (D6):** *"Codex authenticated AND gate is `/spec-review` or `/check` → codex-adversary is added in addition to budget count. At `/plan`, codex-adversary is never dispatched regardless of auth state."*
- **AC #7 (D4):** *"Resolver script error (interactive) → recovery prompt with exactly two options: (1) reconfigure now, (2) continue with seed list. Both options dispatch a budget-respecting roster; full-roster restore requires the documented `RESOLVE_PERSONAS_BYPASS=1` env var."*
- **AC #11 (MF5 — revised):** *"`commands/_prompts/budget-qa.md` exists AND `docs/budget.md` contains the trigger phrase 'reconfigure my agent budget'. Documentation-existence test; no behavioral end-to-end test required.*"

New ACs from the plan:

- **AC #15:** Resolver stdout is valid JSON matching the contract in D8; consumers parse with `python3 -c 'import json'`.
- **AC #16:** Every fallback writes one row to `dashboard/data/budget-events.jsonl`; autorun report surfaces count.
- **AC #17:** `participation.jsonl` rows for budget-dropped personas have `dispatch_status: "budget-dropped"`; `/wrap-insights` Phase 1c excludes them from drift calculations.
- **AC #18:** `RESOLVE_PERSONAS_BYPASS=1` env var causes the resolver to emit the pre-feature roster regardless of config.

ACs #2, #3, #5, #6, #8–#14 carry over from spec unchanged. AC #14 ("All three gates produce consistent behavior from the same resolver script") is kept (per O1 it is partially redundant but reads as a useful invariant).

## Open Questions

**[MF4 — resolved inline, not deferred to build]**

- **Q1 — RESOLVED:** `dispatch_status: "budget-dropped"` rows should **not** count toward `findings_emitted` math — exclude from both numerator and denominator (persona had no opportunity to emit). Moot if MF1 rework removes Task #4's schema bump entirely; if Task #4 is ultimately kept, add a one-line filter to `compute-persona-value.py` and `validate-personas.py`.
- **Q2 — RESOLVED:** Pro/non-Pro answer **affects the default only; not persisted** in `config.json`. No `claude_plan` key. Storing it has no current consumer and would drift out of sync with actual plan changes.

## Risks (top 3, surviving the plan's mitigations)

1. **Resolver-pipeline coupling stays high even after R1 mitigations.** A subtle JSON-shape regression in `resolve-personas.sh` still propagates to all three gates. Mitigation: smoke test (#6) covers all three gates from one fixture; the bypass env var is the second safety net.
2. **`participation.jsonl` schema bump (D10) is a breaking change for any out-of-tree consumer.** None known, but `dashboard/data/*.jsonl` is the source for `/wrap-insights` and `persona-metrics-validator`. Mitigation: schema_version field already exists per spec; bump from 1 → 2 with a one-pass migration in task #4 and update both consumers in task #16.
3. **install.sh adopter-vs-owner detection (existing MEMORY entry).** New Q&A block must NOT prompt owners (Justin) on routine `install.sh` re-runs. Mitigation: schema_version match check (R7) is the gate, and `tests/test-install-idempotent.sh` enforces it.

## Out of Scope (carried from spec, restated)

- Auto-detection of Claude account tier from any CLI/API surface.
- Per-plugin cost measurement / plugin scoping.
- Roster pruning or auto-removal of low-ranking personas.
- Per-project config overrides.
- Linux support (macOS-only in v1; install.sh on Linux skips the Q&A and writes no config — see I14, resolved by `if [[ "$OSTYPE" != darwin* ]]; then skip; fi` in #11).
- Codex-additive at `/plan` (D6 — deferred until schema supports Codex-at-plan).

## Build Notes

- Test orchestrator wiring (#7) is a top priority — there's a recurring MEMORY entry about parallel `/build` agents writing tests but forgetting `tests/run-tests.sh`. Make this an explicit task assigned to a single agent.
- All path writes use `"$HOME/.config/monsterflow/..."` (no literal `~`); all writes use `mktemp + mv -f`.
- All `cat <<EOF` patterns avoided in favor of `python3 -c` for JSON output (per the heredoc-stdin-collision MEMORY entry).
- `bash 3.2` constraint: no `${var,,}`, no associative arrays, no `mapfile`. Use `awk`/`python3` for any non-trivial parsing.
- Persona file existence checks (R4) cover the case where a persona name in `seeds.json` doesn't have a corresponding `personas/<gate>/<name>.md` file — this is also an early-warning for D1-style config drift.
- **[MF2]** `MONSTERFLOW_CODEX_AUTH_CACHED` is exported **once at `run.sh` startup** (Task #5b) before any stage fork — child `bash <stage>.sh` processes inherit it. The resolver checks this env var first and skips its own `codex login status` call when pre-set. Do NOT set it inside a stage script (it won't survive to the next stage). The resolver's own check is the fallback for interactive sessions only.

## Ready for /check

Plan is consistent with the resolved spec-review blockers (B1–B10) and incorporates all three high-severity risk mitigations (R1–R3) into named tasks. Five-wave structure preserves data-contract precedence (data → resolver → integrations → docs/metrics → verification). All 14 original spec ACs plus 4 new plan ACs are testable.
