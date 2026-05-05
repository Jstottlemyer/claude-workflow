# Spec Review — Autorun Overnight Policy

**Reviewers:** requirements, gaps, ambiguity, feasibility, scope, stakeholders + codex-adversary
**Date:** 2026-05-04
**Source spec:** `docs/specs/autorun-overnight-policy/spec.md` (snapshot at `spec-review/source.spec.md`)

## Overall health: **Significant Gaps**

Six Claude reviewers and Codex landed convergent on the same theme: **the spec is operationally coherent but specifies several artifacts and primitives that don't exist yet (`queue/run-state.json`, `scripts/account-type-resolver`, `morning-report`) and depends on a partial artifact contract while explicitly deferring the contract spec.** Core safety claim ("security always blocks") is also weakened by an env var the spec quietly exposes. Resolve the structural gaps before `/plan`.

## Before You Build

### 1. Artifact reality check — three referenced artifacts don't exist yet

- **`queue/run-state.json` is described as "(existing)" but autorun today writes per-item `$ARTIFACT_DIR/state.json`, not a queue-level aggregator.** Decide: (a) create it fresh as a new artifact, or (b) extend the per-item `state.json` with `run_degraded` + `warnings[]`. Update §Data & State accordingly.
- **`scripts/account-type-resolver` doesn't exist as a script.** Closest artifact is `commands/_prompts/_resolver-recovery.md`. The spec says it consumes `_codex_probe.sh` — but if the resolver is Python (per `_resolve_personas.py` precedent), it can't `source` a bash file. Pick: resolver is shell → can source; resolver is Python → `bash _codex_probe.sh` outputs JSON to stdout; or document a Python sibling.
- **`morning-report` is referenced 6+ times but never defined** (schema, path, producer, consumer contract). All 6 Claude reviewers flagged this. Spec the artifact: who writes it, what fields, where it lives, how `notify.sh` consumes it.

### 2. Core safety claim is internally inconsistent

