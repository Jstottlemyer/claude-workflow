# Scope Discipline — /check Review

**Spec:** token-economics v4.1
**Plan:** 4-wave, 28 tasks
**Lens:** YAGNI — what's overbuild?

## Verdict

**PASS WITH NOTES** — plan is largely disciplined (already deferred composite scores, `/wrap-insights ranking`, per-dispatch hashing, A12), but it carries a few v1.1-shaped tasks and surface decorations that should defer for a leaner first ship.

## Must Fix (cuts that BLOCK ship)

None. There is no overbuild large enough to block. The plan has clear v1 boundaries; everything below is "should defer" not "must cut."

## Should Fix (cuts worth making)

### S1. Defer `--explain PERSONA[:GATE]` to v1.1 (cut from decision #16's flag list)
- This is a debugging convenience. v1 ships `contributing_finding_ids[]` already and a dashboard collapsible column. Drill-down at the CLI duplicates that surface for a population of one (Justin debugging). Nothing in A0–A11 requires it. **Cut the flag, cut the help text, cut whatever test row would have covered it.** Ships in v1.1 when the first "why is this persona ranked low" investigation needs more than the dashboard offers.
- **Resulting CLI surface: 5 flags** — `--scan-projects-root` (privacy), `--best-effort` (A1.5 escape hatch), `--list-projects` (discovery dry-run), `--out PATH` (test plumbing), `--dry-run` (compute-without-write). Each earns its slot.

