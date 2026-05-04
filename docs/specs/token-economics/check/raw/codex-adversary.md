**Verdict: NO-GO before code.** The plan is close structurally, but there are several implementation assumptions that will either fail immediately or produce misleading metrics.

**Blocking Findings**

1. **`session-cost.py` cannot be imported as `session_cost`.**  
   The file is [scripts/session-cost.py](/Users/jstottlemyer/Projects/MonsterFlow/scripts/session-cost.py:1), with a hyphen. `sys.path` insertion will not make `from session_cost import PRICING, entry_cost` work. Use `importlib.util.spec_from_file_location`, rename/add an adapter module, or accept touching this boundary explicitly.

2. **`jsonschema` is an undeclared dependency.**  
   The plan relies on `jsonschema.validate`, but this repo has no `requirements.txt`/`pyproject.toml`, and existing scripts are mostly stdlib. The plan also says “stdlib only” for scalability. Either add dependency installation/docs/tests, or implement the narrow allowlist validator yourself. Public-release-week is a bad time to introduce an implicit Python package requirement.

3. **Cost still has no valid join to the artifact-directory window.**  
   The spec says v1 windows over `docs/specs/<feature>/<gate>/` artifact directories, but the cost walk emits `(persona, gate, parent_session_uuid)`. There is no stable key from parent session JSONL to a specific feature artifact directory. This makes `total_tokens`, `avg_tokens_per_invocation`, and especially `cost_only` look artifact-windowed when they are not.  
   Fix options: add explicit `run_id/session_id/feature` capture to gate artifacts first, or downgrade v1 cost semantics to “machine-local aggregate by persona/gate over observed Agent dispatches,” clearly separate from value-window denominators.

4. **Silent personas will be misclassified as “never run.”**  
   Existing metrics deliberately emit [participation.jsonl](/Users/jstottlemyer/Projects/MonsterFlow/commands/_prompts/findings-emit.md:94) for personas that ran with zero findings. The plan mostly keys rows from `findings.jsonl` personas and roster sidecar. A persona with `participation.status: ok` and `findings_emitted: 0` must become a measured row with zero retained findings, not a roster-only “never run” row. Otherwise low-noise personas are invisible or mislabeled.

5. **`--list-projects` conflicts with the privacy/logging model.**  
   The CLI promises `--list-projects`, while telemetry is counts-only and paths are interactive-only/debug-only. A project list without paths is useless; a path list violates the stated steady-state privacy rule. Define whether `--list-projects` is interactive-only, debug-gated, or removed.

**Major Risks / Sequencing Fixes**

6. **Path validation may break the planned tests.**  
   `validate_project_root()` rejects non-absolute paths and paths outside `$HOME`, but tests often use fixture-relative or `/tmp` paths. A3/scan-confirmation tests need to pass absolute fixture paths under the repo, or set `MONSTERFLOW_ALLOWED_ROOTS` explicitly.

7. **A4 overstates content-hash reset enforceability.**  
   The spec admits historical dispatches lack persona-content hashes, but A4 still asserts pre-edit `contributing_finding_ids[]` are cleared. Without per-dispatch hash capture, you can only clear drill-down by intentionally discarding all prior rows for that current persona hash. That is a product decision, not a consequence of available data.

8. **The deliberate-failure fixture needs test-runner isolation.**  
   `leakage-fail.jsonl` is supposed to fail “when run alone,” but normal `tests/run-tests.sh` cannot include it in the same pass path unless the allowlist test explicitly excludes it, then invokes a separate expected-failure subtest. Spell that out.

**Better Approach**

Ship v1 as two honestly separated signals:

- Value metrics by artifact directory using `run.json`, `findings.jsonl`, `participation.jsonl`, `survival.jsonl`, and `raw/*.md`.
- Cost metrics by observed Agent dispatch `(persona, gate)` only, with no claim that cost is aligned to the same 45 artifact-directory window.

Then make v1.1 capture `agent_tool_use_id`, `parent_session_uuid`, `run_id`, `feature`, and `persona_content_hash` at gate execution time. That is the first version where per-artifact cost/value economics become defensible.

**What I’d Keep**

The allowlist privacy gate, file:// sidecar bundle pattern, counts-only telemetry default, and dashboard as passive renderer are good choices. The implementation should not start until the import/dependency issues and cost/value join semantics are corrected.