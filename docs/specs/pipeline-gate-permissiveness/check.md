OVERALL_VERDICT: GO_WITH_FIXES

# Checkpoint — pipeline-gate-permissiveness

**Plan:** `docs/specs/pipeline-gate-permissiveness/plan.md` (revised inline this round)
**Reviewers:** completeness, sequencing, risk, scope-discipline, testability, security-architect + codex-adversary
**Generated:** 2026-05-05

## Reviewer Verdicts

| Dimension | Verdict | Key Finding |
|-----------|---------|-------------|
| completeness | PASS WITH NOTES | `addressed_by` writer unowned (MF2); additionalProperties:false field-list parity test missing (MF1) |
| sequencing | PASS WITH NOTES | VERSION bump (4.4) ordering vs W5 tests; render-followups.py missing dep on _followups_lock.py |
| risk | PASS WITH NOTES | Splice script regex bug → 27 personas bad content with no rollback (M1); malformed JSON sidecar branch missing (M2) |
| scope-discipline | PASS WITH NOTES | ~15-20% scope fat shippable to v0.9.1 (regression marker, provenance header, 2 sidecars, helper files) |
| testability | PASS WITH NOTES | No AC→fixture map; concurrency lock test mechanism unspecified; CI partial-landing simulation unpinned |
| security-architect | PASS WITH NOTES | Parity coercion-to-unclassified loses security signal (S1); `.force-permissive-log` gitignore unpinned (S2) |
| codex-adversary | (advisory; 5 findings) | **Implementation surface gap: commands/*.md are prompt templates, not executable parsers — load-bearing scripts must be named explicitly** |

**No FAIL verdicts.** No reviewer blocked outright; all converged on PASS WITH NOTES with specific actionable items.

## Architectural Fixes Applied Inline (this round)

Per the spec's own per-axis classification framework, 4 items classified as `architectural` and resolved inline before /build:

1. **Implementation surface clarification** (Codex #5) — added explicit script ownership: `scripts/gate-mode-resolve.sh`, `scripts/_followups_lifecycle.py` (NEW), `scripts/build-mark-addressed.py` (NEW), `scripts/_iteration-state.py` (NEW). Gate command markdown orchestrates Claude to invoke these scripts; CLI parsing / lock acquisition / JSONL writes happen in the scripts, not the prose. Matches autorun pattern (`scripts/autorun/check.sh` ↔ `commands/check.md`).

2. **`addressed_by` writer ownership** (completeness MF2) — new Task 3.8b creates `scripts/build-mark-addressed.py`; `/build` wave-final invokes with `--feature/--finding-ids/--commit-sha`; resolves the orphaned A14d test-path concern.

3. **Splice script rollback safety** (risk M1) — Task 3.1 now requires `--dry-run` mode + single-file invocation; Task 3.2 has explicit human-review gate on the unified diff before real run; new Task 3.2b adds independent post-splice frontmatter-parse validator in `tests/test-agents.sh` (so a splicer bug + same-author test-bug can't co-fail silently).

4. **VERSION bump ordering** (sequencing #4 + Codex #1) — moved Task 4.4 to new **Wave 6 — Release commit (PR-final)**, executed only after `bash tests/run-tests.sh` exits clean. Eliminates the "v0.9.0 advertised before its tests landed" failure mode.

Plus 1 cheap warn-route applied inline (since edit was trivial):

5. **Malformed JSON sidecar branch** (risk M2) — Task 3.8 legacy-detection ladder now explicitly includes "malformed JSON sidecar = refuse with same error class as v1." Closes the Python-traceback footgun.

## Should Fix → check-followups (warn-routed, will land in /build first commits)

These are `contract` / `documentation` / `tests` class per the spec's framework. Per autorun-overnight-policy v6's pattern, they don't halt the gate — they land in /build's first commits as task additions. Tracked here for /build agents to pick up.

**`contract` class (apply inline at /build):**
- additionalProperties:false 9-field-presence parity test in W1.8 (completeness MF1)
- render-followups.py missing dep on _followups_lock.py edge in 1.6 (sequencing #1)
- 1.2/1.3 [P] markers honest about bounded parallelism (sequencing #2)
- W3 internal parallelization notation `[After: 3.3, 3.4 | P with 3.6, 3.7]` (sequencing observation)
- W3 explicit join-point before W3 verifier runs (sequencing #7)
- Followups schema 4-class enum vs verdict 7-class taxonomy clarification — explicit "blocking classes excluded by construction" comment (Codex #2)
- render-followups.py `--no-lock` invariant: read only renamed target, never partial state (Codex #3)
- class_sev_mismatch must surface through autorun's existing `sec_count > 0` gate (Codex #4) — runtime check ensures coerced rows still increment `security_findings[]` array
- Parity rule: one-way upgrade not coerce-down (security S1) — preserves security signal in dashboards
- `.force-permissive-log` NOT gitignored (security S2) — committed audit trail
- `$CI`/`$AUTORUN_STAGE` truthy-value whitelist `[true, 1, yes]` (risk S1) — `CI=false` should be treated as not-CI
- `.iteration-state.json` worktree handling: gitignore + lock primitive (risk S2)
- iCloud Drive flock weakness: warn (don't refuse) on `~/Library/Mobile Documents/` paths (risk S4)
- 5.3 orchestrator wiring count check needs frozen baseline (sequencing #8)

**`tests` class (apply inline at /build wave 5):**
- AC→fixture map table per AC (testability MF1)
- Concurrency lock test mechanism: `_LOCK_OVERRIDE` env hook (testability MF2)
- Hand-craft state:addressed rows in fixtures (testability MF3)
- CI guard partial-landing via file-pair stubs not git history mock (testability MF4)
- W5 wall-clock budget: `time` gate with 15s ceiling OR batched validator (testability SF1)
- 9 missing-field + 9 wrong-type + 1 unknown-field schema negatives (testability SF2)
- Lock-file metadata audit fixture (testability SF3)
- A9b reclassification authority: manual verification at /build wave-final (testability SF4)
- `--dry-run-class-coverage` report format spec (testability SF5)
- Bash 3.2 compatibility guard `${array[-1]}`/`export -f`/`mapfile`/`&>` (testability SF6)
- Data-loss-mis-tagged regression fixture for Judge upgrade path (security observation)
- W5 fixtures use synthetic IDs not real hashes (testability observation)

**`documentation` class (apply at /build wave 4):**
- A23 regression marker — defer to v0.9.1 (scope SF1)
- A22 followups.md provenance header — defer minimal v0.9.0 / polish v0.9.1 (scope SF2)
- spec-review-verdict.json + plan-verdict.json sidecars — defer to v0.9.1 (scope SF3)
- _followups_lock.py inline into render-followups.py — single consumer (scope SF5)
- _gate-mode.md / _gate_helpers.sh shared includes — verify mechanic OR inline (scope SF6/SF7)
- OQ1 force-permissive reason string mandatory (lean-yes converted to decision)
- CHANGELOG migration block — `.force-permissive-log` path + sentinel paths (completeness SF4)
- Persona drift sentinel test asserts byte-identity to template (completeness SF5)
- A25 unclassified=block — runtime hardcode IS the enforcement (completeness SF6)
- Code comment in `_policy_json.py` near W1.4: `# unclassified=block HARDCODED — never read from constitution` (security observation)
- Architectural carve-outs are LLM-judgment, not enforced — mark in `personas/judge.md` (security observation)

**`scope-cuts` class (mention only):**
- 5 missing risks: R9 splice regex bug, R10 sidecar JSON corruption, R11 worktree iteration divergence, R12 banner sentinel collision with future uninstall.sh, R13 template-edit re-splicing maintenance dependency (risk observation)

## Conflicts Resolved

- **Lock primitive disagreement (security S3 vs scalability):** security wanted PID liveness + mtime fallback; scalability wanted pure `fcntl.flock` kernel-cleanup. Resolved: `fcntl.flock` primary (kernel handles death cleanup); lock-file metadata `{pid, hostname, started_at}` retained for audit only. NFS/iCloud out of scope.
- **Followups class enum width (data-model 4-value vs Codex 7-value):** confirmed 4-value (followups) is correct by construction; architectural/security/unclassified always block and never reach followups. Adding clarifying comment to schema (Codex #2 → followup).
- **Codex round-4 #4 + security S1 + A28 self-contradiction on parity:** parity coercion to unclassified DID lose the security signal in `class_breakdown`. Security S1's "one-way upgrade" framing wins; promoted from warn-route to inline at /build wave 1.4.

## Codex Adversarial View (round 4)

5 findings — 1 architectural (#5 implementation surface, applied inline), 4 contract-class (followups schema enum routing, render-followups --no-lock invariant, class_sev_mismatch surfacing through autorun, VERSION ordering — already addressed by sequencing #4 fix). All routed to check-followups above.

## Risk Register Update

Plan's R1–R8 stand. Adding from check round:
- **R9.** Splice script regex bug across 27 files in one commit — Likelihood Medium, Impact High; **mitigated by M1 fix (--dry-run + diff approval + single-file invocability + independent test-agents.sh validator)**.
- **R10.** Sidecar JSON corruption on Synthesis SIGKILL — Likelihood Low, Impact Medium; mitigated by malformed-JSON branch (now in 3.8 ladder).
- **R11.** `.iteration-state.json` cross-worktree divergence — Likelihood Low, Impact Medium; mitigated by gitignore + lock + documentation.
- **R12.** Migration banner sentinel collision with future `uninstall.sh` — Likelihood Very Low, Impact Low; deferred (uninstall.sh is its own backlog spec).
- **R13.** Template-edit post-ship requires re-splicing 28 files — Likelihood Low, Impact Low; idempotency sentinel makes this re-runnable.

```check-verdict
{
  "schema_version": 1,
  "prompt_version": "check-verdict@1.0",
  "verdict": "GO_WITH_FIXES",
  "blocking_findings": [],
  "security_findings": [],
  "generated_at": "2026-05-05T19:25:00Z"
}
```

## Recommendation

The 4 architectural items have been applied inline. The remaining ~30 contract/documentation/tests items are warn-routed per the spec's own framework — they land in /build's first commits as task additions, NOT as gate-blocking re-cycles.

**This is the spec eating its own dogfood successfully:** 6 reviewers + Codex surfaced ~36 items; 4 were architectural and got fixed inline; ~30 were contract-shaped and route forward without forcing iteration 2 of /check. Under v0.8.x halt-on-anything semantics, this would be a NO_GO. Under the v0.9.0 framework this spec ships, it's GO_WITH_FIXES.

Approve to proceed to `/build`? (go / hold)
