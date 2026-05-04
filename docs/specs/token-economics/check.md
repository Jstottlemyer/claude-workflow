# Check: Token Economics

**Date:** 2026-05-04
**Spec:** `docs/specs/token-economics/spec.md` revision 4.1
**Plan:** `docs/specs/token-economics/plan.md`
**Reviewers:** 5 plan reviewer personas + Codex adversarial
**Survival classifier (synthesis-inclusion mode):** 31/33 plan-stage findings addressed by plan.md (94%); 1 not_addressed (memory observation); 1 rejected_intentionally (install.sh deferral)
**Overall verdict:** **GO WITH FIXES** — 5 of 5 primary reviewers PASS WITH NOTES (zero must-fix); Codex NO-GO with 5 implementation blockers (all confirmed empirically; all fixable inline without re-planning).

## Reviewer Verdicts

| Dimension | Verdict | Key Finding |
|-----------|---------|-------------|
| Completeness | PASS WITH NOTES | A1 + A8 acceptance criteria lack named Wave 3 verification tasks; e12 fresh-install needs explicit DOM test |
| Sequencing | PASS WITH NOTES | DAG is acyclic; 1.5 underdeclares dep on 0.4 fixtures; 3.7 docs over-declares dep on 3.1 (can run parallel) |
| Risk | PASS WITH NOTES | **tmux non-tty refusal** will hit Justin day-one (`dev-session.sh` pipes stdin); salt mid-run corruption + content-hash 90%-pre-edit-data window unaddressed |
| Scope Discipline | PASS WITH NOTES | 5 trims: cut `--explain`, fold `--list-projects` into `--dry-run`, cut precommit task 3.6, 11→7 dashboard cols, 7→4 test files |
| Testability | PASS WITH NOTES | Every A0–A11 + A1.5 has named test owner; 9 tightenings (meta-runner contract for inverted assertion, `test-no-raw-print.sh` regex shape, A11 fresh-install owner, A0 content checks, A1.5 disagreement-path test) |
| **Codex** | **NO-GO before code** | **5 implementation blockers** — hyphen-filename import bug, undeclared `jsonschema` dep, cost↔value-window join still undefined, silent-persona misclassification, `--list-projects` privacy contradiction |

## Must Fix Before Building (8 items — Codex 5 confirmed + 3 highest-value primary)

### From Codex (all empirically verified)