Spec says "security always blocks regardless of mode" (Summary, AC#4) but later allows `AUTORUN_SECURITY_POLICY=warn|block` env-var with supervised allowing override. **Codex flagged this as a high-risk weakening of the central guarantee.** Decide:
- **Tighten:** remove the env var entirely; security is hardcoded block in all modes.
- **Or weaken the claim:** remove "always blocks" language and document the conditional precisely.

Recommend the former — a single hardcoded block is the entire point of the carve-out.

### 3. `verdict_policy=warn` is dangerously underspecified

Codex (#16, #17) and Ambiguity (#3) raise: when `verdict_policy=warn`, does `NO_GO` downgrade to PR-only, or only `GO_WITH_FIXES`? The Q&A landed on `verdict_policy=block` for overnight, but the *meaning* of `verdict_policy=warn` (in supervised override or a future preset) was never defined. Recommend a per-verdict map:
- `GO` → never blocks
- `GO_WITH_FIXES` → respects `verdict_policy` (warn-eligible)
- `NO_GO` → always blocks regardless of policy

That gives users a sensible escape hatch (warn-on-fixes-only) without a quiet path to "ship NO_GO overnight."

### 4. `security_findings[]` extraction is brittle and over-broad

Spec says "any reviewer output authored by `security-architect` persona" → security finding. **Codex (#3) and Scope (#3) flag this:** every finding from that persona becomes a security blocker, even if it's about scope or testing. Tightened contract:
- Block only on findings explicitly tagged `sev:security` or `severity: security` (case-insensitive, with stated regex)
- Require `security-architect` persona doc to mandate the tag (not just recommend)
- Optionally warn if security-architect emits untagged findings (so you can see the gap)
- Define what counts as a "finding" in raw markdown — heading? bullet? structured tail block?

Also: precise regex (`(?i)\bsev:security\b|\bseverity\s*:\s*security\b`), line-vs-finding scope, code-fence/quote-block exclusion.

### 5. Concurrency / re-entrancy missing

If two `run.sh` invocations land on the same slug (or autorun + interactive `/check` collide), `check-verdict.json` and `run-state.json` race-write. **Gaps (#1) flagged it; Codex (#12) reinforced.** Recommend: run-specific state path (`queue/runs/<run-id>/run-state.json`), advisory lockfile, or PID-based mutex. Pick one.

### 6. `auto_merge` provenance + precedence undefined

Three reviewers flagged: spec adds `auto_merge: true` to config silently. Is it pre-existing or new? Where in CLI/env/JSON precedence? Acceptance criteria don't cover `auto_merge=false`. Either document as pre-existing (with current default), or carve out as its own micro-spec.

### 7. Branch-policy danger: `branch_policy=warn` can destroy work

**Codex (#6) and Ambiguity (#4) flagged.** "Reset proceeds; warning logged" can wipe useful local changes. Required hardening:
- Only reset if branch matches an exact pattern (`^autorun/<slug>$` — pin the regex)
- Capture pre-reset SHA + dirty diff to an artifact (`docs/specs/<slug>/pre-reset-<ts>.patch`) before reset
- Block if untracked files exist outside generated-artifact paths
- Never reset a non-autorun branch even with `branch_policy=warn` (already in spec, but make hardcoded)

### 8. `RUN_DEGRADED` cross-stage propagation mechanism not named

`run.sh` calls each stage as subprocess; setting `RUN_DEGRADED=1` in a child doesn't reach the parent. **Feasibility (#8) and Codex (#11) flagged.** Pick one mechanism:
- Child writes outcome to a shared file; parent reads after each stage
- Child exits with distinct code (e.g., 3 = warn) and parent maps
- Single durable state transition API in `_policy.sh` that appends warnings atomically to the state file and derives `RUN_DEGRADED` from it

### 9. Infra-error vs substantive verifier-finding boundary

**Requirements (#5) and Ambiguity (#1) flagged.** Closed enumeration required:
- Network errors mid-verification — infra or substantive?
- `claude -p` exits 0 with empty body — infra or substantive?
- Partial timeout (some personas completed) — partial findings substantive, or whole stage infra?
- Decision rule (e.g., `$INFRA_EXIT_CODES` regex on exit code, `$INFRA_PATTERNS` on stderr)

### 10. JSON parser dependency choice silent

Autorun today uses `python3 -c "import json"` (run.sh:97). Spec doesn't say whether `check-verdict.json` reads use jq (new dep) or python3 (existing). Pick. If jq, add to `scripts/doctor.sh` and install gating.

### 11. Malformed `check-verdict.json` interaction with `verdict_policy=warn`

**Stakeholders (#3) and Codex (#8) flagged.** Edge case #4 says malformed JSON → NO_GO. But under `verdict_policy=warn`, NO_GO downgrades to PR-only — *opposite of fail-closed*. Fix: malformed sidecar should hardcode-block (like security_findings), not be subject to `verdict_policy`. Codex suggests classifying as a separate `artifact_integrity=block` category for clearer reporting.

### 12. Adopter migration silent default-shift

External adopters who pulled previous autorun config get supervised semantics by default after this lands; their cron-scheduled `run.sh <slug>` (no `--mode`) silently changes behavior. **Stakeholders (#1) flagged.** Add: CHANGELOG entry, `doctor.sh` line that flags configs missing `policies` and recommends `"AUTORUN_MODE": "overnight"`, README section.

### 13. `autorun-shell-reviewer` subagent contract

AC#12 invokes the subagent on resulting `.sh` changes. Spec adds `_policy.sh` + `_codex_probe.sh` with new primitives the subagent's 13-pitfall list hasn't seen (sourced helper + `set -e` interactions, sticky `RUN_DEGRADED`, `policy_act()` eval-style behavior). **Stakeholders (#2) flagged.** Either expand the subagent's checklist as part of this spec, or enumerate the new patterns the reviewer must check.

### 14. `policy_act(axis, reason)` API is under-specified

**Codex (#13).** Helper needs exact behavior:
- stdout vs stderr?
- return code on warn (0?) vs block (nonzero?)
- mutates run-state file?
- reason JSON-escaping?
- enforces valid axis enums?
- can callers add stage names?

### 15. Fail-closed on invalid config values

**Codex (#14).** If config has `"warn "` or `"warning"` (typo) or invalid JSON, does the run block, warn, or fall back? For unattended safety, **invalid policy config should block early with a clear startup error**, not silently fall through.

### 16. `finding_id` source unspecified

Schema requires `finding_id: "string"` but reviewer raw output is unstructured markdown. **Requirements (#3).** Specify: synthesis generates by hashing cluster signature (matches existing persona-metrics convention from `findings.schema.json`), or pulls from a structured tail block.

## Important But Non-Blocking

- **Persona-metrics blindness during overlap window** — until `autorun-artifact-contracts` lands, every overnight run produces zero per-persona records. Acknowledge in Out of Scope: "Autorun runs continue invisible to persona-metrics until the followup ships."
- **Deprecation window must be pinned to a VERSION** — "one release of overlap" is ambiguous. Tie to e.g. v0.9.0.
- **`policy_outcome` line format normative spec** — `<reason>` containing colons would break a parser. Either escape, switch to JSON, or pin grammar.
- **Schema-version evolution policy** — what does autorun do when it sees `schema_version: 2`? Codex (#23) — readers MUST refuse unknown versions with clear error.
- **`grep -E '^OVERALL_VERDICT:|NO-GO'` fallback ordering** — current pattern matches both first-line marker AND any "NO-GO" in body discussion. Order: parse first line first; only fall back to whole-file scan if first line doesn't match the marker. Also: normalize `NO-GO` ↔ `NO_GO`.
- **CODEX_HIGH_COUNT × RUN_DEGRADED interaction at auto-merge gate** — both gates can trip simultaneously; morning-report semantics need to handle both being non-clean.
- **AC#9 missing test for the headline behavior** — "warn → RUN_DEGRADED=1 → auto-merge skipped" is the spec's whole point but isn't in the enumerated test cases. Add it.
- **Audit trail for resolved policy source per axis** — when Justin debugs at 7am, he should see `verdict_policy=warn (source: cli)` persisted in the state file, not just stdout.
- **Per-axis CLI flags** — only `--mode` documented; per-axis flags absent. Either document the absence or add (`--verdict-policy=warn`).
- **Smaller MVP option** — Scope (#4) raised: ship `verdict_policy` + `check-verdict.json` only; defer the other 3 axes. Spec doesn't acknowledge this option. Either justify all-four-together or carve out phase 2.
- **Auth-state failure mode** — `gh auth: token expired` at 3am at PR creation time isn't covered by any axis. Either add `auth_policy` axis or make auth a hardcoded preflight.
- **`security-architect` persona absence fallback** — if user's roster swaps it out, security carve-out silently stops working. Add fallback to tag-only scan + log notice.
- **PR-only assumes PR creation succeeds** — Codex (#9): warns can occur before there is a valid branch/commit/diff/remote/auth. Add states: `completed-no-pr` / `artifact-only` if degraded but PR creation failed.
- **Verifier-warned PR must carry blocking GitHub status/check** — Codex (#10): `verify_infra_policy=warn` lets unverified merge slip through GitHub UI. Add a status `autorun/verified=neutral` on warned runs so GitHub itself prevents merge.
- **Bash 3.2 patterns for `_policy.sh` API surface** — no assoc arrays; use parallel arrays or function dispatch (`policy_for_axis verdict` echoes "warn"|"block"). Document in spec.
- **Synthesis-side JSON robustness** — Codex (#44) suggests synthesis writes markdown only; deterministic post-processor extracts first verdict line and writes JSON. Reduces LLM JSON-validity risk.

## Observations

- Edge case section (13 items) is unusually thorough — strength.
- Out-of-scope discipline good.
- `tests/run-tests.sh` orchestrator wiring explicitly called out — addresses the test-orchestrator-wiring-gap memory directly.
- Three-layer precedence (CLI > env > JSON > default) is well-conceived; needs the `--mode` preset placed precisely in the ladder.
- Back-compat story (grep fallback + deprecation log) is clean modulo the version-pin gap.
- "Warn → PR-only" invariant (AC#5) is the cleanest part of the spec.
- `commands/check.md` change affects interactive `/check` users (additive: sidecar emit + first-line marker). Worth a CHANGELOG note even though behavior unchanged.
- **Codex policy-classes alternative (#43):** instead of axis-only knobs, classify decisions: `integrity:block`, `security:block`, `destructive_git:block-unless-autorun-owned-and-backed-up`, `verification_unavailable:warn-but-mark-PR-blocked`. Worth considering for v2 — keeps current per-axis design but with semantically-grouped defaults.
- **Codex GitHub-status-gate alternative (#45):** defer auto-merge by GitHub status check (`autorun/merge-capable`) instead of shell state alone. Prevents accidental web-UI merge of degraded runs.
- "Warn-streak" counter for chronically-warn-ing infra would be a future `/wrap-insights` enhancement — backlog candidate.

## Reviewer Verdicts

| Dimension | Verdict | Key Finding |
|-----------|---------|-------------|
| Requirements | PASS WITH NOTES | morning-report format/location not defined; security_findings[] extraction algorithm under-specified; finding_id source unspecified |
| Gaps | PASS WITH NOTES | Concurrent run protection missing; auto_merge precedence undefined; gh/claude/codex auth-state failure mode unspecified; notify.sh contract undefined |
| Ambiguity | PASS WITH NOTES | Infra-vs-substantive verifier boundary fuzzy; sev:security regex imprecise; precedence on invalid input undefined; autorun-branch detection rule missing |
| Feasibility | PASS WITH NOTES | run-state.json doesn't exist; resolver script doesn't exist; jq vs python3 dep choice silent; LLM-JSON robustness vs malformed-vs-missing distinction |
| Scope | PASS WITH NOTES | auto_merge silently new; deprecation window not pinned to version; synthesis security extraction depends on data not in structured form (the queasy seam) |
| Stakeholders | PASS WITH NOTES | Adopter migration silent default-shift; autorun-shell-reviewer contract gap for new helpers; malformed-JSON × verdict_policy=warn opposite-of-fail-closed |

### Codex Adversarial View

Codex landed 10 high-risk and 10 medium-risk findings, plus 20 missing failure modes. Items NOT covered by the 6 Claude reviewers:

- **`AUTORUN_SECURITY_POLICY=warn` weakens the central safety claim** — remove the knob entirely or stop calling it "always blocks" (high-risk).
- **`verdict_policy=warn` semantics undefined per verdict value** (`NO_GO` downgrade is a big safety decision and currently implicit).
- **PR creation failure is a class the spec doesn't cover** — warns can occur before a valid branch/commit/auth exists; need `completed-no-pr` outcome state.
- **`verify_infra_policy=warn` lets unverified merge happen via GitHub UI** unless the warned PR carries an explicit blocking status check.
- **Branch-dirty reset can destroy generated artifacts** — must capture pre-reset patch/stash before any reset.
- **Morning report should use machine fields, not strings** (`{merge_capable: false, requires_review_reason: "warnings"}`) instead of `PR-awaiting-merge` vs `PR-awaiting-review`.
- **Synthesis JSON should be code-generated, not prompt-only** — have synthesis write markdown, then a deterministic wrapper extracts and validates JSON.
- **Auto-merge defer via GitHub status check** — adds defense-in-depth beyond shell state.
- **Run-specific state paths** instead of global `queue/run-state.json` — eliminates concurrency races.
- **Codex flags this spec is larger than it claims** and that `autorun-artifact-contracts` is likely a prerequisite, not a follow-up. Worth re-evaluating the spec split.

## Conflicts Resolved

No major conflicts between Claude reviewers — they converged. The single tension is between the per-axis warn/block model (current spec) and Codex's policy-classes alternative (#43). The per-axis model is locked from Phase 1 Q&A; classes are deferred as a v2 evolution.

## Persona Metrics

Findings, participation, and run.json artifacts emitted to `docs/specs/autorun-overnight-policy/spec-review/` per `findings-emit@1.0`. `persona-metrics-validator` subagent recommended at `/wrap-insights` time.

---

## Recommendation

**Refine before `/plan`.** The spec is structurally sound but has 16 critical gaps that will all surface as planning ambiguities. Highest-leverage refinements:

1. Resolve the three "doesn't exist yet" artifact issues (run-state.json, resolver, morning-report) — pick paths and update §Data & State + §Files modified.
2. Either remove `AUTORUN_SECURITY_POLICY` entirely or weaken the safety claim in Summary.
3. Define `verdict_policy=warn` per-verdict-value mapping (`NO_GO` always blocks; only `GO_WITH_FIXES` is warn-eligible).
4. Tighten `security_findings[]` extraction to tag-required, with explicit regex.
5. Define the concurrency model (run-specific state path or lockfile).
6. Pin the dependency choice (jq vs python3) and language for the resolver.
7. Add the `policy_act()` API contract and the `_policy.sh` sourced-helper safety patterns.
8. Pin the deprecation window to a VERSION.
9. Add the malformed-JSON-as-hardcoded-block rule (decoupled from `verdict_policy`).
10. Acknowledge persona-metrics blindness during overlap in Out of Scope.

Approve to proceed to `/plan`? (`approve` / `refine <what to change>`)