### S2. Drop `--list-projects` OR `--dry-run` — pick one
- Both are "compute discovery / compute output, don't write." `--dry-run` (don't write the JSONL) subsumes `--list-projects` (just print discovered roots) if `--dry-run` also prints the discovery telemetry to stderr (which Δ4 already mandates anyway). Keep `--dry-run`; cut `--list-projects`. **Resulting CLI: 4 flags.**
- If you keep `--list-projects` for the interactive `--scan-projects-root` confirmation flow (where the user needs to see paths before saying y/N), note that flow is already inline in `--scan-projects-root` first-use behavior. No separate flag needed.

### S3. Cut Wave 3 task 3.6 (`scripts/install-precommit-hooks.sh`)
- Q1 added 3.6 + 3.7 in the same /plan session — that's two new artifacts bolted on right before /check. Pre-commit hook installation is **adopter ergonomics**, not a v1-ship requirement.
- A10 (the allowlist test) already runs in CI / local test runs. The pre-commit hook only catches the case "adopter `git add -f`s a fixture file with a forbidden field locally" — which is exactly what A10 catches at PR-review time per the risk register ("A10 catches at PR review time; allowlist removes most leak vectors").
- **Defer 3.6 to a follow-up issue.** Document the recommendation in 3.7 with a 3-line `git config core.hooksPath` snippet adopters can copy. Ship the hook script post-merge if anyone asks.

### S4. Collapse the 11-column dashboard table to 7 columns for v1
- Current: persona, gate, runs_in_window, run_state (badge), judge_retention_ratio, downstream_survival_rate, uniqueness_rate, total_tokens, avg_tokens_per_invocation, last_seen, persona_content_hash, contributing_finding_ids (collapsible). That's 11 visible + 1 collapsible.
- **Cut for v1:** `total_tokens` (avg is the right cost-rank field per decision #20; total just confuses), `persona_content_hash` (debug column; nobody reads sha256 prefixes — surface in tooltip on persona name instead), `last_seen` (timestamp clutter; surface in tooltip on persona name), `runs_in_window` AND `run_state` standalone column (decision #20 already says "Coverage column derived from run_state_counts" renders `14/18 complete` — that single column replaces both).
- **Resulting v1 columns (7):** persona, gate, coverage (`14/18 complete`), judge_retention_ratio, downstream_survival_rate, uniqueness_rate, avg_tokens_per_invocation, contributing_finding_ids (collapsible — counts as the 8th if collapsed counts). Tooltip on persona surfaces last_seen + content_hash. Same data emitted to JSONL — just less rendered.

### S5. Merge two of the seven new test files
- Per task list there are: `test-compute-persona-value.sh`, `test-phase-0-artifact.sh`, `test-allowlist.sh`, `test-path-validation.sh`, `test-finding-id-salt.sh`, `test-scan-confirmation.sh`, `test-no-raw-print.sh` — **7 files.**
- Two natural merges:
  - **Merge `test-finding-id-salt.sh` + `test-scan-confirmation.sh` + `test-path-validation.sh` → `test-privacy-gates.sh`.** All three are privacy-side enforcement (salt perms, scan confirmation, path traversal). Single test file, three test functions. Keeps the "one privacy gate, one test" mental model intact.
  - **Merge `test-no-raw-print.sh` into `test-allowlist.sh`.** Both enforce output-side privacy (allowlist on rows, grep gate on stderr). One file, two assertions.
- **Resulting test files: 4** (`test-compute-persona-value.sh`, `test-phase-0-artifact.sh`, `test-allowlist.sh`, `test-privacy-gates.sh`). Same coverage; less file-count overhead; easier to find privacy regressions.

## Observations (not cuts, just framing)

### O1. Two survival rates is correct — keep both
The user prompt asked whether v1 could ship `judge_retention_ratio` OR `downstream_survival_rate` and add the other later. **Keep both.** Round-3 explicitly renamed retention ratio away from "survival" precisely because it's *not* a survival rate — they measure different things (compression density vs downstream pickup), and the spec is careful to document that. Cutting either one means giving up either Judge-stage signal or downstream-stage signal. Both axes are load-bearing. The "stakeholders find one rate easier to reason about" framing dissolves once they're clearly named — and they are.

### O2. A12 (Pro-friend commitment) is correctly punted to BACKLOG
A12 was "spec for `account-type-scaling` exists within 14 days of v1 merge" — that's a **process commitment**, not a software requirement. It can't be tested by `compute-persona-value.py`. Punting to BACKLOG is right; trying to enforce it via this spec would be scope creep into project-management automation. Plan handles correctly.

### O3. Two test fixtures (`persona-attribution/` real + `cross-project/` synthetic) should NOT merge
The user prompt asked. They serve different test surfaces:
- `persona-attribution/` — real (redacted) JSONL excerpts validating Phase 0 spike linkage + A0 + A10 (allowlist on real-shaped data including the deliberate-failure `leakage-fail.jsonl`).
- `cross-project/` — synthetic two-project tree exercising Project Discovery cascade + cross-project aggregation (A3) + cross-fixture (persona, gate) pairs at multiple `runs_in_window` values for A6's "(only N qualifying)" branch.
- Merging would conflate "is the real data shape correct" with "does cross-project aggregation work" — different failure modes. Keep separate.

### O4. Δ6 (don't modify session-cost.py) is the right call and reduces scope
Importing `PRICING` + `entry_cost` via `sys.path` insert — lower blast radius, no concurrent-edit conflict with existing `/wrap` Phase 1 display. Proper YAGNI: don't refactor what you don't need to refactor.

### O5. Sidecar bundle pattern (decision #2) is the correct minimum for `file://` rendering
Both `persona-roster.js` and `persona-rankings-bundle.js` exist because the dashboard can't `fetch()` under `file://`. This isn't gold-plating; it's the established pattern (per `feedback_settings_file_relocation.md` cohort of file://-vs-http lessons). No cut here.

### O6. `schema_version: 1` reservation is correct (no future field pre-reservation)
Decision #7 is explicit: reserve the bump path, do NOT pre-reserve future field names. Plan is disciplined. No cut.

### O7. Net effect of S1–S5 if applied
- CLI: 6 → 4 flags (cut --explain, --list-projects)
- Wave 3: 7 → 6 tasks (cut 3.6; 3.7 absorbs the pre-commit hook docs paragraph)
- Dashboard: 11 → 7 visible columns (move three to tooltips, merge runs_in_window+run_state into Coverage)
- Tests: 7 → 4 files (merge privacy-gates trio, fold no-raw-print into allowlist)
- **Estimated saved effort:** ~3-5 subagent-task-sizes worth (one M task and 2-3 S tasks). Not a wave reduction, but a meaningful Wave 2/3 trim.
- **Risk of cutting:** essentially zero — every cut is either deferred to v1.1 (still ships when needed) or a presentation-layer reduction (data still emitted to JSONL).

## Out-of-Scope-for-This-Persona Notes

- I did **not** look for missing items (completeness owns).
- I did **not** look for risks (risk owns).
- All cuts above are pure overbuild reduction; if completeness or risk persona disagrees with any specific cut, defer to them.
