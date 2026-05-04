---
name: token-economics
description: Per-persona cost + survival + uniqueness instrumentation — measurement only, no roster scaling
created: 2026-05-03
revised: 2026-05-04
revision: 3
status: ready-for-plan
session_roster: defaults-only (no constitution)
---

# Token Economics Spec (v3 — instrumentation only, public-release-ready)

**Created:** 2026-05-03
**Revised:** 2026-05-04 — narrowed from "instrumentation + roster scaling" (v1) to instrumentation-only (v2); v3 applies 7 round-2 blockers as inline edits per Q&A walkthrough on the same date. Public release this week is the new audience constraint.
**Constitution:** none — session roster only
**Confidence:** Scope 0.97 / UX 0.94 / Data 0.92 / Integration 0.93 / Edges 0.93 / Acceptance 0.95
**Session Roster:** defaults-only (28 pipeline personas)

> Session roster only — run /kickoff later to make this a persistent constitution.

## Summary

Measure per-persona **cost** (tokens spent in subagent dispatches per gate) and per-persona **value** along two independent axes — **judge-survival** (post-Judge clustering) and **downstream-survival** (addressed in the next pipeline artifact) — plus **uniqueness** (whether the persona was the sole contributor to the cluster). Aggregate over a rolling 45-(persona, gate)-invocation window across all MonsterFlow projects on the machine. Persist to `dashboard/data/persona-rankings.jsonl`, refresh unconditionally at `/wrap-insights`, surface in a new dashboard tab and `/wrap-insights` text section. **No automatic action** — no roster pruning, no tier detection, no gate behavior changes.

