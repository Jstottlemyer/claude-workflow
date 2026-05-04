# Gaps Review — Round 3 (token-economics v3)

**Lens:** missing requirements, unaddressed scenarios, things assumed-but-not-stated. Public-release-week constraint elevates adopter-onboarding gaps and zero-history bootstrap.

**Round-3 verification of round-2 critical gaps in this lens:**
- **Project Discovery cascade — RESOLVED.** §Project Discovery names three concrete tiers (config file path `~/.config/monsterflow/projects`, auto-discovery sentinel `~/Projects/*/docs/specs/`, CLI args `--project` / `--projects-root`), specifies dedup as union, and notes adopter escape hatches for non-`~/Projects/` layouts. A3 covers cascade testing.
- **Drill-down `contributing_finding_ids[]` — RESOLVED.** Field present in JSONL schema (line 165) and in idempotency contract (sorted, diff-stable). A7 covers it. Dashboard column listed as collapsible.

Round 3 dropped both of round 2's gaps-lens blockers cleanly.

## Critical Gaps

None. The two round-2 blockers in this lens are closed and no new gap rises to blocker for a measurement-only, no-action spec shipping behind a gitignored data file.

## Important Considerations

1. **Adopter-with-zero-history first run is undefined.** Public-release adopter clones MonsterFlow, runs `/wrap-insights` on day 1: no `~/.claude/projects/<their-proj>/` subagent transcripts pre-date adoption (their old gates ran without instrumentation), no `findings.jsonl` exists yet, and no `docs/specs/` tree. Project Discovery tier (2) finds nothing, tier (1) doesn't exist, tier (3) wasn't passed. Spec doesn't say what `compute-persona-value.py` writes in that case — empty JSONL? No file? An informational stub? Dashboard tab behavior on empty/missing JSONL is also unspecified (does e9 "(never run)" rendering still work with zero data rows? probably yes via roster merge, but state it). A11 requires "≥10 historical gate runs" which an adopter won't have for weeks. Recommend: spec one-line behavior — "if no projects discovered OR all discovered projects have zero `findings.jsonl` rows, write an empty JSONL with a header comment line and exit 0; dashboard renders the full roster as '(never run)'."

2. **Tier-1 config file is mentioned but its lifecycle is not.** No spec line covers: who creates `~/.config/monsterflow/projects` (install.sh? user manually?), what happens if the file references a path that no longer exists (silently skip vs warn vs abort?), how an adopter discovers the file exists (docs? `--help` output?). For a public release this is the surface area where adopters self-serve. Recommend a one-paragraph "Config file lifecycle" sub-section: created on demand, missing-path entries skip with one-line stderr warning, documented in `compute-persona-value.py --help`.

3. **Multi-machine sync gap.** A user with a laptop + desktop runs `/wrap-insights` on each. Each writes its own `dashboard/data/persona-rankings.jsonl` (gitignored, so neither is shared). The 45-invocation window is per-machine, not per-user. Two machines with the same persona converge on different rates. Spec doesn't acknowledge this. Not necessarily a bug (cost data is local to the machine that ran the dispatch), but the per-machine semantics should be stated so adopters don't expect cross-machine aggregation. One sentence under Privacy or Edge Cases is enough.

4. **Worktree-derived parent-dir resolution leaks into Project Discovery.** Open Q2 acknowledges worktree subagents may sit under the original parent dir. If true, Project Discovery tier (2) scans `~/Projects/*/docs/specs/` and finds the worktree as a separate project — likely producing a duplicate row family or worse, a phantom project with zero findings.jsonl but real subagent transcripts (cost without value). Spec defers Q2 to `/plan` but doesn't pre-commit the policy: "worktrees collapse to their canonical parent project for window/aggregation purposes." State the intended policy now so `/plan` doesn't have to re-litigate scope.

5. **Schema versioning absent.** `persona-rankings.jsonl` rows have no `schema_version` field. Round-2 closed the e8 case for legacy `findings.jsonl` (no `personas[]`); the same forward-compat problem will apply to `persona-rankings.jsonl` itself once v1.1 (BACKLOG #3, roster scaling) lands and wants to add fields like `tier` or `composite_signal`. Idempotency contract pins the field list, which makes additive evolution lossy. Recommend adding `"schema_version": 1` to the row and noting "additive changes bump to 2; readers ignore unknown fields."

6. **No cleanup story for the JSONL file itself.** Edge case e7 covers deleted personas inside the window, but the JSONL grows unboundedly across (persona, gate) pairs over time — every persona ever run, even if their last `last_seen` is 2 years stale, persists forever. Window is per (persona, gate) but rows don't retire. For a long-running adopter this becomes a slow leak. Suggest: row TTL ("if `last_seen` > 365 days, drop on next compute") or an explicit "rows persist forever; this is fine because the count is bounded by `|personas| × |gates|`" decision documented in §Data & State.

7. **No telemetry on Project Discovery results.** When `compute-persona-value.py` runs, the user has no easy way to verify which projects it actually found. For a public-release tool with three discovery tiers, a one-line stderr summary ("Discovered 4 projects: /Users/foo/Projects/A, /Users/foo/Projects/B, ...") would close a large class of "why isn't my data showing up" support questions before they're asked. Cheap to add now, painful to add after adopters have started filing issues.

## Observations

- Privacy section (§Privacy) handles the public-release concern well — A0 redaction script + A10 leakage canary + A9 gitignore check is a tight three-gate pattern. No gap here.
- The "logging-shim path is a separate spec, not in-flight scope expansion" line in Open Questions #3 is exactly the kind of pre-commitment that prevents scope drift mid-build. Good.
- A1.5 elegantly defers the canonical-token-source decision to a test outcome rather than a spec-time guess. Good engineering.
- The hybrid roster/data merge for the dashboard (e9) is the right answer to "how do brand-new adopters see anything useful on day 1" — every persona shows as "(never run)" until data accrues. This partially mitigates Important #1 above but doesn't fully resolve the script-side empty-discovery behavior.
- BACKLOG.md #3 fast-follow promise: spec commits to it landing immediately after v1 with ≥10 validated runs. That's a process gap the spec can't enforce — worth a note that v1.1 spec should reuse this spec's `persona-rankings.jsonl` as input rather than re-deriving from raw transcripts.
- `/wrap-insights ranking` bare-arg form is mentioned in Integration but not defined in the `/wrap-insights` Phase 1c sub-section. Minor — likely caught by the docs-and-decisions reviewer, not a gap.

## Verdict

**PASS WITH NOTES** — round 3 closes both round-2 critical gaps in this lens (project discovery cascade + drill-down field). Remaining items are pre-public-release polish: zero-history first-run behavior, config file lifecycle, multi-machine semantics, worktree dedup policy, schema versioning, JSONL row TTL, and discovery telemetry. None blocks `/plan`; all should be addressed before adopters start filing issues.
