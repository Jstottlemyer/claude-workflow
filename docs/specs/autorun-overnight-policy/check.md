OVERALL_VERDICT: GO_WITH_FIXES

# Plan Checkpoint v4 — Autorun Overnight Policy

**Reviewers:** completeness, sequencing, risk, scope-discipline, testability + codex-adversary
**Date:** 2026-05-05
**Source plan:** `docs/specs/autorun-overnight-policy/plan.md` (v5)
**Prior check:** v3 NO-GO over D42 nonce architectural failure (Codex H2: model-echoed secrets are not trust boundaries). Resolved in v5 via Option C: drop nonce; document residual; carve `autorun-verdict-deterministic` follow-up spec.

## Overall verdict: **GO WITH FIXES**

All 5 Claude reviewers returned **PASS** (Sequencing) or **PASS WITH NOTES** (Completeness, Risk, Scope-discipline, Testability) — **zero Must-Fixes** from any Claude reviewer. Codex returned **2 Highs + 4 Mediums + 4 Lows** — qualitatively different from v3 (5 architectural highs); v5's remaining gaps are documentation, framing, and scheduling realism, not architecture.

Codex's bottom line: *"v5 properly removed the broken nonce trust boundary and closed the iteration-3 nonce-related highs. The main remaining issue is not stale nonce references; it is product/security posture."*

The 2 Codex highs — R18 visibility to overnight adopters + R18 mitigation framing honesty — are pre-build documentation fixes, not architectural rework. Total remediation effort: ~30-45 minutes plan v6 + spec amendment (or land them inline at /build).

## Reviewer Verdicts

| Dimension | Verdict | Key Finding |
|-----------|---------|-------------|
| Completeness | PASS WITH NOTES | All 26 ACs covered; check v3 must-fixes traceable; 5 SF observations (BACKLOG grep, prompt_version AC, dry-run stub fence) |
| Sequencing | **PASS** | All 6 v5 deltas land correctly; critical path 8 hops consistent; 1.0 gates schemas; 5.6 audit before 5.7 preship |
| Risk | PASS WITH NOTES | R14/R15/R17 verifiably resolved; net risk **decreased** (nonce removal closed env-leak axis); R18 honestly Med×High; SF-RISK1 doctor.sh visibility |
| Scope Discipline | PASS WITH NOTES | Endorses Option C carve-off; net scope shrank; 3 prior cuts still recommended (fixture-e, 8-perm reduction, banner test) |
| Testability | PASS WITH NOTES | 4 SF promotions (T1/T2/T3/T4) landed; SF-T7 env-isolation pinned; SF-T5 (`extract_fence` fuzz) now highest-leverage post-Option-C add |
| **Codex Adversary** | **GO WITH FIXES (2 highs)** | R18 visibility insufficient at adopter surface (H1); R18 mitigation framing too soft (H2 — detection-hardening, not prevention) |

## Must Fix Before Building (2 items)

### Codex Highs — Documentation & framing (not architecture)

**MF1. Codex H1 — R18 residual not visible to overnight adopters.**
Spec AC#25 + synthesis prompt requirement #5 + plan R18 document the residual single-fence-spoof class. But adopter-facing surfaces only get CHANGELOG migration notes and doctor.sh `policies` checks. *"Someone enabling overnight autorun may never read the spec."*

**Fix:** add an explicit v1 limitation notice to **three** surfaces:
- `CHANGELOG.md` — "Known v1 limitation" header with the R18 statement.
- `scripts/doctor.sh` — emit one-line note on every run: *"autorun v1 ships with known prompt-injection residual class (single-fence-spoof). See BACKLOG.md → autorun-verdict-deterministic."*
- `scripts/autorun/run.sh --help` (or `review.md`) — same notice plus *"Do not use unattended auto-merge on untrusted prompt-bearing content until autorun-verdict-deterministic lands."*

This is the SF-RISK1 finding from Risk reviewer plus Codex's reinforcement.

**MF2. Codex H2 — R18 mitigation language is too soft.**
Plan v5 R18 row says mitigation is *"prompt-hardening language, heuristic."* After Codex H2 already proved model-compliance is not a boundary, this language reads as a security control when it is not. The blast radius if a forged single fence produces `GO` is **unattended auto-merge**.

**Fix:** rewrite R18 mitigation as **detection-hardening, not prevention**. Concretely:
- Spec AC#25 + synthesis prompt requirement #5 + plan R18: state that D33 multi-fence rejection blocks the *easy* attack class but does NOT authenticate a single fence quoted from reviewed content.
- Add policy recommendation in CHANGELOG: *"For repos processing untrusted spec sources (third-party PRs, externally-authored queue items, etc.), set `verdict_policy=block` and disable unattended auto-merge until autorun-verdict-deterministic ships."*
- Existing AC#7 auto-merge gates (`RUN_DEGRADED=0` AND `CODEX_HIGH_COUNT=0`) remain the runtime risk floor. No new gates needed for Justin's trusted-input scenario; the recommendation covers adopter-facing edge cases.

## Should Fix (~12 items, deferrable)

### Codex Mediums

**SF1. Codex M1 — Stale "deterministic post-processor" wording in 3.2.** D33 is *deterministic fence extraction*, not deterministic verdict derivation. The architectural fix carved into `autorun-verdict-deterministic` is the actual deterministic-verdict spec. Rename 3.2's description to "fenced-output extractor/post-processor (D33)" and reserve "deterministic verdict" for the follow-up.