**Pro-tier relief comes in v1.1 (BACKLOG #3) immediately after this lands.** This v1 ships measurement only; the friend-on-Pro who motivated the work gets actionable cost reduction once the next spec ships, not from this one.

## Backlog Routing

| # | Item | Source | Routing |
|---|------|--------|---------|
| 1 | Token economics instrumentation | BACKLOG.md | **(a) In scope** — this spec |
| 3 | Account-type agent scaling | BACKLOG.md | **(b) Stays — committed v1.1 fast-follow** after this spec ships and ≥10 validated runs accumulate |
| 4 | Inter-agent debate (Agent Teams) | BACKLOG.md | **(b) Stays** — research, separate `/spec` after #3 |
| 2 | Onboarding install.sh rewrite | BACKLOG.md | **(b) Stays** — independent, separate `/spec` |
| — | Plugin scoping per gate (action) | BACKLOG.md | **(b) Stays** — needs per-plugin cost measurement (also deferred) |
| — | Per-plugin cost measurement | BACKLOG.md | **(b) Stays** — depends on Phase 0 spike completing first |

## Scope

**In scope:**
- Per-persona, per-gate cost attribution. Subagent transcripts live at `~/.claude/projects/<proj>/<parent-session-uuid>/subagents/agent-<agentId>.jsonl` (linkage via `agentId` in the parent's `Agent` tool_result trailing text — see Phase 0 spike result below).
- **Two value signals**, kept independent:
  - **Judge survival rate** = `count(findings.jsonl rows where persona ∈ personas[]) / count(all bullets in <stage>/raw/<persona>.md, including Critical Gaps + Important Considerations + Observations)`. Measures: did this persona's input survive the Judge clustering pass?
  - **Downstream survival rate** = `count(survival.jsonl rows with outcome ∈ {addressed, kept} where finding's personas[] includes persona) / count(findings.jsonl rows where persona ∈ personas[])`. Measures: did this persona's surviving findings get picked up in the next pipeline artifact (e.g., plan.md, check.md, code)?
- **Uniqueness rate** = `count(findings.jsonl rows where unique_to_persona == persona) / count(findings.jsonl rows where persona ∈ personas[])`. Uses the existing `findings.jsonl.unique_to_persona` field — no jaccard, no recomputation.
- Persistence to `dashboard/data/persona-rankings.jsonl` with **rolling 45 (persona, gate) invocations** window. **Reports totals across the window**, not averages — dashboard divides if it wants.
- Refresh hook in `/wrap-insights` Phase 1c — **unconditional**, NOT piggybacked on `dashboard-append.sh` (which is conditional on `graphify-out/graph.json` existing).
- Cross-project aggregation: the JSONL aggregates across all MonsterFlow projects discoverable on the machine via the cascade in §Project Discovery below.
- New "Persona Insights" dashboard tab — sortable table with separate columns for **judge_survival, downstream_survival, uniqueness, total_tokens, runs_in_window**. No composite score. Renders both data-driven rows AND "(never run)" rows for personas in current `personas/` files but absent from the JSONL (hybrid layer; see UX).
- `/wrap-insights` text sub-section showing top + bottom 3 per gate × per dimension (when ≥3 qualifying personas exist; "(only N qualifying)" otherwise).
- `contributing_finding_ids[]` field on each row for drill-down — addresses adopter debugging on a public release.
- Edge-case handling for new personas, persona-prompt edits (content-hash-based, not mtime), file concurrency, malformed JSONL, deleted personas.

**Out of scope (deferred to separate specs):**
- Roster scaling / auto-pruning (BACKLOG #3) — committed v1.1 immediately after.
- Tier detection (Pro/Max/API) — only useful for #3.
- Runtime gate-roster resolver, gate command edits.
- Composite ranking score.
- Per-plugin cost attribution + plugin-scoping action.
- Build-outcome correlation as a value signal.
- Linux support for new scripts (macOS-only).
- The logging-shim path if Phase 0 spike fails — that's a separate spec, not in-flight scope expansion here.

## Phase 0 Spike Result (preliminary — populated by feasibility round-2 reviewer)

**Status:** preliminary. Two questions remain before `/plan` can proceed (see Open Questions). Three closed below.

**Probe:** `~/.claude/projects/-Users-jstottlemyer-Projects-RedRabbit/42dcaafa-1fbb-4d52-9344-1899381a205c.jsonl` (6427 lines, 73 Agent dispatches).

**Closed:**
- **Where do subagent usage rows land?** NOT in the parent session JSONL (parent contains orchestrator turns only — 1203/1203 assistant rows in fixture). Subagent transcripts at `~/.claude/projects/<proj>/<parent-session-uuid>/subagents/agent-<agentId>.jsonl` with full per-row `usage` (input/output/cache split). Sibling `agent-<agentId>.meta.json` contains `{agentType, description}`.
- **What field links parent→subagent?** The `agentId` string (16 hex chars) appears in the parent's `Agent` tool_result trailing text: `agentId: <16-hex>\n<usage>total_tokens: N\ntool_uses: N\nduration_ms: N</usage>`. NOT `parent_tool_use_id` (doesn't exist as a top-level key). NOT `sourceToolUseID` (only echoes non-Agent tool_use IDs).
- **How do we recover the persona name?** The Agent dispatch's `input.prompt` contains `personas/<gate>/<name>.md` (regex-extractable across all 73 fixtures). Brittle but workable; A1.5 verifies.

**Still open (must resolve in `/plan`):**
- **Open Q1 — canonical token source:** is the `total_tokens` annotation in the parent's tool_result equal to the sum from `subagents/agent-<id>.jsonl`? If they agree, parent annotation is canonical (cheaper to read). If they disagree, subagent transcript is canonical (per-message granularity). A1.5 (acceptance) verifies the agreement; if they disagree, the spec's data-collection path picks subagents/*.jsonl.
- **Open Q2 — worktree behavior:** for sessions that span project dirs / worktrees (saw `Mobile-CosmicExplorer--claude-worktrees-…` in `~/.claude/projects/`), do `subagents/` folders sit under the original parent dir? Resolves whether project discovery needs to follow worktree symlinks.

**Spike fixture:** `tests/fixtures/persona-attribution/` — populated in `/plan` with **redacted** JSONL excerpts (only linkage / IDs / timestamps / model / usage; no prompts, no message bodies, no file paths). See Privacy section.

## Approach

**Phase 1 — instrumentation:**
- Extend `scripts/session-cost.py` to walk both root families:
  - **Cost root:** `~/.claude/projects/*/` for session JSONLs + `subagents/` subdirs.
  - **Value root:** discovered MonsterFlow project paths (see §Project Discovery) for `docs/specs/*/{spec-review,plan,check}/{findings,survival}.jsonl`.
  - Group cost by (parent_session_id, agentId) → match agentId to its `subagents/agent-<id>.jsonl`, sum that file's `usage`. Recover persona name via regex on the parent's `Agent` tool_use prompt; emit per-(persona, gate, parent_run_uuid).
- New `scripts/compute-persona-value.py`:
  - Walks `findings.jsonl` across all discovered projects.
  - Computes **judge_survived** count per (persona, gate): rows where `persona ∈ personas[]`.
  - Computes **emitted** count per (persona, gate): bullet count in matching `<stage>/raw/<persona>.md` (lines starting with `- ` or `* ` under `## Critical Gaps`, `## Important Considerations`, `## Observations` headings).
  - Computes **downstream_survived** count per (persona, gate): joins `survival.jsonl` rows by `finding_id` to `findings.jsonl` rows where `persona ∈ personas[]`, filters `outcome ∈ {addressed, kept}`.
  - Computes **unique** count per (persona, gate): rows where `unique_to_persona == persona`.
  - Caps the window at the most recent 45 (persona, gate) invocations (one Agent tool_use_id = one invocation; re-prompts within a run count as one).
  - Emits totals (not averages) per row; emits `contributing_finding_ids[]` for drill-down.
  - Excludes a row's rates from rendering if `runs_in_window < 3` (sets `insufficient_sample: true`); row is still written.
- Refresh hook in `commands/wrap.md` Phase 1c — invokes `compute-persona-value.py` **unconditionally** when `/wrap-insights` runs, regardless of whether `dashboard-append.sh` ran (which is conditional on graphify).

**Phase 2 — visualization:**
- New "Persona Insights" tab in `dashboard/index.html`:
  - Sortable table merging the JSONL data with the current `personas/{review,plan,check}/*.md` file list. Personas in the file list AND the JSONL render with their data; personas in the file list but NOT in the JSONL render as "(never run)" rows; personas in the JSONL but NOT in the file list render with a strikethrough (deleted persona, data still in window).
  - Columns: persona, gate, runs_in_window, judge_survival_rate, downstream_survival_rate, uniqueness_rate, total_tokens, last_seen, persona_content_hash, contributing_finding_ids (collapsible).
  - **Insufficient-sample rows: rate cells render as "—" (not opacity-dimmed numbers).** Sorting by survival_rate does not surface a 1-run "100%" persona at the top.
- `/wrap-insights` Phase 1c sub-section format:
  ```
  Persona insights (last 45 runs, all projects)
    spec-review:  highest judge-survival → ux-flow (89%), scope-discipline (84%), cost-and-quotas (78%)
                  highest downstream-survival → scope-discipline (62%), edge-cases (54%)
                  highest uniqueness → edge-cases (32%), scope-discipline (28%)
                  lowest total cost → cost-and-quotas (8.2k tok), gaps (9.1k tok)
                  never run this window: legacy-reviewer (in roster, no data)
    plan:         …
    check:        …
  ```
  Show all-available with "(only N qualifying)" annotation if fewer than 3 personas have `runs_in_window ≥ 3`. v1 stays static — no week-over-week deltas.

**Alternatives considered + rejected:**
- Computing value on-the-fly per dashboard load (slow on large histories).
- Per-project (not cross-project) aggregation (artificially shrinks samples).
- Composite ranking score (round-1 + round-2 reviewers showed it's gameable, severity-blind, schema-redundant).
- Re-jaccarding finding titles for uniqueness (existing `unique_to_persona` already encodes the signal).
- Per-invocation averaging (cost↔value join undefined; report totals instead).

## Project Discovery (cascade)

`compute-persona-value.py` resolves project roots via three-tier cascade. Each tier is independently optional; output is the union with deduplication.

1. **Explicit config (highest priority):** `~/.config/monsterflow/projects` — one absolute path per line. Comments (`#`) and blank lines ignored. Adopter-maintained; auditable.
2. **Auto-discovery (default):** scan `~/Projects/*/docs/specs/` (presence of `docs/specs/` directory is the sentinel). No new file required from adopters; uses the convention MonsterFlow already establishes. Adopters who use `~/Code/`, `~/dev/`, etc. add their root via tier (1) or (3).
3. **CLI args:** `compute-persona-value.py --project <path> --project <path>` plus `--projects-root <dir>` (scans the dir for `*/docs/specs/`). For ad-hoc / CI use; `dashboard-append.sh` and the `/wrap-insights` invocation default to no args, deferring to (1) + (2).

Resolves Open Q4 inline. Adopters with non-standard layouts have two escape hatches.

## Roster Changes

No roster changes.

## UX / User Flow

(Detailed in §Approach Phase 2 above and §Data & State below; not duplicated here.)

## Data & State

### New artifact: `dashboard/data/persona-rankings.jsonl`

One row per (persona, gate) pair seen in the last 45 (persona, gate) invocations across all discovered MonsterFlow projects:

```jsonc
{
  "persona": "scope-discipline",
  "gate": "spec-review",
  "runs_in_window": 18,
  "window_size": 45,
  "total_emitted": 47,                          // sum of bullet counts in raw/<persona>.md across runs in window
  "total_judge_survived": 31,                   // sum of findings.jsonl rows where persona ∈ personas[]
  "total_downstream_survived": 19,              // sum of survival.jsonl rows with outcome ∈ {addressed, kept}
  "total_unique": 9,                            // sum of findings.jsonl rows where unique_to_persona == persona
  "total_tokens": 274500,                       // sum across runs in window (no avg; dashboard divides if it wants)
  "judge_survival_rate": 0.659,                 // total_judge_survived / total_emitted
  "downstream_survival_rate": 0.404,            // total_downstream_survived / total_judge_survived
  "uniqueness_rate": 0.191,                     // total_unique / total_judge_survived
  "last_seen": "2026-05-02T18:14:00Z",          // sourced from run.json.created_at of most recent contributing run, NOT file mtime
  "persona_content_hash": "sha256:9a4b…",       // hash of personas/<gate>/<name>.md body, NFC + LF-normalized
  "window_start_run_id": "uuid…",
  "contributing_finding_ids": ["sr-9a4b1c2d8e", ...],   // drill-down
  "insufficient_sample": false                  // true iff runs_in_window < 3
}
```

**Counting unit:** **(persona, gate) invocations** — each Agent dispatch tool_use_id with persona X loaded for gate Y counts as one invocation toward X's window for Y. Re-prompts within a single gate run share a tool_use_id and count as one.

**No composite score.** Survival (×2), uniqueness, and cost are kept as separate columns; consumers compose them however they need.

### Survival semantics

- **judge_survival_rate** denominator = bullets emitted (raw/<persona>.md, all sections including Observations). Numerator = post-Judge findings.jsonl rows where persona is in `personas[]`. Rate captures how much of what the reviewer surfaced survived clustering.
- **downstream_survival_rate** denominator = the persona's findings that survived Judge (i.e., the judge-survival numerator). Numerator = those findings whose `survival.jsonl` outcome is `addressed` or `kept`. Rate captures how much of the reviewer's signal made it into the next pipeline artifact.

These are **independent axes**. A persona can have high judge-survival (Judge keeps everything they say) but low downstream-survival (none of it changes the plan), or vice versa. v1 surfaces both.

### Cost attribution — dependent on Phase 0 spike Open Q1

Pseudocode pending Open Q1 resolution:

```python
for parent_session_jsonl in walk("~/.claude/projects/*/*.jsonl"):
    for agent_dispatch in parent_session_jsonl:
        if agent_dispatch.tool_use.name != "Agent": continue
        persona = regex_extract_persona(agent_dispatch.tool_use.input.prompt)
        gate    = regex_extract_gate(agent_dispatch.tool_use.input.prompt)
        agentId = parse_agent_id_from_tool_result_trailing_text(agent_dispatch.tool_result)
        subagent_jsonl = "~/.claude/projects/<parent-proj>/<parent-session-uuid>/subagents/agent-<agentId>.jsonl"
        # Open Q1: if total_tokens annotation matches sum(subagent_jsonl.usage), use annotation (cheap).
        #          else use sum(subagent_jsonl.usage) (canonical, per-message).
        tokens  = sum_tokens(subagent_jsonl) if open_q1 == "subagent_canonical" else parse_total_tokens_annotation(...)
        emit_per_persona_row(persona, gate, parent_session_uuid, tokens)
```

### Idempotency contract (A8 spec)

- Diff-stable fields (must match byte-for-byte across re-runs): `persona`, `gate`, `runs_in_window`, `window_size`, `total_*`, `judge_survival_rate`, `downstream_survival_rate`, `uniqueness_rate`, `persona_content_hash`, `window_start_run_id`, `contributing_finding_ids` (sorted), `insufficient_sample`.
- Intentionally-volatile fields (excluded from idempotency check): `last_seen` (sourced from `run.json.created_at` of most recent contributing run; never from file mtime — same critique that drove the persona content-hash decision applies).
- Floats serialized as `round(x, 6)` to avoid `0.6590000000001` drift.
- Rows sorted by `(gate, persona)` for deterministic ordering.

### Window: 45 (persona, gate) invocations

- Reset condition: persona's `personas/<gate>/<name>.md` **content hash** changes (NFC-normalized, line-ending-normalized sha256 of file body). Mtime is NOT used.
- Window applies independently per (persona, gate).

### File concurrency

- `compute-persona-value.py` writes via tmp + `os.replace` — atomic on POSIX and Windows.
- Readers (dashboard, `/wrap-insights`) tolerate parse errors: malformed JSONL line → skip with one-line warning, do not abort.
- Cross-project safety: two `/wrap-insights` runs on the same machine race on the same JSONL. Last writer wins; freshness-check before replace (compare `last_seen` of new vs old; if older, abort with warning).

## Privacy (public release)

This spec ships in a public repo. Three concrete privacy gates apply:

1. **A0 fixtures must be redacted** before commit. `tests/fixtures/persona-attribution/` may contain ONLY: linkage IDs (`agentId`, `tool_use_id`, `sessionId`), timestamps, model id, `usage` blocks. NOT: prompts, message bodies, file paths, persona names from the user's actual workflow. A redaction script lives at `scripts/redact-persona-attribution-fixture.py`.
2. **`compute-persona-value.py` reads `findings.jsonl` from any project found by Project Discovery — including private ones (Luna's, career).** The output JSONL records only counts and persona/gate names, NEVER finding titles or bodies. `contributing_finding_ids[]` records IDs only (which are sha256-derived, not human-readable). Spec adds A10 below to verify.
3. **`dashboard/data/persona-rankings.jsonl` is gitignored** per existing `dashboard/data/*.jsonl` rule. Verify in `git check-ignore` test (A9).

## Integration

**Files modified:**
- `scripts/session-cost.py` — add per-(persona, gate, parent_run_uuid) attribution; preserve existing per-session output.
- `commands/wrap.md` — Phase 1c: invoke `compute-persona-value.py` unconditionally; append "Persona insights" sub-section. Bare-arg `/wrap-insights ranking` shows full table.
- `dashboard/index.html` — add "Persona Insights" tab.
- `dashboard/dashboard.js` (or new `persona-insights.js`) — render the new tab with hybrid (data + roster) merge.

**Files created:**
- `scripts/compute-persona-value.py` — value computation + Project Discovery cascade.
- `scripts/redact-persona-attribution-fixture.py` — A0 fixture redaction helper.
- `dashboard/data/persona-rankings.jsonl` — generated, gitignored.
- `tests/test-compute-persona-value.sh` — covers e1–e8 + Project Discovery cascade + drill-down field.
- `tests/test-phase-0-artifact.sh` — A0 machine check.
- `tests/fixtures/persona-attribution/` — REDACTED real-data excerpts (Phase 0 spike output).
- `tests/fixtures/cross-project/` — two synthetic project trees for A3.

**Files NOT touched:**
- `commands/{spec-review,plan,check}.md` — gates dispatch the full default roster.
- `settings/settings.json` — no new keys.
- No new `scripts/resolve-roster.sh`. No tier detection.

**Existing systems leveraged:**
- Persona-metrics infrastructure (`docs/specs/persona-metrics/spec.md`) — `findings.jsonl` schema (`personas[]`, `unique_to_persona`), `survival.jsonl` schema, snapshot/findings-emit directives.
- `scripts/judge-dashboard-bundle.py` — cross-project walk pattern.

**Subagents to invoke during/after build:**
- `persona-metrics-validator` — after first `/wrap-insights` run that produces `persona-rankings.jsonl`.

## Edge Cases

| ID | Case | Behavior |
|----|------|----------|
| e1 | Persona with `runs_in_window < 3` | Row written with `insufficient_sample: true`. Dashboard renders rate cells as "—" (NOT opacity-dimmed numbers, so sort-by-rate cannot surface a 1-run "100%"). Omitted from `/wrap-insights` top/bottom lists. |
| e2 | Persona prompt changed | Detect via content-hash. Reset that (persona, gate) window — drop accumulated runs, mark `insufficient_sample: true` until 3 new runs accumulate. |
| e3 | `findings.jsonl` malformed at compute time | Skip the malformed file with one-line warning to stderr; do not abort the cross-project walk. |
| e4 | `persona-rankings.jsonl` malformed at read time | Dashboard + `/wrap-insights` skip the malformed line, render the rest, print one-line warning. |
| e5 | Two `/wrap-insights` race on the same JSONL | Atomic write via tmp + `os.replace`. Freshness-check before replace (compare new `last_seen` vs old; if older, abort with warning). |
| e6 | Stale data (no `/wrap-insights` run in 14+ days) | Dashboard shows stale-cache banner with last refresh timestamp. No fallback action — data is just stale. |
| e7 | Persona file deleted from `personas/` | Rows for that persona remain in JSONL until window rolls out, but `compute-persona-value.py` flags `persona_content_hash: null`. Dashboard renders deleted personas with strikethrough. |
| e8 | `findings.jsonl` exists but lacks `personas[]` (legacy schema) | Skip with warning; record in compute log. Excluded from window. |
| e9 | Persona in roster files but NOT in JSONL ("never run") | Dashboard renders a "(never run)" row. `/wrap-insights` lists under "never run this window: ..." per gate. |
| e10 | A persona's `total_emitted == 0` | `judge_survival_rate` = null (not 0/0). `insufficient_sample: true`. Cell renders as "—". |
| e11 | A persona's `total_judge_survived == 0` (so downstream-rate denominator is 0) | `downstream_survival_rate` and `uniqueness_rate` = null. Cells render as "—". |

## Acceptance Criteria

| ID | Criterion | Verification |
|----|-----------|--------------|
| **A0** | Phase 0 spike preliminary findings persisted; remaining open questions resolved in `/plan` | `tests/test-phase-0-artifact.sh` asserts: (a) spec contains `## Phase 0 Spike Result` heading; (b) section names a non-empty linkage field (`agentId`); (c) `tests/fixtures/persona-attribution/` exists with ≥1 `.jsonl` file containing valid JSON. Open Q1 + Q2 closed in `/plan` before any code merges. |
| **A1** | Per-persona cost = sum of subagent rows | For fixture: `sum(per_persona_tokens across all gates) == sum(usage rows from subagents/agent-*.jsonl)` (exact equality). Diagnostic columns `orchestrator_tokens` and `unattributed_tokens` reported but not constrained. |
| **A1.5** | Parent annotation cross-checks subagent transcript sum | For every Agent dispatch in fixture: `total_tokens` from parent's tool_result trailing text == `sum(usage.input_tokens + usage.output_tokens)` from `subagents/agent-<id>.jsonl`. If they agree, parent annotation is canonical (resolves spike Open Q1 in favor of cheap path). If disagree, subagent transcript is canonical and `compute-persona-value.py` reads from there. |
| **A2** | Both survival rates + uniqueness computed | `persona-rankings.jsonl` rows have `judge_survival_rate`, `downstream_survival_rate`, `uniqueness_rate` ∈ [0.0, 1.0] OR null (per e10/e11). Rows with `runs_in_window < 3` carry `insufficient_sample: true`. |
| **A3** | Cross-project aggregation works (programmatic) | `tests/fixtures/cross-project/` contains two synthetic project trees (each with `docs/specs/.../{findings,survival}.jsonl`). `tests/test-compute-persona-value.sh` invokes `compute-persona-value.py --project <fixture-A> --project <fixture-B>` and asserts the output JSONL contains data drawn from both roots. Project Discovery cascade tested via fixture-config + fixture-CLI-args. |
| **A4** | Content-hash window reset works | Test sequence: (1) seed N invocations; (2) modify persona file body; (3) run one fresh dispatch; (4) re-run compute. Assert that (persona, gate)'s `runs_in_window == 1` AND `insufficient_sample: true` in the post-edit JSONL. Pre-edit data is dropped. |
| **A5** | Dashboard tab renders correctly | "Persona Insights" tab present; sortable; separate columns for judge_survival, downstream_survival, uniqueness, total_tokens; insufficient-sample rate cells render as "—" (not dimmed numbers); deleted personas strikethrough; "(never run)" rows for personas in roster files but absent from JSONL. |
| **A6** | `/wrap-insights` text section renders | Output includes "Persona insights (last 45 runs, all projects)" with top + bottom 3 per gate × per dimension. When fewer than 3 qualify: "(only N qualifying)" annotation. v1 stays static (no deltas). |
| **A7** | Edge cases covered by tests | `tests/test-compute-persona-value.sh` validates e1–e11 + Project Discovery cascade + drill-down `contributing_finding_ids[]` populated correctly. |
| **A8** | Idempotent refresh | Diff `persona-rankings.jsonl` after two consecutive `compute-persona-value.py` runs with no new source data: byte-for-byte identical excluding the explicitly-volatile `last_seen` field. Diff-stable allowlist documented in §Idempotency contract. |
| **A9** | Privacy: JSONL gitignored | `git check-ignore docs/specs/<feature>/spec-review/findings.jsonl` returns 0 (it IS ignored). Same for `dashboard/data/persona-rankings.jsonl`. Verified in `tests/test-privacy.sh`. |
| **A10** | Privacy: no finding titles/bodies leak into output JSONL | Test sequence: write a `findings.jsonl` row whose title is `LEAKAGE_CANARY_DO_NOT_PERSIST_xyz123`. Run `compute-persona-value.py`. Assert `LEAKAGE_CANARY_DO_NOT_PERSIST` does NOT appear anywhere in `dashboard/data/persona-rankings.jsonl`. Also asserts: `tests/fixtures/persona-attribution/` contains zero matches for `prompt`, `body`, `text`, `content` field-name patterns. |
| **A11** | Spec-level outcome criterion (instrumentation success) | After first `/wrap-insights` run on a project with ≥10 historical gate runs, `persona-rankings.jsonl` contains ≥1 row per (persona, gate) pair seen in those runs. Verifies the script actually writes useful data, not an empty file. |

## Open Questions

1. **Spike Open Q1 — canonical token source** (parent annotation vs subagent transcript). Resolved by A1.5; if values agree, parent annotation is used (cheap); else subagent transcript (canonical, per-message).
2. **Spike Open Q2 — worktree subagent placement** (do `subagents/` folders sit under the original parent dir for worktree sessions?). Resolve in `/plan` with one extra probe against a worktree session; defines whether Project Discovery needs to follow worktree symlinks.
3. **Phase 0 spike-failure path**: if the spike turns up clean linkage (current evidence says yes), v1 ships as-is. If `/plan` discovers the linkage breaks under load (e.g., dashes in gate name corrupt regex), the **logging-shim path is a separate spec** — not in-flight scope expansion here.

(Open Q3 from v2 — uniqueness threshold tuning — disappeared because jaccard was removed. Open Q4 — cross-project root discovery — resolved inline in §Project Discovery. Open Q5 — deletion of stale rows — resolved in e7.)

## Spec Review Round 1 + Round 2 — Resolved Concerns

The first `/spec-review` (artifacts at `spec-review/findings-2026-05-04T01-37-36Z.jsonl`, 23 clusters) raised 7 blockers tied to combined #1+#3 scope. v2 narrowed to instrumentation-only.

The second `/spec-review` (artifacts at `spec-review/findings.jsonl`, 29 clusters) raised 7 narrower blockers tied to schema misalignment (survival, uniqueness, run_id), testability gaps (A0/A1/A3/A8), and project-discovery scope. v3 (this revision) applies all 7 as inline edits per a Q&A walkthrough on 2026-05-04:

| Round-2 Blocker | v3 Resolution |
|---|---|
| Survival not computable | Two columns, both schema-derivable: judge_survival (vs raw bullets) + downstream_survival (vs survival.jsonl outcomes) |
| Uniqueness uses wrong layer | Drop jaccard; use existing `unique_to_persona` field |
| Cost↔value join undefined | Drop per-invocation averaging; report totals; dashboard divides if it wants |
| A1 ±5% impossible | A1 = exact equality on subagent rows; A1.5 = parent annotation cross-check (resolves spike Open Q1) |
| e1 "new persona" rows impossible | Hybrid: data-driven JSONL + dashboard/wrap render-time enrichment with current `personas/` files (e9 added) |
| A0/A3/A8 testability gaps | A0 + A3 + A8 all tightened with concrete test files; `last_seen` sourced from `run.json.created_at` |
| Project discovery unspecified | Cascade: explicit config → auto-discovery via `docs/specs/` → CLI args |

Plus public-release-driven additions: A9 (gitignore verification), A10 (leakage canary), A11 (outcome criterion), Privacy section, A0 fixture redaction script.
