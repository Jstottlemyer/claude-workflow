# Plan: Token Economics

**Date:** 2026-05-04
**Spec:** `docs/specs/token-economics/spec.md` revision 4
**Review:** `docs/specs/token-economics/review.md` (round 3)
**Survival:** `docs/specs/token-economics/spec-review/survival.jsonl` — 29/32 round-3 findings addressed by v3→v4 revision (90.6%); 2 not_addressed (TTL, Pro-friend A12 enforcement); 1 rejected_intentionally (persona-author docs)
**Designers:** 7 in parallel — api / data-model / ux / scalability / security / integration / wave-sequencer

## Architecture Summary

`compute-persona-value.py` is a single Python script that walks two trees, computes `persona-rankings.jsonl`, and emits `persona-roster.js` + `persona-rankings-bundle.js` sidecars so the dashboard can render under `file://` without `fetch()`. All output flows through one allowlist schema (`schemas/persona-rankings.allowlist.json`) with `additionalProperties: false` as the privacy gate. All stderr/stdout flows through one `safe_log()` helper restricted to a fixed `SAFE_EVENTS` enum. `commands/wrap.md` Phase 1c invokes the script unconditionally (not piggybacked on `dashboard-append.sh`); the dashboard adds a third top-level "Persona Insights" mode tab. Phase 0 spike Q1 is forced by A1.5 in tests; everything else is best-effort by design.

**Mental model:** the spec is one engine + one schema + one logger + one bundle pattern, with the dashboard as a passive renderer.

## Key Design Decisions

### Decisions where designers converged (no debate)

1. **Single allowlist file as both row schema and privacy gate** (data-model + security + integration). One file `schemas/persona-rankings.allowlist.json` with `additionalProperties: false`. A10 = `jsonschema.validate(row, schema)` per emitted line. No separate "schema" vs "allowlist" split.
2. **Sidecar bundle pattern under `file://`** (ux + integration + data-model). `persona-roster.js` and `persona-rankings-bundle.js` both loaded via `<script src>` setting `window.PERSONA_ROSTER` and `window.__PERSONA_RANKINGS`. No `fetch()`. **`compute-persona-value.py` emits both.** Spec only mentioned the roster sidecar; we extend the same pattern to the rankings JSONL.
3. **`safe_log()` enforces output-side privacy** (api + security). All stderr/stdout flows through one helper restricted to a fixed `SAFE_EVENTS` enum + value-pattern allowlist. Raw `print()` and `sys.stderr.write()` banned by grep test.
4. **mtime-pruned single-pass with substring pre-filter** (scalability solo). Stdlib only. Substring screen for `"Agent"` + `"tool_use"` before `json.loads`. mtime-prune horizon = `MIN(window.created_at) - 24h` slack. Light adopter <2s; heavy adopter 3-5s; cold first-run 30-60s with stderr warning.
5. **Wave 0 / 1 / 2 / 3** (wave-sequencer). Spike close + schemas (Wave 0) → engine + privacy gates (Wave 1) → dashboard + wrap text (Wave 2, parallel) → end-to-end acceptance (Wave 3). Privacy ships **with** the engine, not deferred.
6. **Use `null`, never omit** for missing rates (data-model). Schema types rates as `["number", "null"]` with `[0,1]` constraint when number. Idempotent diffs stay clean; dashboard branches on `=== null` only.
7. **Reserve forward-compat via `schema_version: 1`** (data-model). v1.1 (per-dispatch hash + `agent_tool_use_id`) bumps to 2; v1 readers skip rows with `schema_version > KNOWN_MAX`. **Do NOT pre-reserve future field names** (invites confusion).
8. **`run_state` enum + `run_state_counts` aggregate** (data-model + spec). 6-key required object on every row. Sum equals `runs_in_window` (A2 verifies). Dashboard renders dominant state as `.badge` with hover-tooltip showing full breakdown.

### Decisions resolving designer disagreements / spec deltas