**SF2. Codex M2 — `autorun-verdict-deterministic` is XL, not L.** Changes trust model + reviewer output contract + synthesis role + aggregation rules + schema semantics + tests + migration + likely manual `/check`. Update BACKLOG entry size; add acceptance bullets (reviewer tag schema, deterministic aggregation precedence, migration from `check-verdict` fences, adversarial single-fence fixture).

**SF3. Codex M3 — BACKLOG note: deterministic verdict needs new reviewer-output schema.** Don't imply current `check-verdict.schema.json` is reusable as the trust boundary in the follow-up.

**SF4. Codex M4 — NFKC normalize order vs fence detection underspecified.** 2.4 mentions NFKC + zero-width strip; D33 says exact case-sensitive lang-tag match. Order matters: normalize-before-detection can turn disguised fences into real ones; normalize-after can miss them. Specify order in 1.5/2.1b/3.2: **normalize/strip BEFORE scanning, then exact-match `check-verdict`**. Add test where homoglyph/zero-width fence becomes a second fence after normalization (folds into SF-T5 fuzz table).

### Claude reviewer SFs

**SF5. Risk SF-RISK2** — `test_policy_json_no_shell_out`: add `__import__` to Call-node enumeration. One-liner.

**SF6. Risk SF-RISK3** — Synthesis prompt (2.4): instruct authoring-side hardening — quote literal `check-verdict` fence content as nested 4-backtick wrappers, not 3-backtick fences.

**SF7. Testability SF-T5 — `test_extract_fence_fuzz` (NOW highest-leverage).** With nonce dropped, D33 is sole structural defense for multi-fence injection. Parser bug = single-point-of-failure. Add 5.2 case with 8-row fixture: unclosed fence, CRLF, BOM, trailing whitespace after lang-tag, adjacent fences, mixed-case tag, empty fence, fence-inside-fence.

**SF8. Testability SF-T6 — `test_real_artifact_schema_match`.** 3 schemas × silent drift. Read `tests/fixtures/autorun-policy/golden/{morning-report,check-verdict,run-state}.json`, validate via `_policy_json.py validate`.

**SF9. Testability SF-T8 — `test_renderer_permutations` exact-string source pinning.** v5 keeps the test but doesn't say expected strings are fixture-sourced. Hardcoded → silent renderer/spec drift.

**SF10. Completeness SF-O1** — 1.0 acceptance: add `grep -q 'autorun-verdict-deterministic' BACKLOG.md`.

**SF11. Completeness SF-O5** — 3.1 `--dry-run` flag should produce stub `check-verdict.json` fence in synthesis path (else 5.5 false confidence per dryrun-full-graph memory).

**SF12. Scope SF-CUT4 + SF-CUT2/SF-CUT1 carry-forward** — `test_d39_banner_non_tty` is gold-plating; D38 8-perm reduce to 2 representative rows; fixture (e) duplicative.

### Codex Lows
- L1: Plan header "Spec... (v4: 26 ACs...)" → change to v5.
- L2: "D33 v4" labels noisy after deletion sweep; rename to D33 (or "D33 unchanged").
- L3: Delete or remove `5.3 (folded into 5.2)` row outside the task table.
- L4: R11 likelihood Med (cheap multi-fence attempts) or explain why D33 makes residual likelihood Low post-implementation.

## Verdict reasoning

Iteration-3 (v3) was NO-GO because the v4 nonce mechanism wasn't actually a trust boundary. Iteration-4 (v5) drops that mechanism cleanly, documents the residual honestly, carves the architectural fix into a follow-up spec — and Codex's response is to validate the move and find only documentation/framing gaps.

This is the kind of /check verdict that says *"the plan is right; the language and visibility need to catch up before /build."* Both must-fixes are documentation edits with no architectural risk.

**Recommended:** apply MF1 + MF2 + Codex mediums + Codex lows as plan v6 + spec amendment (~30-45 min), then ship to /build. SFs are build-time follow-ups.

## Codex Adversarial View — Trend

| Iteration | Codex highs | Class |
|---|---|---|
| 1 | 6 | Architectural (slug semantics, sidecar emission, stage env) |
| 2 | 6 | Contract pinning (preship/audit, circular dep, stdlib import, missing CLI, D33 self-inconsistency, single-fence bypass) |
| 3 | 5 | **Architectural for nonce design (H1, H2, H4, H5); contract leak (H3)** |
| **4** | **2** | **Documentation/framing (R18 visibility, R18 mitigation honesty)** |

The trend has reversed. Iteration-4's 2 highs are an order of magnitude lower-stakes than iterations 1-3.

## Next Step

```
fix now      → I apply MF1 + MF2 + selected SFs as plan v6 + spec amendment, re-present
defer to build → ship as-is; MF1/MF2 land in /build's first commits as documentation work
hold         → review on your end
```

**My lean: `fix now` for MF1/MF2 + Codex L1-L4 (cosmetic cleanup) + SF1 (3.2 wording rename) + SF2 (BACKLOG XL resize) + SF11 (dry-run stub fence emission). The other SFs are legitimate /build-time follow-ups.** Total ~30 min. The two MFs are documentation/framing — leaving them for /build means /build agents have to invent the language under time pressure, and the wrong language ships.
