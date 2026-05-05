# Check — account-type-agent-scaling

**Created:** 2026-05-04
**Plan:** `docs/specs/account-type-agent-scaling/plan.md` (snapshot at `check/source.plan.md`)
**Spec:** `docs/specs/account-type-agent-scaling/spec.md`
**Reviewers:** completeness, sequencing, risk, scope-discipline, testability, codex-adversary
**Mode:** autorun headless

---

## Overall Verdict: **NO-GO** — revise plan, then re-run /check

The plan's design intent is sound and the wave structure is well-shaped, but two **file-grounded errors** in the resolver pseudocode will fail acceptance criteria on day one — the same class of bug the spec review caught with the missing `risk` persona in `/plan` (B1). Codex independently verified both against the live repo. Until these are corrected in the plan (not just acknowledged), `/build` would produce a resolver that emits no personas for one of the three gates and crashes on a nonexistent ranking field.

A third blocker (participation schema v2 has `additionalProperties: false`) makes D19's "back-compat with v1 readers" claim structurally impossible without an explicit migration step. Five Claude reviewers each flagged 2–4 Must-Fix items that, in aggregate, expose the plan's "Low-Medium" residual risk claim as optimistic.

---

## Reviewer Verdicts

| Dimension | Verdict | Key Finding |
|---|---|---|
| Completeness | PASS WITH NOTES | AC #11 ("tell Claude to reconfigure") has no discoverable trigger surface; `config.json` gitignore touched by no task |
| Sequencing | PASS WITH NOTES | SP1–SP3 spec patches have no scheduled task ID; T5.3 marked parallel with its own dependencies |
| Risk | PASS WITH NOTES | python3-missing path undefined (D1); `MONSTERFLOW_BUDGET_SNAPSHOT` env-var lifecycle leaks across sessions; participation v2 reader-resilience claim is not test-backed |
| Scope discipline | PASS WITH NOTES | Wave 4 autorun snapshot mechanism (D14, T4.1/T4.3/T4.5) is heavy for an R14-rated Low risk; ~1 session of cuttable scope |
| Testability | PASS WITH NOTES | `install.sh --reconfigure` round-trip (AC #10) has no test task; banner contract (D25) not parser-tested; 6/14 ACs partial coverage, 2/14 outright gap |
| **Codex adversarial** | **DO NOT BUILD AS WRITTEN** | Resolver references nonexistent `score` field; gate-to-directory mapping wrong (`spec-review`→`review`); participation schema v2 violates `additionalProperties:false` |

**Consolidated:** 5 of 5 Claude reviewers PASS WITH NOTES; Codex returns hard FAIL with three file-grounded blockers verified against the live repo. Net verdict: **NO-GO** — Codex's blockers cannot be deferred to /build because they invalidate the plan's central pseudocode.

---

## Must Fix Before Building (10 items)

### MF1. Resolver pseudocode sorts on a `score` field that does not exist
**Source:** Codex (verified). `schemas/persona-rankings.allowlist.json:21` exposes only `judge_retention_ratio`, `downstream_survival_rate`, `uniqueness_rate`, `avg_tokens_per_invocation`, and `insufficient_sample`. There is no composite `score` (token-economics spec explicitly calls this out). Plan §1 pseudocode `key=lambda r: (r.score, -r.insufficient_sample_weight)` cannot run.
**Fix:** Replace D-section pseudocode with an explicit ordering using existing fields. Recommended: lexicographic `(downstream_survival_rate desc, uniqueness_rate desc, avg_tokens_per_invocation asc)` with explicit null/missing handling. Resolves before any T1.1 work begins. Or take the harder path: add a `selection_score` to token-economics and gate this feature on that schema bump.

### MF2. Persona directory mapping wrong for `/spec-review`
**Source:** Codex + scope-discipline (verified). `scripts/_roster.py:35` defines the canonical mapping `_DIR_TO_GATE = {"review": "spec-review", "plan": "plan", "check": "check"}`. The plan's D2 + §1 pseudocode says "walk `personas/<gate>/*.md`" — for the `spec-review` gate that path is `personas/spec-review/` which does not exist. The resolver would emit zero personas for the entire spec-review gate, tripping D16's empty-stdout guard and falling back to seed-only on every run.
**Fix:** Reuse `_roster.py`'s `_DIR_TO_GATE` (or extract it to `scripts/resolve-personas/_lib.py` so the resolver and `_roster.py` share one source). T1.1 must read from the gate-mapped directory, not the gate name. Add a fixture in T1.4 that asserts `spec-review` returns ≥1 persona.

### MF3. Participation schema v2 violates `additionalProperties: false`
**Source:** Codex + risk + testability (verified). `schemas/participation.schema.json:1` declares `additionalProperties: false` and `schema_version: const 1`. Adding `dispatch_pool[]` and `roster_size_total` rejects every new row at validation time unless schema_version bumps to 2 and every reader is updated atomically. The plan calls v2 fields "optional in schema v1 readers" — that is structurally wrong; v1 readers refuse the rows entirely.
**Fix:** Two viable paths. (a) Cut D19 from v1; emit dispatch context to `dashboard/data/budget-events.jsonl` (D17) only and teach `persona-metrics-validator` to consult that sidecar. (b) Bump `schema_version` to 2 in T0.2, update every reader in the same PR (Phase 1c renderer, validator subagent, dashboard render path), add a mixed-history fixture test. Option (a) is recommended — it removes the migration burden without losing the longitudinal-comparability gain Codex flagged as deferrable.

### MF4. AC #11 ("tell Claude to reconfigure") has no callable trigger surface
**Source:** completeness. T3.3 builds `commands/_prompts/budget-qa.md` (the prompt body) but no task creates a slash command file or documents the trigger phrase. Without one, AC #11 is unverifiable end-to-end.
**Fix:** Add T3.3a — author `commands/reconfigure-budget.md` (or document the canonical trigger phrase + add a one-line invocation pattern to QUICKSTART.md and docs/budget.md). Wire it to call the same `_lib.py` validators install.sh uses.

### MF5. Spec patches SP1–SP3 have no scheduled task ID
**Source:** sequencing. Plan §7 lists three required spec edits ("can land in the same commit as Wave 0") but no T0.* task owns them. T0.3 contradicts unpatched spec.md until SP1 lands; T1.4 fixtures encode unpatched AC #1 until SP2 lands; T3.4 recovery options contradict spec UX option (3) until SP3 lands.
**Fix:** Add T0.0 — apply SP1/SP2/SP3 to spec.md in the same commit as T0.3, before any other Wave 0 work. Sequencing enforces "spec is the source of truth before code reads from it."

### MF6. python3-missing / wrong-version failure path is undefined
**Source:** risk. D1 says "Python 3.9+ is already required by MonsterFlow" but the resolver becomes the first pre-flight Python invocation in every gate. On a stock macOS box without Homebrew python (system python3 is 3.9 from Xcode), or a misconfigured PATH, the bash wrapper T1.2 fires `python3 resolver.py` and the gate dies with a stack trace. No fallback path. The MEMORY entry on Homebrew vs system Python warns this is real on Justin's machine.
**Fix:** T1.2 wraps the Python invocation with: (a) `command -v python3` short-circuit + recorded fallback to "full disk roster" with stderr warning + budget-events row, (b) `timeout 10` ceiling, (c) version sniff that prints a clear "MonsterFlow requires python3 ≥ 3.9" message rather than letting the resolver crash. T1.4 adds a "PATH=/empty" fixture asserting the gate completes with full roster and a logged event.

### MF7. `MONSTERFLOW_BUDGET_SNAPSHOT` and `MONSTERFLOW_CODEX_AVAILABLE` lifecycle is unspecified
**Source:** risk + Codex. `scripts/autorun/run.sh` invokes stage scripts as separate child shells. Env vars set inside one stage script do not persist to the next without explicit `export` in the parent. Snapshot files have no cleanup → next interactive session in the same shell reads a stale snapshot and dispatches the previous run's budget. D14's protection only fires if the env var is set; absent the env var, resolver reads live config (correct for interactive but only by coincidence).
**Fix:** T4.1/T4.2 set env vars in the autorun **wrapper** (parent), `export` them, and `unset` + `rm -f` snapshot file on exit (trap EXIT). Add a complementary `MONSTERFLOW_AUTORUN_ACTIVE` sentinel; resolver's `_lib.py` only honors `MONSTERFLOW_BUDGET_SNAPSHOT` when the sentinel is also present. Test in T1.4 with a fixture that exports the snapshot var without the sentinel and asserts live config is read.

### MF8. Gate command edits T2.1/T2.2/T2.3 are prompt-template changes, not script integrations
**Source:** Codex + risk. `commands/spec-review.md`, `plan.md`, `check.md` are natural-language prompts the model interprets. "Parse JSON, dispatch selected personas, hard-error on `len < 1`, fall back on resolver non-zero" is *prompt behavior*, not a shell call — three near-identical edits across three large prompts is fragile; drift between them is guaranteed.
**Fix:** Add T2.0 — author `commands/_prompts/_resolve-persona-dispatch.md`, the single canonical fragment all three commands include verbatim. T2.1/T2.2/T2.3 then become one-line `{{include}}` edits. Add a text-lint test that asserts all three commands include the fragment. (This was scope-discipline's "one-line `{{include}}`" point; Codex independently flagged it.)

### MF9. Bypass env var (D15) conflicts with observability promise (D17/T4.3)
**Source:** Codex. The plan says `MONSTERFLOW_RESOLVE_PERSONAS_BYPASS=1` "skips resolver entirely." But T4.3 expects every gate run to leave a `budget-events.jsonl` trail; bypass produces silence indistinguishable from "feature off." A user who sets bypass for a debug session and forgets has no way to audit it.
**Fix:** Bypass should still emit a single-line `budget-events.jsonl` row with `fallback_reason: "bypass_env"` before short-circuiting. Update T1.1 spec accordingly. Add a T1.4 fixture asserting the row appears.

### MF10. `tests/run-tests.sh` orchestrator wiring gap for `install.sh --reconfigure` and codex-cache tests
**Source:** testability + Codex. T1.5 wires `tests/test-resolve-personas.sh`; T5.3 wires `tests/test-defaults-consistency.sh`. But the plan never creates or wires `tests/test-install-reconfigure.sh` (covering AC #10 round-trip, R7 idempotency, R3 `.bak` corruption recovery) or any test for codex-cache lifecycle (D12 / MF7). Per the MEMORY entry on the orchestrator-wiring gap, this is a recurring drift mode.
**Fix:** Add T3.5 — author `tests/test-install-reconfigure.sh` covering AC #10 (round-trip), R7 (idempotent re-install), R3 (.bak corruption restore), D24 (schema_version migration prompt). Wire into `tests/run-tests.sh`. Add T2.5a — extend `tests/test-resolve-personas.sh` with codex-cache lifecycle cases (cached false → user authenticates → cache stays false; missing binary → cache false; timeout → cache false).

---

## Should Fix (12 items)

- **SF1.** AC #7/AC #8 recovery prompt (T3.4) has no fixture; behavior is asserted but not test-covered. (testability)
- **SF2.** Gate-side empty-stdout guard (D16) tested only resolver-side; gate caller's `len < 1` check has no test. (testability)
- **SF3.** Banner format (D25) documented as "stable contract" but not parser-tested. Add a regression test that the literal format `Selected: a, b, c | Dropped: d, e | Codex: yes` survives. (testability)
- **SF4.** budget-events.jsonl emit (D17/T1.1) not enumerated in T1.4's 18 test cases. (testability)
- **SF5.** `MONSTERFLOW_CODEX_AVAILABLE` cache staleness on mid-session `codex login`: positive-cache only (re-check if cached false), or document the staleness window. (risk)
- **SF6.** T1.4 missing R2 silent-degradation fixtures: malformed rankings row, empty personas dir, unwritable `dashboard/data`, concurrent jsonl appends, truncated `config.json`. (risk)
- **SF7.** `MONSTERFLOW_RESOLVE_PERSONAS_BYPASS` (D15) has no audit trail in T4.3's autorun report → "0 fallbacks" can be misleading when bypass is active. (risk)
- **SF8.** T3.3's "tell Claude to reconfigure" trust boundary: Claude can bypass `_lib.py` validators via direct Write/Edit and corrupt config; D13's `.bak` rotation can overwrite the last good backup with a corrupt one. Add a 2-deep `.bak` rotation. (risk)
- **SF9.** `qualifies(r)` weighting for `insufficient_sample` rankings rows (Q3 in plan): pseudocode says 0.5x weight, but the field on the row is bool (`insufficient_sample`). Specify the deprioritization mechanism explicitly given the actual schema. (risk + Codex MF1)
- **SF10.** No spec AC for the `agent_budget=8` ceiling (review explicitly flagged). Either add an AC or document that the ceiling is enforced by config validation only. (completeness)
- **SF11.** Resolver-absent (vs error/bypass) fallback for gate commands has no plan task — what happens if `scripts/resolve-personas.sh` itself is missing? (completeness)
- **SF12.** Three sequencing nits: T3.4 missing deps on T2.5 + T0.4; T2.5 wave-2 placement could move to end-of-Wave-0; T1.5 ↔ T5.3 same-file collision on `tests/run-tests.sh` needs a one-line note. (sequencing)

---

## Cut Candidates (scope discipline)

- **CC1. T4.1 + T4.3 + T4.5** (autorun snapshot, autorun report yellow-flag, validator rule update) — heavy mechanism for R14-rated Low risk. ~1 session saved. *Recommended cut.*
- **CC2. T2.5 `_codex_check.md` extraction** — 4-line check; T4.2 (or its replacement) handles the env-var cache. Inline in each gate command instead.
- **CC3. D17 `budget-events.jsonl`** — has no v1 consumer if T4.3 is cut. *But* MF9 + Codex MF7 both require this exact sidecar to address bypass audit trail and (per MF3) participation context. *Keep — promote to canonical observability surface in lieu of participation v2.*
- **CC4. D25 banner-as-stable-contract** — locks UX format on day one for no concrete consumer; ship as iterable UX with versioning. (Q5 should be answered "no, don't lock.")
- **CC5. T2.4 emit logic for participation v2** — depends on MF3 resolution. If option (a) (defer), T2.4 disappears entirely.

---

## Accepted Risks (proceed knowing these are unmitigated in v1)

- **R5 stale rankings** — D18's mtime warning is the only mitigation. Acceptable for v1.
- **R8 banner becomes accidental contract** — accepted by adopting CC4 (don't lock the format).
- **R11 pin ossification** — pin-drift detection deferred to v1.1. Mitigated by Q4 default of "no pins at install."
- **R13 insufficient_sample starves rankings on low-traffic gates** — partially addressed by SF9; full handling depends on MF1 ordering decision.

---

## Codex Adversarial View (additive findings)

Codex returned **DO NOT BUILD AS WRITTEN** with seven concrete blockers, three of which are the highest-confidence findings in this checkpoint because they're verified against live repo files:

1. **No `score` field exists** — plan pseudocode references it; rankings allowlist (`schemas/persona-rankings.allowlist.json:21`) does not. → **MF1**
2. **Persona path mapping wrong** — `scripts/_roster.py:35` proves `personas/review/` → gate `spec-review`. Plan walks `personas/<gate>/*.md`. → **MF2**
3. **Participation schema v2 violates `additionalProperties:false`** — `schemas/participation.schema.json:1`. → **MF3**

Codex also surfaced four softer blockers that align with Claude reviewers' concerns:
4. Gate integration is a prompt-template change, not a script call → **MF8**
5. Autorun env-var caching crosses child-shell boundaries → **MF7**
6. install.sh / `--reconfigure` testing is one-task-too-thin → **MF10**
7. Bypass conflicts with observability → **MF9**

Codex's recommended scope cut for v1: **resolver + config + gate dispatch only**; defer participation schema v2 (matches MF3 option (a)); use budget-events.jsonl as the only new runtime observability surface (matches CC3 keep + CC1 cut). This converges with scope-discipline's recommendations.

---

## Agent Disagreements Resolved

- **Wave 4 scope** — scope-discipline argued cut T4.1/T4.3/T4.5 for ~1 session savings; risk argued the autorun snapshot (D14, T4.1) is the *only* mitigation for R14 (mid-autorun reconfigure). → **Resolution: cut T4.1 partially.** Snapshot at autorun start is cheap (D14 is 5 lines) and addresses R14; the *report aggregation* (T4.3) and *validator rule update* (T4.5) are the deferrable pieces. Net: keep snapshot mechanism, cut report+validator polish to v1.1. (Codex independently recommended "do not add autorun report aggregation in v1.")
- **Participation schema v2** — risk + testability flagged the back-compat claim as untested; Codex flagged it as structurally invalid (`additionalProperties: false`). → **Resolution: Codex wins** because the structural claim is verified against the schema file. MF3 option (a) defers the change entirely.
- **`_codex_check.md` extraction (T2.5)** — risk argued it's needed for centralization; scope-discipline argued it's 4 lines and inlinable (CC2). → **Resolution: scope-discipline wins** if MF8's `_resolve-persona-dispatch.md` fragment lands (codex check goes inside that fragment, single source of truth). If MF8 is rejected, T2.5 stays.
- **`/plan` Codex additivity (D7, plan Q1)** — Codex did not contest the "spec-review + check only in v1" scoping. Risk and scope-discipline both accepted it. → **Resolution: confirm D7 as written.** Q1 → "v1 = spec-review + check only."

---

## Required Plan Revisions Before Re-Check

The plan author should land the following before re-running `/check`:

1. **Rewrite §1 pseudocode** to use real persona-rankings fields (MF1). Pick an ordering and document null/missing handling.
2. **Replace `personas/<gate>/*.md` with the `_DIR_TO_GATE` mapping** in D2, §1 pseudocode, T1.1, and T1.4 fixtures (MF2). Reuse `scripts/_roster.py`'s mapping.
3. **Cut D19 / T2.4** and route dispatch context exclusively through `budget-events.jsonl` (MF3 option (a)). Update DoD §9 and Codex-additive view in §6 (B10) accordingly.
4. **Add T0.0** to apply SP1/SP2/SP3 to spec.md as the first task in Wave 0 (MF5).
5. **Add T2.0** for `commands/_prompts/_resolve-persona-dispatch.md` shared fragment; rewrite T2.1/T2.2/T2.3 as include-only edits (MF8).
6. **Add T3.3a** for `commands/reconfigure-budget.md` slash-command surface (MF4).
7. **Add T3.5** for `tests/test-install-reconfigure.sh` covering AC #10 + R7 + R3 + D24, wired into `tests/run-tests.sh` (MF10).
8. **Specify env-var lifecycle** in T4.1/T4.2 (set in parent wrapper, export, unset/cleanup on exit, sentinel-gated read in `_lib.py`) (MF7).
9. **Specify python3 fallback path** in T1.2 (`command -v` short-circuit, version sniff, full-roster fallback with logged event) (MF6).
10. **Specify bypass observability** in D15 / T1.1 (emit one-line budget-events row before short-circuiting) (MF9).

After these land, the plan is structurally executable. Re-run `/check` to re-validate completeness/sequencing/risk against the revised plan.

---

## Consolidated Verdict

**0 of 6 reviewers PASS** (5 PASS WITH NOTES, 1 FAIL/Codex). **NO-GO** — three Codex blockers (MF1, MF2, MF3) are file-grounded errors that invalidate the resolver pseudocode and one schema claim; deferring them to /build would produce a resolver that crashes on the first gate. Revise the plan per the 10-item revision list above and re-run `/check`. Estimated revision effort: ~2–3 hours of plan editing; no additional design questions to answer except Q5 (banner lock — recommend "no").

---

*Checkpoint complete. autorun headless mode — no approval prompt requested. Stopping per instructions.*
