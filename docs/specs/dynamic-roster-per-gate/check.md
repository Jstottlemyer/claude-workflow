OVERALL_VERDICT: NO_GO

# Plan Check — dynamic-roster-per-gate

Synthesis of 6 specialist reviewers. Two FAIL verdicts (security-architect, scope-discipline) plus four PASS WITH NOTES. Four `sev:security` findings trigger the hardcoded security block; independently, scope-discipline and architectural sequencing concerns (lineage-backfill ordering, orchestrator rate-limit path, scope bundling) recommend a /plan re-synthesis pass.

## Reviewer Verdicts

| Reviewer | Verdict | Must-Fix Count | Notes |
|---|---|---|---|
| completeness | PASS WITH NOTES | 4 | Missing-task gaps; D7 fallback, tier_policy merge, `--allow-tier-fallback`, fit_tags lint |
| risk | PASS WITH NOTES | 3 | Task 7 sequencing, orchestrator rate-limit, constitution rename recovery |
| scope-discipline | **FAIL** | 3 | MVP bundles 3 ship-units; speculative complexity (specificity_factor, escape hatches, --explain) |
| security-architect | **FAIL** | 4 (all sev:security) | D7 wrapper-file injection, NFKC normalization, fence parser, `tags_provenance` re-validation |
| sequencing | PASS WITH NOTES | 2 | Lineage backfill after resolver consumes it; autorun gate-shell deps off-by-one |
| testability | PASS WITH NOTES | 4 | Fixture-cap vs wall-clock contradiction, empirical evidence artifact, A21–A23 negative paths, schema validation AC |

## Must Fix (Blocking)

**Security (hardcoded blockers — 4):**
1. **S1 — D7 fallback wrapper-file path is a persistent prompt-injection surface.** SIGKILL leaves `_dispatch-*.md` in `~/.claude/agents/`; concurrent runs collide; path-traversal at write site. Requires trap-based cleanup + startup sweeper + PID/seq suffix + re-validation at write site.
2. **S2 — `_tag_baseline.py` lacks NFKC normalization** → Cyrillic homoglyphs (`аuth`) defeat the SEC-02 floor. Must NFKC + strip zero-width before regex; fixture required.
3. **S3 — Code-fence exclusion grammar unspecified.** Pin CommonMark backtick semantics; add hide-keyword + show-keyword fixtures.
4. **S4 — `tags_provenance.baseline` is author-writable** → resolver MUST recompute and assert `recorded ⊆ recomputed` at every dispatch; recorded provenance is informational only.

**Architectural / scope (independent of security):**
5. **Scope FAIL — bundled ship-units.** Carve constitution-rename (D14, tasks 29–30) to a sibling spec; defer escape hatches (tasks 27, 28) and `--explain` formatter (tasks 31, 32, 41) to BACKLOG until concrete user friction surfaces. Cut specificity_factor (D1) until persona-author drift is observed.
6. **Sequencing M1 — lineage backfill (task 46) lands AFTER resolver (task 12) reads on `lineage == "claude"`.** v0.10.0 MVP ships content-blind. Either move backfill into W2 or have resolver default missing `lineage` to `"claude"` (cheaper).
7. **Sequencing M2 — autorun gate shells off-by-one.** Tasks 23/24/25 deps must be `12,14` / `12,15` / `12,16` respectively, not all `12,16`.
8. **Risk MF-1 — task 7 (Agent-tool model precedence) is W2 parallel but plan-blocking.** Move to a pre-W2 gate; record empirical evidence as artifact (per testability MF-2) before W2 helpers commit to caller-override path.
9. **Risk MF-2 — orchestrator rate-limit handling undefined.** D10/task 13 covers panel reviewers; the host Claude session itself (pinned Opus per `tier_policy.orchestrator: opus`) has no documented 429 path.
10. **Risk MF-3 — D14 "both files exist" halt has no recovery recipe.** Ship `scripts/migrate-pipeline-config.sh` or carve the rename per (5) above.

## Should Fix (Warn — apply inline if possible)

- **Completeness 1–4:** add explicit tasks for tier_policy merge code, `--allow-tier-fallback` (or strike), fit_tags >6 CI lint, D7 contingency tasks.
- **Completeness 5–11:** schema validation for spec.md `tags:`, schematize or remove `selection-history.jsonl`, AST-banlist test, edge-case fixture enumeration, threat-model doc, `tags_set_size_distribution` metric, Codex-unavailable regression assertion.
- **Risk SF-1:** verify Opus synthesis budget separately (1200s persona vs 1800s stage tight margin).
- **Risk SF-2:** smooth `specificity_factor` (cliff at fit_tags=4 is gameable).
- **Risk SF-4:** resolver back-compat for missing `lineage` field (couples with M1).
- **Risk SF-5:** raise fixture cap to ~40 with rationale or fold concurrent-write/rate-limit into the 6 edge slots.
- **Sequencing S2:** serialize `29 → {27, 28}` in W6 to avoid shared-file race on `commands/*.md`.
- **Sequencing S3, S4:** add task 2 to task 18 deps; add task 10 to task 20 deps.
- **Testability MF-1:** restate A18 as `≥33 fixtures, <15s wall-clock`; the 40–60 number contradicts the D12 cap.
- **Testability MF-2:** require `dispatch-precedence-evidence.md` artifact from task 7.
- **Testability MF-3:** expand A21–A23 negative-path coverage; add network-zero assertion to A23 (mutation-zero `--explain`).
- **Testability MF-4:** add AC: resolver validates `selection.json` against schema pre-write.
- **Security S5–S9:** AST-banlist enforcement test; followup-row write durability; backup-dir `chmod 700/600`; `$USER` actor provenance hardening; resolver-internal pins.json/registry.json paths.

## Decision Path

The plan is structurally sound (waves well-sequenced, MVP cuts coherent, parallelism mapped, orchestrator-wiring task explicit per `feedback_test_orchestrator_wiring_gap`). However:

1. **Four `sev:security` findings hit hardcoded block** (per `feedback_security_n_attempts_before_block` — autorun allows up to N=3 resolution attempts before halt; this is iteration 1).
2. **scope-discipline FAIL** independently recommends re-synthesis to carve the constitution rename and defer speculative complexity.
3. **Sequencing M1 + M2** are correctness fixes; M1 in particular means v0.10.0 MVP ships content-blind unless addressed.

**Route back to /plan** for a focused revision pass. Priority: address S1–S4 inline in `_tag_baseline.py` / D7 / `tags_provenance` semantics; apply scope cuts (MF1–MF3) to drop ~5 tasks; fix sequencing deps (M1, M2). Should-Fix items can land as inline plan edits during the same revision rather than requiring another full check cycle.

After revision, re-run /check; expect a single re-cycle to resolve to GO_WITH_FIXES.