9. **DROP `window_start_artifact_dir`** (security override on spec). The field leaks adopter's project + feature + gate names. Drop entirely (its only use was idempotency debug; `(persona, gate)` already identifies the row). Removes a column from the dashboard. **Spec delta required.**
10. **TRUNCATE `last_seen` to date-minute granularity** (security override on spec; revised from hour per Justin 2026-05-04). Full ISO with seconds is over-precise; minute is the chosen tradeoff — gives dashboard "refreshed today" UX without weakening A8 idempotency in practice (minute-precision races are rare). Round to `YYYY-MM-DDTHH:MM:00Z` in both rankings JSONL and committed fixtures. **Spec delta required.**
11. **Per-machine salt for `contributing_finding_ids[]`** (security override on spec). Generate `~/.config/monsterflow/finding-id-salt` (256-bit random, chmod 600) on first run. ID = `<gate-prefix>-sha256(salt || normalized_signature)[:10]`. Cross-machine ID stability lost — explicitly NOT a v1 feature (drill-down is machine-local). **Spec delta required.**
12. **Telemetry line is counts-only, paths are interactive-only** (security override on spec). Spec's `(sources: cwd, config, scan): <path>, <path>, ...` becomes `discovered N projects (sources: cwd:1, config:M, scan:K)` with no paths. Paths only emitted in interactive `--scan-projects-root` first-use confirmation prompt and behind `MONSTERFLOW_DEBUG_PATHS=1` env (logs to local-only `~/.cache/monsterflow/debug.log`, never gitignored). **Spec delta required.**
13. **`--scan-projects-root` requires interactive confirmation on first use** (security new). Adopter's first `--scan-projects-root <dir>` prompts: "Confirm scan of these N roots? Append to `scan-roots.confirmed`? [y/N]". Subsequent runs skip. Non-tty: refuse to scan, log `[persona-value] scan-roots not confirmed; skipping K roots`. Per-project opt-out via `.monsterflow-no-scan` sentinel file. **Spec delta required.**
14. **DO NOT modify `scripts/session-cost.py`** (integration override on spec). New `compute-persona-value.py` imports `PRICING` and `entry_cost` from `session_cost` via `sys.path` insert. Rationale: lower blast radius (existing `/wrap` Phase 1 display unaffected); cleaner test boundary; round-3 narrowing to artifact-directory aggregation removed the need for per-row attribution inside `session-cost.py`. **Flag for /check confirm.**
15. **Path-traversal + symlink-escape hardening** (security new). Shared `validate_project_root(path) -> Path | None` rejects: non-absolute, `..` after normalize, resolved path not under `$HOME` (configurable via `MONSTERFLOW_ALLOWED_ROOTS`), symlinks that escape `$HOME`. Applied to config tier 2 reader AND `--scan-projects-root` arg.
16. **6-flag CLI surface** (api). `compute-persona-value.py` exposes: `--scan-projects-root <dir>` (**repeatable; argparse `action="append"`**, locked per Q2), `--best-effort` (downgrade A1.5 disagreement to warning), `--list-projects` (dry-run discovery only), `--out PATH` (override default output path), `--dry-run` (compute but don't write), `--explain PERSONA[:GATE]` (drill-down debugging via `contributing_finding_ids`). Help text carries the cascade verbatim. **Verify each flag with `<tool> --help` smoke test before declaring shipped** (per global CLAUDE.md).
17. **API rename `last_seen` → `last_artifact_created_at`** (api). Pre-empts a future "fix to file-mtime" regression that the spec explicitly forbids. Self-documenting field name.
18. **Dashboard "Persona Insights" as a third top-level mode** (integration + ux). Matches existing `data-mode` pattern at `dashboard/index.html:70-71`. NOT a sub-tab under Judge (rankings are cross-project; Judge is per-project).
19. **Validator (`persona-metrics-validator`) fires on first JSONL creation only** (integration). Pre/post `[ -f ]` check in `commands/wrap.md` Phase 1c — 3 lines of bash. Reruns on demand only.
20. **Dashboard "Coverage" column derived from `run_state_counts`** (api + ux). Display `14/18 complete` with full breakdown in tooltip. Avoids surfacing `run_state` as a sortable peer column (meaningless rank).
21. **`/wrap-insights` text shows top + bottom 3 per dimension per gate** (ux), with "(only N qualifying)" annotation when fewer than 3 personas have `runs_in_window ≥ 3`. Always-on retention-vs-survival semantics note at end ("retention is a compression ratio, not a survival rate").

## Implementation Tasks (Wave-Ordered)

### Wave 0 — Spike close + data contracts (parallel; 2-3 subagents)

| # | Task | Depends On | Size | Parallel? |
|---|------|------------|------|-----------|
| 0.1 | Close Phase 0 spike Q1 — probe one MonsterFlow session, verify `total_tokens` annotation == `sum(usage)` from `subagents/agent-<id>.jsonl`. Write result to `plan/raw/spike-q1-result.md`. Update spec §Phase 0 Spike Result. | — | S | yes |
| 0.2 | Write `schemas/persona-rankings.allowlist.json` per data-model sketch + security overrides (drop `window_start_artifact_dir`, **minute-truncated** `last_artifact_created_at` (renamed from `last_seen`)). | — | S | yes (with 0.1, 0.3, 0.4) |
| 0.3 | Write `scripts/redact-persona-attribution-fixture.py` (single-purpose, bound to allowlist schema). | 0.2 | S | yes (with 0.1, 0.4) |
| 0.4 | Build `tests/fixtures/cross-project/` — two synthetic project trees, each with `docs/specs/<f>/{spec-review,plan,check}/{findings,survival,run.json,raw/<persona>.md}`. Designed so ≥1 (persona, gate) pair has ≥3 qualifying rows AND ≥1 has only 1 (so A6 "(only N qualifying)" branch is exercisable). | — | M | yes |
| 0.5 | Build `tests/fixtures/persona-attribution/` — redacted real session excerpts via 0.3, plus deliberate-failure fixture (`leakage-fail.jsonl`) with one forbidden field. | 0.1, 0.3 | S | sequential after 0.1+0.3 |

**DoD Wave 0:** Q1 result documented. Both schemas validate. Cross-project fixtures cover both A6 branches. Deliberate-failure fixture has one forbidden field that `additionalProperties: false` would catch.

### Wave 1 — Engine + privacy gates (sequential after Wave 0; ~2 subagents internally)

| # | Task | Depends On | Size | Parallel? |
|---|------|------------|------|-----------|
| 1.1 | Project Discovery cascade — implement `validate_project_root()` (path-traversal + symlink containment); cwd auto-discovery; `${XDG_CONFIG_HOME:-$HOME/.config}/monsterflow/projects` reader; `--scan-projects-root` with interactive `scan-roots.confirmed` flow + `.monsterflow-no-scan` opt-out sentinel; non-tty refusal path. | 0.2 | M | — |
| 1.2 | `safe_log()` helper — fixed `SAFE_EVENTS` enum (`discovered_projects`, `malformed_artifact`, `missing_artifact`, `window_rolled`, `wrote_rankings`, `truncated_finding_ids`, `rejected_config_entry`, `rejected_symlink_escape`); value-pattern allowlist (persona/gate/state/sha256/int/ISO-date); raw `print()` banned by `tests/test-no-raw-print.sh` grep gate. | — | S | yes (with 1.1) |
| 1.3 | Cost walk — `~/.claude/projects/*/*.jsonl` mtime-pruned single-pass with substring pre-filter (`"Agent"` + `"tool_use"`); per-(persona, gate, parent_session_uuid) attribution; persona-name regex from Agent dispatch prompt; `agentId` from tool_result trailing text. Imports `PRICING` + `entry_cost` from `session_cost`. **Does NOT modify `session-cost.py`.** | 1.1, 1.2, 0.5 | M | — |
| 1.4 | A1.5 cross-check — for every Agent dispatch in fixture: `total_tokens` from parent's tool_result == `sum(usage.input_tokens + usage.output_tokens)` from `subagents/agent-<id>.jsonl`. On agreement: parent annotation is canonical. **On disagreement: `compute-persona-value.py` exits non-zero** unless `--best-effort`. Resolves spike Open Q1. | 1.3 | S | — |
| 1.5 | Value walk + `run_state` classification — walks `findings.jsonl`, `survival.jsonl`, `run.json`, `raw/<persona>.md` per artifact directory; classifies into 6-state enum; computes `total_emitted` from top-level bullets under `## Critical Gaps` / `## Important Considerations` / `## Observations` (excludes `## Verdict`, nested, numbered). | 1.1, 1.2 | L | yes (with 1.3) |
| 1.6 | 45-window cap + `contributing_finding_ids[]` soft-cap (most-recent-50 + `truncated_count`); IDs sorted lex before emit (idempotency); per-machine salt at `~/.config/monsterflow/finding-id-salt` (256-bit random, chmod 600); ID = `<gate-prefix>-sha256(salt \|\| normalized_signature)[:10]`. | 1.5 | M | — |
| 1.7 | Roster sidecar emit — walks `personas/{review,plan,check}/*.md`; emits `dashboard/data/persona-roster.js` (`window.PERSONA_ROSTER = […]` with persona, gate, file_path, persona_content_hash, last_modified, deprecated). | — | S | yes (with 1.3, 1.5) |
| 1.8 | Rankings bundle emit — computes JSONL row per (persona, gate); validates each via `jsonschema.validate(row, allowlist_schema)`; atomic write to `dashboard/data/persona-rankings.jsonl`; sibling `dashboard/data/persona-rankings-bundle.js` (`window.__PERSONA_RANKINGS = […]`); `sort_keys=True` + `round(x, 6)` for floats. | 1.4, 1.6, 1.7 | M | — |
| 1.9 | `tests/test-allowlist.sh` — A10. Asserts: every row in `persona-rankings.jsonl` has zero non-allowlist fields; every row in `tests/fixtures/persona-attribution/*.jsonl` (except `leakage-fail.jsonl`) passes; `leakage-fail.jsonl` FAILS the test when run alone (proves enforcement). Plus stderr canary check (`LEAKAGE_CANARY_xyz123`). | 1.2, 1.8, 0.5 | M | — |
| 1.10 | `tests/test-phase-0-artifact.sh` — A0. Asserts spec contains `## Phase 0 Spike Result` heading; section names `agentId`; `tests/fixtures/persona-attribution/` exists with ≥1 valid `.jsonl`. | 0.1, 0.5 | S | yes (with 1.9) |
| 1.11 | `tests/test-path-validation.sh` — symlink escape, `..` segments, non-absolute config entries; per-project `.monsterflow-no-scan` opt-out. | 1.1 | S | yes (with 1.9, 1.10) |

**DoD Wave 1:** A0, A1, A1.5, A8, A9, A10 all green against Wave 0 fixtures. Engine produces a real `persona-rankings.jsonl` + `persona-rankings-bundle.js` + `persona-roster.js` from the cross-project fixture.

### Wave 2 — Surfaces (parallel; 2 subagents)

| # | Task | Depends On | Size | Parallel? |
|---|------|------------|------|-----------|
| 2.1 | `commands/wrap.md` Phase 1c integration — insert unconditional `compute-persona-value.py` invoke after line 160; pre/post `[ -f persona-rankings.jsonl ]` check gates `persona-metrics-validator` invocation (V3 trigger); render text section per ux's locked format (top + bottom 3 per dim × per gate, "(only N qualifying)" handling, "never run this window" line, retention-vs-survival semantics note). | 1.8 | M | yes |
| 2.2 | `dashboard/index.html` — third top-level mode button `<button data-mode="personas">Persona Insights</button>` near line 70; three `<script src>` tags in strict order (roster.js → rankings-bundle.js → persona-insights.js); extend mode handler. | — | S | yes (with 2.1) |
| 2.3 | `dashboard/persona-insights.js` (NEW) — registers `window.__renderPersonaInsightsView`; merges `PERSONA_ROSTER` + `__PERSONA_RANKINGS`; renders 11-column sortable table (per ux spec) with `.badge` for dominant `run_state`; `.row-low-sample` (opacity 0.55) for insufficient_sample; strikethrough + red badge for deleted; "(never run)" rows from roster-only entries; null-rate cells `—` (sort to bottom always); color bands; `.gitignored` rendered banners (privacy + stale-cache + empty-state per ux's locked copy). | 2.2 | M | sequential after 2.2 |
| 2.4 | `.gitignore` — add `dashboard/data/persona-rankings-bundle.js`, `dashboard/data/persona-roster.js` (existing `dashboard/data/*.jsonl` covers JSONL). | — | S | yes |

**DoD Wave 2:** Both rendering surfaces work against Wave-1 JSONL under `file://`. Banner copy matches ux spec verbatim. State badge silent for `complete_value`, otherwise dominant-state badge with hover-tooltip breakdown.

### Wave 3 — End-to-end acceptance (parallel; 2-3 subagents)

| # | Task | Depends On | Size | Parallel? |
|---|------|------------|------|-----------|
| 3.1 | `tests/test-compute-persona-value.sh` — A2 (rates + `run_state_counts` totals match `runs_in_window`); A3 (cross-project cascade tested via cwd, fixture-config, `--scan-projects-root`); A4 (content-hash window reset, asserts post-edit `contributing_finding_ids[]` cleared); A7 (e1–e12 + soft-cap behavior + `--scan-projects-root` opt-in default-off); A11 (≥1 row per distinct (persona, gate) pair present in source `findings.jsonl[s]`). | 1.8, 0.4 | L | yes |
| 3.2 | Dashboard A5 — DOM-level assertions that "Persona Insights" tab present, sortable, insufficient-sample rows dim with "—" rate cells, deleted personas strikethrough + "deleted" badge, "(never run)" rows from roster-only entries, all three banners (privacy / stale-cache / empty-state) render correctly under each precondition. Loaded under `file://`. | 2.3 | M | yes (with 3.1, 3.3) |
| 3.3 | `/wrap-insights` A6 — text-format assertions; cost ranking uses `avg_tokens_per_invocation` not totals; "(only N qualifying)" annotation; retention-vs-survival semantics note present. | 2.1 | S | yes (with 3.1, 3.2) |
| 3.4 | Privacy regression: `tests/test-finding-id-salt.sh` (same input + different salts → different IDs; salt file perms 600); `tests/test-scan-confirmation.sh` (non-tty refusal, pre-confirmed roots, `.monsterflow-no-scan` sentinel respected). | 1.6, 1.1 | S | yes (with 3.1) |
| 3.5 | Telemetry + final lint — verify no raw `print()` in `compute-persona-value.py` (test 1.2's grep gate passes); verify `--help` output for all 6 flags lists the Project Discovery cascade verbatim; verify the `persona-metrics-validator` subagent runs cleanly against Wave-1 output. | All Wave 1+2 | S | sequential after others |

**DoD Wave 3:** A0–A11 all green. Privacy regression suite green. `--help` output matches CLI spec. `persona-metrics-validator` reports zero schema violations.

### Wave 3 — additions per Q1 (locked 2026-05-04)

| # | Task | Depends On | Size | Parallel? |
|---|------|------------|------|-----------|
| 3.6 | `scripts/install-precommit-hooks.sh` (NEW) — adopter-installable opt-in script. Wires a pre-commit hook that runs `tests/test-allowlist.sh` whenever any file under `tests/fixtures/persona-attribution/**` or `dashboard/data/**` is staged. Idempotent (rerunnable, doesn't duplicate hooks); detects existing hooks and prepends safely. Not auto-enabled by `install.sh` rewrite. | 1.9 | S | yes (with 3.1–3.5) |
| 3.7 | `docs/persona-ranking.md` (NEW, in-scope per Q1) — single page covering: retention-vs-survival semantics callout, persona contributors' data lifecycle ("don't self-reject from low rates with insufficient samples — window stabilizes at 45 invocations"), Project Discovery cascade with concrete examples (`scan-roots.confirmed` flow, `.monsterflow-no-scan` opt-out, `MONSTERFLOW_DEBUG_PATHS=1` env), pre-commit hook installation snippet pointing at 3.6. | 3.1, 3.6 | S | sequential after 3.1+3.6 |

### Out-of-band tasks (post-merge, not blocking v1)

- `~/.config/monsterflow/README.md` — written by future `install.sh` rewrite (BACKLOG #2 — Onboarding spec).

## Open Questions — all resolved 2026-05-04

| # | Question | Resolution |
|---|----------|------------|
| 1 | Adopt 6 spec deltas in v4.1 or in `/check`? | **Adopt in v4.1.** Spec amended in same session; `/check` reviews coherent spec/plan pair. |
| 2 | `session-cost.py` non-modification (Δ6) — pre-commit or surface for `/check` re-litigation? | **Pre-commit.** Δ6 in spec; `/check` flags only if import path is genuinely broken. |
| 3 | Pre-commit hook — opt-in script or docs only? | **Both** — `scripts/install-precommit-hooks.sh` (Wave 3 task 3.6) + `docs/persona-ranking.md` paragraph (Wave 3 task 3.7). |
| 4 | `--scan-projects-root` repeatable or comma-separated? | **Repeatable**, argparse `action="append"`. Matches one-path-per-line convention in `scan-roots.confirmed`. |

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| A1.5 disagreement (parent annotation ≠ subagent sum) → engine has no canonical token source | Low (Q2 closed; Q1 remains) | High (spec re-opens) | A1.5 fails build hard; `--best-effort` downgrade exists; subagent transcript path is canonical fallback |
| Adopter's `--scan-projects-root ~/Projects` includes client-confidential repos | Medium | High (privacy leak) | Interactive scan-confirmation flow (decision #13); `.monsterflow-no-scan` per-project opt-out; counts-only telemetry (decision #12); allowlist-enforced output (A10) |
| `additionalProperties: false` rejects a legitimate field added in v1.1 | Medium | Low | `schema_version: 1` bump path documented; v1.1 spec must update allowlist explicitly |
| Heavy adopter (5 projects, 167 features) > 5s refresh | Medium | Low | mtime-prune brings 3-5s; cold first-run 30-60s with stderr warning. Document, don't optimize beyond Wave 1. |
| Persona-name regex breaks under `/autorun` headless flow scaffolding | Low | Medium | Regex tested across 73 RedRabbit fixtures during round-2; unknown personas map to `<unknown>` (don't silently drop). Add autorun fixture in /check if /autorun ships first. |
| `findings.jsonl` schema evolves under our feet (e.g., persona-metrics adds a field) | Low | Low | We read only `personas[]` + `unique_to_persona`; both schema-stable. Forward-compat by reading-permissively. |
| Dashboard `<script src>` load order fails silently if one bundle is missing | Low | Medium | Each bundle file emits `window.__BUNDLE_FOO_LOADED = true`; persona-insights.js asserts presence + renders empty-state on absence. |
| Salt file leaks → finding IDs become guessable | Very low | Low | Single-machine impact; regenerate to invalidate; documented in `docs/persona-ranking.md`. |
| Adopter `git add -f dashboard/data/persona-rankings.jsonl` to share a snapshot | Medium | Low (allowlist-enforced output already privacy-safe) | A10 catches at PR review time; allowlist removes most leak vectors. |

## Spec Deltas to Apply Before /check

These five deltas are required by the plan but currently misalign with spec v4. Apply as v4.1 before `/check`:

| # | Spec section | Change |
|---|--------------|--------|
| Δ1 | Data section / row schema | DROP `window_start_artifact_dir` field |
| Δ2 | Data section / `last_seen` | Truncate to **date-minute** (revised from hour per Justin 2026-05-04); rename to `last_artifact_created_at` |
| Δ3 | Data section / `contributing_finding_ids` | Per-machine salt: `sha256(salt \|\| normalized_signature)[:10]`; salt at `~/.config/monsterflow/finding-id-salt` (256-bit, chmod 600); cross-machine ID stability explicitly NOT a feature |
| Δ4 | Project Discovery / Telemetry | Counts-only stderr telemetry; paths only in interactive `--scan-projects-root` confirmation + behind `MONSTERFLOW_DEBUG_PATHS=1` env (logs to `~/.cache/monsterflow/debug.log`) |
| Δ5 | Project Discovery / Tier 3 | First-use interactive confirmation via `~/.config/monsterflow/scan-roots.confirmed`; non-tty refuses; per-project `.monsterflow-no-scan` opt-out sentinel |
| Δ6 | Integration / Files modified | DO NOT modify `scripts/session-cost.py`; `compute-persona-value.py` imports `PRICING` + `entry_cost` instead |

## Agent Disagreements Resolved

- **Should `compute-persona-value.py` modify `session-cost.py` (per spec) or import from it (per integration)?** Integration's lower-blast-radius argument wins: round-3 narrowing to artifact-directory aggregation removed the per-row attribution need. Recorded as Δ6.
- **Telemetry line format** — spec says paths; security says counts-only. Security wins: paths leak project structure on a public repo. Counts-only in steady state; paths only in interactive confirmation prompt. Recorded as Δ4.
- **Window start field** — spec persists `window_start_artifact_dir` (a path); security says drop or hash. Drop: only used for idempotency debug, redundant with `(persona, gate)` key. Recorded as Δ1.
- **`last_seen` precision** — spec uses full ISO; security said truncate to hour for work-pattern privacy; Justin relaxed to minute (within-hour activity not a privacy concern; minute precision improves dashboard UX). Recorded as Δ2 (also renamed to `last_artifact_created_at` per api).
- **Contributing finding ID hashing** — spec's "sha256-derived but not assumed unguessable" + security's "rainbow-table threat is real for targeted recon." Per-machine salt closes the threat at the cost of cross-machine ID stability (not a v1 use case). Recorded as Δ3.
- **`--scan-projects-root` UX** — api wants flag-and-go; security wants confirmation. Security wins on a public release: friction-aligned with privacy risk. Non-tty refusal preserves automation. Recorded as Δ5.
- **`run_state` surfacing in dashboard** — ux's badge-only-when-non-default approach beats api's first-class `Coverage` column proposal. Resolution: keep both — small `.badge` (dominant state) AND a `Coverage` column rendering `14/18 complete` from `run_state_counts`. ux's "no peer-rank by run_state" concern addressed by removing it from default sort.
- **Three render surfaces** — spec previously had 3; round-3 cut bare-arg full-table. Wave 2 confirms 2 surfaces only (dashboard tab + `/wrap-insights` text section).

## Consolidated Verdict

**Plan is ready for `/check`.** Spec v4.1 (Δ1–Δ6 applied) and plan.md (this file) are coherent. All 4 open questions resolved inline (see table above). 33 design recommendations clustered in `plan/findings.jsonl`; survival classifier at `/check` Phase 0 will judge which made it into this plan vs which Judge dropped. Wave 0 starts with the Phase 0 spike (A1.5 forcing function) — see Wave 0 task 0.1.