**M1. `from session_cost import PRICING, entry_cost` won't work — file is `session-cost.py` (hyphen).**
- **Verified:** `ls scripts/session-cost.py` returns the hyphenated filename.
- Plan decision #14 + Δ6 + spec §Integration all assume Python's `from session_cost import …` works via `sys.path` insert. It doesn't — hyphens are illegal in module names.
- **Fix options:** (a) `importlib.util.spec_from_file_location("session_cost", "scripts/session-cost.py")` (3 lines, one-time at top of `compute-persona-value.py`); (b) symlink `scripts/session_cost.py` → `scripts/session-cost.py`; (c) rename `session-cost.py` → `session_cost.py` (touches the spec's "DO NOT modify session-cost.py" boundary, but only as a `git mv` not a content edit).
- **Recommend (a)** — keeps the existing script's filename intact and explicit about the import dance. Add to plan task 1.3 description.

**M2. `jsonschema.validate` is an undeclared Python dependency.**
- **Verified:** `python3 -c "import jsonschema"` → `ModuleNotFoundError`. Repo has no `requirements.txt` / `pyproject.toml`; existing scripts are stdlib. Plan decision #1 + scalability persona's "stdlib only" constraint conflict with the planned `jsonschema.validate(row, schema)` per row.
- **Fix options:** (a) Add `requirements.txt` + install step (bad timing for public release week — adds an adopter setup step); (b) Implement a narrow allowlist validator inline (~30 lines of python — checks `additionalProperties: false` + `required[]` + `enum`/`pattern` for the fields we actually use); (c) Vendor a single-file pure-stdlib validator.
- **Recommend (b)** — the allowlist schema is small (~22 fields); a 30-line validator is less cost than a dependency. Add validator-impl task to Wave 1 (between 1.8 and 1.9). Update plan decision #1 to clarify "schema is JSON Schema-shaped, but validation is custom + narrow."

**M3. Cost↔value-window join is still undefined — declare honest separation in v1.**
- Plan windows over `docs/specs/<feature>/<gate>/` artifact directories on the value side, but the cost walk emits `(persona, gate, parent_session_uuid)`. **There is no stable key linking parent session UUID to a specific feature artifact directory.** This means `total_tokens`, `avg_tokens_per_invocation`, and especially `cost_only` row counts look artifact-windowed when they aren't.
- This was Codex round-3 blocker #3 in `/spec-review`; v4 declared "best-effort aggregate by artifact directory" but plan didn't carry through the implication that **cost cannot use that window** without per-dispatch capture.
- **Fix:** declare the honest two-signal split in plan + spec:
  - **Value metrics** (judge_retention, downstream_survival, uniqueness, total_emitted, run_state_counts) — windowed over 45 most-recent (persona, gate) artifact directories.
  - **Cost metrics** (total_tokens, avg_tokens_per_invocation) — windowed over 45 most-recent observed Agent dispatches per (persona, gate), measured machine-locally from session JSONLs. **Explicitly NOT aligned to the value-window 45 artifact directories.**
  - Dashboard renders both columns; tooltip explains they're different windows.
  - v1.1 (per-dispatch capture) makes them aligned.
- This is the most architectural of the 5; spec needs a one-paragraph clarification + plan needs the same denominator distinction in §Data and A2 verification.

**M4. Silent personas (zero findings, status:ok) get misclassified as "never run."**
- Existing `commands/_prompts/findings-emit.md` deliberately writes `participation.jsonl` rows for personas that ran but emitted nothing — so the plan must read both files, not just `findings.jsonl` + roster.
- Plan keys "data row" off `findings.jsonl personas[]` and "(never run)" off roster-minus-data. **A persona with `participation.status: ok` and `findings_emitted: 0` falls through both filters** — currently rendered as "(never run)" when it actually ran successfully (and is signal-low, possibly auto-pruneable in v1.1).
- **Fix:** add `silent_runs_count` to row schema (separate denominator). State machine adds 7th state `silent` between `complete_value` and roster-only. `compute-persona-value.py` reads `participation.jsonl` per artifact directory; `findings_emitted: 0 AND status: ok` → contribute to row with `silent_runs += 1`. Dashboard renders silent row with appropriate badge (e.g., `.badge.grey "silent"`), distinct from `.badge.grey "never run"`.

**M5. `--list-projects` violates the counts-only-telemetry privacy model.**
- Plan: counts-only stderr; paths only in interactive `--scan-projects-root` confirmation + `MONSTERFLOW_DEBUG_PATHS=1` env.
- `--list-projects` is in the 6-flag CLI surface (decision #16), but a project list without paths is useless and a path list violates the steady-state privacy rule.
- **Fix options:** (a) Define `--list-projects` as **interactive-only** — refuses if `!isatty(stdout)`; (b) Define as **debug-gated** — requires `MONSTERFLOW_DEBUG_PATHS=1`; (c) **Remove**, fold into `--dry-run` (which scope-discipline already recommended).
- **Recommend (c)** — `--dry-run` covers the same use case (compute discovery + show what would happen) without a separate flag and stays aligned with scope-discipline's S2.

### From Primary Reviewers (highest-value)

**M6. tmux non-tty refusal will hit Justin on day one** (Risk S1).
- `dev-session.sh` pipes claude window output to a session log file. Under tmux pipe-pane, `isatty(stdin)` returns False. First-time `--scan-projects-root ~/Projects` from Justin's actual workflow will silently refuse to confirm, log "scan-roots not confirmed; skipping K roots," and never populate `scan-roots.confirmed`.
- **Fix:** add `--confirm-scan-roots` non-interactive flag — accepts a `<dir>` and writes it to `scan-roots.confirmed` without the prompt. Document in `docs/persona-ranking.md`. Risk-register entry: "tmux/log-piped stdin defeats interactive confirmation flow." Self-diagnostic stderr message when refusing (`[persona-value] non-interactive stdin detected; cannot prompt. Use --confirm-scan-roots <dir> from a real terminal first, or set MONSTERFLOW_TIER=...`).

**M7. Salt file mid-run corruption is unspecified** (Risk S2).
- Zero-byte salt collapses entropy to public hash; truncated salt drops to 64 bits silently; concurrent first-run race between two `/wrap-insights` produces orphaned IDs in JSONL.
- **Fix:** validate on read (`len == 32` bytes, non-zero), atomic write via `tmp + os.replace` on first generation, regenerate-and-clear-rankings-JSONL on validation failure (drill-down continuity reset is the only honest behavior).

**M8. `leakage-fail.jsonl` inverted assertion needs meta-runner contract** (Testability #1).
- A test that's supposed to **fail when run alone** is brittle — a crash falsely "passes" the inverted assertion.
- **Fix:** specify in plan: `tests/test-allowlist.sh` runs the regular fixtures (which pass); a separate `tests/test-allowlist-inverted.sh` invokes the validator with `leakage-fail.jsonl` as input and asserts both **non-zero exit code** AND a **specific stderr violation message** (e.g., `additionalProperties: 'finding_title'`). `tests/run-tests.sh` runs both; only the second is allowed to "fail successfully."

## Should Fix (apply during /build, not blocking)

### From Codex
- **Path validation breaks tests under `/tmp` or repo paths.** `validate_project_root()` rejects non-`$HOME`. Fixtures need either repo-relative absolute paths under `$HOME` OR `MONSTERFLOW_ALLOWED_ROOTS=<repo>:$HOME` env-var setup in test harness. Document in plan task 1.11.
- **A4 overstates content-hash reset enforceability.** Without per-dispatch hash capture, you can only clear drill-down by intentionally discarding all prior rows for the current persona. That's a product decision, not a data property. Reword A4 to: "after persona edit + one fresh dispatch, `contributing_finding_ids[]` for the new hash contains only post-edit IDs (pre-edit IDs are dropped wholesale at hash-change detection time)."

### From Primary Reviewers
- **A1 + A8 verification tasks** — fold A1 (cost sum equality) and A8 (idempotent re-run) into Wave 3 task 3.1's enumerated list (currently only A2/A3/A4/A7/A11). [Completeness S1+S2]
- **e12 fresh-install DOM test** — explicit sub-case in Wave 3 task 3.2 ("no JSONL + roster.js present → empty-state banner + (never run) rows"). [Completeness S3 + Testability #3]
- **Task 1.5 dep on 0.4** — value walk needs the cross-project fixtures; add `0.4` to the "Depends On" column. [Sequencing #1]
- **Task 3.7 dep simplification** — `docs/persona-ranking.md` only needs `1.1 + 1.6 + 3.6`, not `3.1 + 3.6`. Lets it run parallel with Wave 3 tests. [Sequencing #2]
- **A0 spike-result content checks** — `test-phase-0-artifact.sh` should assert `wc -l > 10` + literal token checks (`total_tokens`, `subagents/agent-`, verdict line) so a 1-line TODO can't pass A0. [Testability #4]
- **A1.5 disagreement-path test** — Wave 3.5 should exercise the disagreement branch with a tampered fixture, asserting non-zero exit + `--best-effort` downgrade behavior. [Testability #5]
- **Content-hash 90%-pre-edit-data tooltip** — when current hash doesn't match the oldest row's hash in window, dashboard shows "Hash recently changed (mixed-window)" badge. [Risk S3]
- **Dashboard banner assertions: CSS class + load-bearing word, not full copy.** Otherwise A5 is brittle to whitespace edits. [Testability #7]
- **Color band assertions: `.band-low/.band-mid/.band-high` class boundaries**, not RGB pixel diff. [Testability #8]
- **`tests/test-no-raw-print.sh` regex pinning** — define the regex shape + positive/negative corpus; scope to `compute-persona-value.py` only. [Testability #2]
- **Salt perms test uses `python3 os.stat`**, not `stat -f` vs `-c` (portability). [Testability #6]

### Scope-discipline trims (apply if light on Wave 3 budget)
- Cut `--explain` flag from v1 (defer to v1.1 — drill-down is in dashboard already).
- Fold `--list-projects` into `--dry-run` (already a Codex M5 fix).
- 11 dashboard columns → 7 (move `persona_content_hash` and `last_artifact_created_at` to tooltip on persona name; merge `runs_in_window` + `run_state` into "Coverage: 14/18" column per decision #20).
- 7 test files → 4 (combine privacy-side: `test-finding-id-salt.sh` + `test-scan-confirmation.sh` + `test-path-validation.sh` → `test-privacy-gates.sh`; fold `test-no-raw-print.sh` into `test-allowlist.sh`).

## Accepted Risks (proceeding with awareness)

- **Cold first-run 30-60s on year-old history** — surfaces as stderr warning; not optimized further in v1 (Risk Register entry).
- **Persona-author exposure via screenshots** — privacy banner is the only mitigation; allowlist doesn't help with rendered output. Documented in §Privacy.
- **Multi-machine sync gap** — JSONL is gitignored; per-machine windows diverge. Stated as machine-local v1; cross-machine aggregation is v2+ scope.
- **A1.5 calibration based on one fixture (RedRabbit)** — Risk S4 suggests re-run against one additional project + Claude Code version before public release. Accepted for now; re-run becomes a pre-release smoke check (post-`/build`, pre-merge).
- **`MONSTERFLOW_DEBUG_PATHS` discoverability** — only documented in `docs/persona-ranking.md` (Wave 3 task 3.7), not surfaced in `--help` of `compute-persona-value.py`. Risk S5 says "discoverable on day one." Accept; mention in stderr telemetry message when paths are needed but env var isn't set.

## Codex Adversarial View

Codex round-at-check full output: `docs/specs/token-economics/check/raw/codex-adversary.md`. The 5 must-fix items above (M1–M5) are Codex's 5 blockers; M6–M8 came from primary reviewers; the rest of Codex's findings (path validation under fixtures, A4 enforceability, deliberate-failure isolation) are folded into Should Fix. Codex's "What I'd Keep" notes the allowlist privacy gate, file:// sidecar, counts-only telemetry, and dashboard-as-passive-renderer as good — recommend keeping all four.

Codex's "Better Approach" — ship v1 as **two honestly separated signals** (value-metrics by artifact directory; cost-metrics by observed Agent dispatch with NO claim of window alignment) — is what M3 enforces. Recommend adopting verbatim.

## Agent Disagreements Resolved

- **Codex NO-GO vs 5× primary PASS WITH NOTES** — same pattern as `/spec-review` rounds 2 + 3. The primary reviewers verified the plan against itself; Codex verified it against the actual codebase (and found the hyphen-import bug + missing dependency + join-key gap). Resolution: NO-GO is correct on Codex's evidence, but the fixes are targeted plan edits (~30 minutes), not a re-plan. Surface as **GO WITH FIXES** with the 8 must-fix items above.
- **Scope-discipline cuts vs everything else** — scope-discipline persona pushed for cutting precommit script + collapsing dashboard columns + merging test files. Risk + completeness reviewers explicitly didn't push back. Apply during /build (Should Fix), not pre-/build — keeping them in v1 doesn't break anything; cutting them is "if budget tight" reflexive YAGNI not "this won't work."
- **`session_cost` import (Codex M1) vs Δ6 spec text** — Δ6 says "DO NOT modify scripts/session-cost.py"; M1 fix (a) honors this (importlib without renaming). M1 fix (c) (`git mv` to underscore) violates Δ6. Pick (a). Update plan task 1.3 inline.

## Final Verdict

**GO WITH FIXES.** Apply M1–M8 inline to plan.md (and where necessary spec.md as v4.2) before `/build` dispatches its first subagent. Should Fix items can either land in plan now or be absorbed during /build by individual subagents — flag them in the relevant task descriptions so subagents see the constraints.

**Estimated fix time:** ~30 minutes of plan/spec edits. No re-plan needed.
