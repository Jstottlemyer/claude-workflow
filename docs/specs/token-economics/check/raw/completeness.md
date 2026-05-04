# Completeness Check — Token Economics

**Verdict:** PASS WITH NOTES — the plan covers every spec requirement structurally, but two acceptance criteria (A1, A8) are implemented in Wave 1 without an explicit Wave 3 verification task, leaving their pass/fail signal implicit.

## Must Fix (blocks /build)

None. Every spec requirement, edge case, delta, and "Files created" entry has at least one wave task that produces or covers it. The two gaps below are verification-binding gaps, not coverage gaps — they should be fixed but they don't block the engine from being built; they make /check-on-build harder.

## Should Fix (important but not blocking)

### S1. A1 has no explicit Wave 3 verification task
A1 ("per-persona cost = sum of subagent rows, exact equality") is the headline cost-attribution invariant. Wave 1 task 1.3 builds the cost walk and 1.4 covers A1.5 (parent-vs-subagent agreement check), but Wave 3 task 3.1 only enumerates A2, A3, A4, A7, A11. A1's "sum(per_persona_tokens across all gates) == sum(usage rows from subagents/agent-*.jsonl)" assertion isn't bound to any named test file.

**Fix:** add A1 to task 3.1's enumeration (it's the same `tests/test-compute-persona-value.sh` file), or fold it into task 1.4 explicitly. One-line plan edit.

### S2. A8 idempotent-refresh has no explicit verification task
Task 1.8 implements the mechanics (`sort_keys=True`, `round(x, 6)`, sorted `contributing_finding_ids[]`, atomic write), and §Idempotency contract names the diff-stable allowlist — but no Wave 3 task runs `compute-persona-value.py` twice and asserts byte-for-byte equality (excluding `last_artifact_created_at`). A8 is the only acceptance criterion in the spec without a named test owner in the plan.

**Fix:** add a small task 3.x ("run engine twice on identical fixture data, diff outputs excluding `last_artifact_created_at`, assert empty diff") or fold into 3.1. Important because A8 silently regressing would be invisible in dashboard renders.

### S3. e12 fresh-install assertion is folded into A5, not A11
Spec e12 says "fresh-install adopter sees empty data area + full (never run) roster + 'No data yet' banner — A11 explicitly excludes this case." Plan task 3.2 mentions "empty-state" banner "render correctly under each precondition" but doesn't enumerate the e12 precondition (no `persona-rankings.jsonl` exists) as a distinct DOM-test scenario. A11 in 3.1 also doesn't assert the negative case.

**Fix:** add one line to task 3.2 making the "no rankings file at all" scenario explicit, or note it under task 3.1 as A11's contrapositive.

## Observations (non-blocking)

### O1. `tests/test-no-raw-print.sh` is created inside task 1.2's description rather than as a standalone task line
Spec lists it in "Files created"; plan task 1.2 says "banned by `tests/test-no-raw-print.sh` grep gate" and task 3.5 says "verify no raw print()". The file gets written, the test gets run — coverage is real, just not as a numbered row. Fine as-is; flagging only because the spec inventories it as a first-class file.

### O2. Δ6 (don't modify session-cost.py) is a negative requirement and the plan handles it correctly
Task 1.3 says "Imports `PRICING` + `entry_cost` from `session_cost`. **Does NOT modify `session-cost.py`.**" Good — explicit negative is preserved through to the build instructions, which is the only way negative requirements survive parallel execution.

### O3. The `MONSTERFLOW_DEBUG_PATHS=1` env var (Δ4) is described in spec but not in any task
The spec defines this as an opt-in path-exposure debug switch logging to `~/.cache/monsterflow/debug.log`. Task 1.2 implements `safe_log()` and the SAFE_EVENTS enum, but neither the env-var read nor the debug-log path is enumerated in any wave task. Likely subsumed under "implement Project Discovery + safe_log" but worth a one-line callout in 1.2 or 1.1 so the build agent doesn't drop it. (The privacy posture works either way — env-off is the safe default.)

### O4. e6 stale-data banner has no test
Task 2.3 says the stale-cache banner is rendered; task 3.2 asserts "all three banners render correctly under each precondition." Since e6 requires "no `/wrap-insights` run in 14+ days" — the test would need to fixture a stale `last_artifact_created_at`. Not blocking; flagging because date-arithmetic banners are exactly the kind of UI that ships broken.

### O5. The `persona-metrics-validator` subagent invocation is wired in task 2.1 + verified in 3.5 — good
This was a spec requirement under "Subagents to invoke during/after build" and the plan correctly puts the wiring in `commands/wrap.md` Phase 1c (2.1) with a smoke verification in 3.5. Coverage is complete.

### O6. Wave 3 additions (3.6, 3.7) for pre-commit hook + docs are bonus scope that the spec didn't explicitly require
Spec mentions `docs/persona-ranking.md` only in the round-3 polish table ("Will be addressed in `docs/persona-ranking.md` (out of scope here; opens a docs issue post-merge)") — so 3.7 is in-scope-expansion vs. spec deferral. Not a completeness defect; flagging because it crosses the spec's stated scope boundary. (Defer to scope-discipline persona for the call.)

## Coverage Summary

| Spec element | Plan coverage |
|---|---|
| A0–A11 + A1.5 acceptance criteria | A1 + A8 lack named verification tasks (S1, S2); rest covered |
| e1–e12 edge cases | e1–e11 covered by 3.1's enumeration; e12 implicit in 3.2 (S3) |
| Δ1–Δ6 spec deltas | All six reflected in concrete tasks (Δ1→0.2, Δ2→0.2, Δ3→1.6, Δ4→1.2, Δ5→1.1+3.4, Δ6→1.3) |
| Files created (15 entries) | 14 explicit; `test-no-raw-print.sh` folded into 1.2 (O1) |
| Phase 0 spike Q1 forcing function | Task 1.4 closes A1.5 with explicit non-zero exit on disagreement |
| Privacy gates (A9, A10, redaction, salt, scan-confirm) | All bound to named test files in Waves 1+3 |
