# Persona Metrics Plan Checkpoint

**Reviewed:** 2026-04-26
**Plan version:** initial draft (23 tasks across 4 waves)
**Reviewers:** 5 Claude plan reviewers (completeness, sequencing, risk, scope, testability) + Codex adversarial check

---

## Overall Verdict: GO WITH FIXES

All 5 Claude reviewers landed PASS WITH NOTES — no FAIL. Codex returned a substantive adversarial pushback ("Adjust before `/check`") with 12 concerns, of which one (raw-output persistence) is a genuinely better approach worth adopting structurally before `/build`. The plan is architecturally sound, but R1 mitigation needs to shift from "test in T6/T14, pivot if blocked" to a Wave 0 file-persistence spike, and several test gaps need pinned fixtures. Net: the plan is buildable after a small set of targeted fixes; no full re-plan needed.

---

## Reviewer Verdicts

| Dimension | Verdict | Key Finding |
|---|---|---|
| Completeness | PASS WITH NOTES | All 16 ACs + 12 BYBs covered; synthesizer prerequisite survey should be a discrete pre-T6 task, not folded into T6 |
| Sequencing | PASS WITH NOTES | 4-wave structure sound; T18 needs explicit dep on T6/T7; Phase 2c → Phase 2b ordering needs explicit pin; consider Wave 0 spike for R1 |
| Risk | PASS WITH NOTES | R1 promotion to Wave 0 spike strongly recommended; R5 likelihood mis-rated (Medium → High); 4 missing risks (install idempotency, schema-prompt drift, context overflow, Codex temp-file ordering) |
| Scope Discipline | PASS WITH NOTES | Plan is ~30-40% non-MVP weight; 12-task floor exists. Cut candidates: T8, T9 (trim), T20 (defer). T1-T4 keep is contested — Risk wants them for drift detection |
| Testability | PASS WITH NOTES | AC #2 / #9 / #10 need fixture-based tests, not LLM re-runs; T21 must run on 2-3 features for rolling-window math; legacy-spec regression check missing |
| Codex (adversarial) | concerns | "Adjust before /check" — proposes file-backed scripts (rejected as architecture change); raw-output persistence is the high-value structural idea worth adopting |

---

## Must Fix Before Building (12 items)

### 1. Persist raw persona outputs to disk (Codex #3 — structural)

The plan's Phase 2c reads raw persona outputs from conversation context. Sub-agent return values, harness truncation, or context compaction can drop them. Codex's better approach: during `/spec-review` and `/check` Phase 1 (reviewer dispatch), persist each persona's raw output to disk:

```
docs/specs/<feature>/<stage>/raw/
  requirements.md
  gaps.md
  ambiguity.md
  feasibility.md
  scope.md
  stakeholders.md
  codex-adversary.md     # if Codex ran (replaces /tmp/codex-<stage>-review.txt)
```

Phase 2c then reads from this directory deterministically. Retires R1 entirely (no harness assumption), folds Codex temp-file relocation in (replaces `/tmp/codex-<stage>-review.txt`), and gives debugging a stable on-disk artifact. **Add as a Wave 0 spike** to validate the dispatch model can hand back raw outputs to disk via the prompt; if blocked, fall back to a re-attribution pass — but unlike the current plan, that fallback now has a clean file-backed input.

### 2. Move Codex output from `/tmp` to feature-local path (Codex #4, Sequencing M3)

Already implied by #1. Codex output writes to `<feature>/<stage>/raw/codex-adversary.md`. Phase 2c reads from there. `/tmp` fallback removed entirely (clean break, simpler model). Phase 2c → Phase 2b ordering becomes explicit: Phase 2c blocks on `<stage>/raw/codex-adversary.md` existing iff Codex was configured.

### 3. Demote `finding_id` determinism guarantee honestly (Codex #7, Risk #5)

The plan claims `finding_id` is "deterministic given identical clustering output." Codex correctly notes hashing a normalized string doesn't make clustering deterministic — same findings may group/split differently across runs. Fix:

- Reframe AC #2: *"`finding_id` is best-effort stable across re-syntheses; the canonicalization rule (NFC → lowercase → collapse \s+ → strip → sort → join \n → sha256 hex) is deterministic and testable in isolation against fixture inputs."*
- Pair this with **fixture-based test** (see Must Fix #4): test the canonicalization function against a hand-crafted input set, asserting hex-stable output. Don't try to test clustering stability via real LLM re-runs.
- Acceptance test for clustering instability: if T21 measures >20% `finding_id` drift on identical raw inputs, halt and switch to Codex's alternative — derive `finding_id` from individual persona finding records *before* clustering (`finding_id` per persona-mention; `cluster_id` separately groups them).

### 4. Fixture-based determinism + evidence-validator tests (Testability #1, #2)

Two AC verifications need test fixtures, not real LLM runs:

- **AC #2 canonicalization fixture:** stash `tests/fixtures/normalized_signature_input.txt` (a known sorted-substring set) and `tests/fixtures/normalized_signature_expected.hex` (the precomputed sha256). T6 includes a doctor.sh-runnable check: feed the input through canonicalization, assert hex matches.
- **AC #10 evidence-validator fixture:** stash `tests/fixtures/hallucinated_evidence_findings.jsonl` + a `tests/fixtures/revised.spec.md` where the evidence string is deliberately not a substring. T7 prompt is invocable in isolation against this fixture. Assert the row demotes to `not_addressed` + `confidence: low`.

Add a new task **T0.5: Build test fixtures** (S, parallel with Wave 0 spike). T20 doctor.sh extends to run these fixture checks.

### 5. Atomic-write test procedure pinned (Testability #3)

"Kill the synthesis process mid-write" inside an LLM prompt is not testable. Reframe AC #9 verification:

- **Static check:** the prompts (T6, T7, T5) literally contain `os.replace` directive language — verifiable by grep.
- **Behavioral check:** create a stale `<name>.tmp` in a test feature dir, run a no-op write through the prompt, assert prior canonical file unchanged. T20 doctor.sh runs this on a sandbox feature.

### 6. Snapshot refusal vs metrics gitignore separation (Codex #5)

Plan says "snapshot refuses if source artifact not git-tracked" and separately offers `PERSONA_METRICS_GITIGNORE=1` for metrics privacy. The wording invites confusion — these are unrelated checks (one about source, one about emit). Fix in T5 (snapshot prompt): explicit comment block distinguishing *"source-artifact tracking required for reproducibility"* from *"metrics-artifact tracking is per-adopter privacy choice."*

### 7. Wave 0 spike before T6/T7 (Sequencing S1, Risk Must #1, Completeness #3)

Insert two pre-Wave-1 tasks:

- **T-1 (synthesizer survey):** read `commands/spec-review.md` and `commands/check.md`, confirm Phase 2 (Judge+Synthesize) produces accessible raw persona outputs. Already done in this `/plan` invocation — confirmed Phase 2 is explicit prose. Document the finding in plan.md.
- **T0 (raw-output persistence spike):** in a real `/spec-review` run, dispatch one throwaway sub-agent and verify its raw output can be written to `<feature>/spec-review/raw/<persona>.md` from the host turn. ~30 min. If blocked, escalate before T6 starts.

### 8. install.sh idempotency on non-MonsterFlow files (Risk #2)

T19 must detect pre-existing regular files (not symlinks) at `~/.claude/commands/_prompts/<name>.md` and back up to `.bak` before symlinking. Existing helper handles this for top-level commands; extend for the new subdir.

### 9. Phase 0 in `/plan` runs *after* revision, not before (Codex #6)

Plan says `/plan` Phase 0 runs at start. But the spec implies revision happens between `/spec-review` and `/plan`. If the user runs `/plan` *before* revising, classifier judges against unrevised spec, tagging everything `not_addressed` (the source already addresses it under pre/post comparison). Fix in T16 prompt: Phase 0 documents *"runs against the current `spec.md` on disk; assumes user revised after `/spec-review`. If `spec.md` mtime predates `<feature>/spec-review/findings.jsonl` mtime, emit a warning suggesting the user revise first."*

### 10. T21 smoke test expanded to 3 features (Testability #4)

Single-feature smoke can't exercise rolling-window math, deadband, "insufficient data <3 runs," or "prior 10 vs current 10" framing. Either:
- Run T21 on 3 real features (slow, ~3x effort), OR
- **Recommended:** seed `tests/fixtures/synthetic-features/<a,b,c>/<stage>/{findings,participation,survival}.jsonl` with hand-crafted artifacts and run `/wrap-insights` against the seeded set. Verifies render math without 3 real pipeline runs.

### 11. Legacy-spec regression check (Testability #5)

Add to T21: run `/plan` on an existing legacy spec (`pipeline-wiki-integration` or `spec-upgrade`) which has no `findings.jsonl`. Assert: `/plan` completes without error, no `survival.jsonl` written, no user-facing failure. Cheap, catches a class of "instrumentation breaks the pipeline" bugs.

### 12. R5 (adopter privacy) likelihood bumped to High; runtime warning state model pinned (Risk #4, Codex #9)

- R5 current rating: Medium / High. Reality: most users don't read installer messages. Bump to **High / High**.
- "Once-per-feature" warning state model (Codex #9): use a **feature-level marker file** at `<feature>/.persona-metrics-warned` (zero-byte sentinel). Simpler than scanning `run.json.warnings[]` across stages. Documented in T14, T15.
- Stronger mitigation worth considering for adopter installs: *opt-in to commit*, not opt-in to gitignore. `MonsterFlow`'s own repo overrides via the `MonsterFlow` repo name detection in install.sh. **Defer this default-flip decision to Open Question for Justin.**

---

## Should Fix (8 items, non-blocking)

13. **T18 (wrap.md) deps include T6/T7**, not just T1-T4 schemas (Sequencing M2). Schemas alone don't define semantics; the prompt files do.
14. **Cut T8 wrap-insights-personas subcommand** for v1 (Scope #2). Bare-arg `/wrap-insights personas` works without a separate file. Re-add when discoverability becomes a real complaint.
15. **Trim T9 to README + CLAUDE.md template note** (Scope #3). Full adopter doc premature with one adopter. Note covers `PERSONA_METRICS_GITIGNORE=1` + privacy posture.
16. **Add doctor.sh check for prompt-version drift** (Risk #3). Grep `prompt_version: "<name>@<ver>"` in prompt-file headers and schema examples; fail if mismatched. Cheap, catches the common case.
17. **Add risk row + T7 behavior for LLM context-window overflow** (Risk #6). T7 prompt: on overflow, emit `classifier_error` rows for all findings with `evidence: "context_overflow"`, never silently truncate.
18. **Commit each Wave 2 command-file mod individually** (Risk obs). T14, T15, T16, T17 each get their own commit so a partial Wave 2 leaves a self-consistent repo.
19. **Pin T6/T7 estimation as XL, not L** (Risk #8). They carry NFC normalization across two callsites, fencing, slug regex, atomic-write semantics, schema references, prompt-version bump rule, batched-call discipline. Wave 1 "half day parallelized" is wishful — budget 1 full day.
20. **Pin schemas/ location at repo root** (Completeness obs). Not symlinked. Document in T1-T4 done-criteria.

---

## Observations (non-blocking)

- **`participation.jsonl` failed-vs-silent semantics** (Codex #8): a persona that *failed* (LLM error, timeout) is currently indistinguishable from one that *ran-but-found-nothing*. Worth a `status` field in `participation.jsonl` rows: `{"persona": "...", "model": "...", "findings_emitted": N, "status": "ok"|"failed"|"timeout"}`. Defer if not adopted now.
- **Recovery story if T21 fails after Waves 1-3 complete** is unspecified. Worst case: remove new symlinks + revert command-file edits. Committed JSONL artifacts are harmless leftovers. Worth one sentence in plan.
- **Codex's "ship Python scripts" recommendation rejected as architecture change.** `MonsterFlow` is markdown-choreography by design; introducing Python helpers is a project-shape change, not an implementation detail. The prompt-prose enforcement is sufficient for solo-dev use; if drift surfaces in real use, scripts can be added in a follow-up `persona-metrics-helpers` spec.
- **R7 (Windows atomic-write) over-mitigated** (Risk obs). Solo dev macOS; "Low (now fixed)" is right. No further action.
- **T22 hand-verification arithmetic** is loose — pin one persona's `load_bearing_rate` must round-trip within 0.01 of rendered.
- **Open Questions 1-6 in plan.md are unanswered.** Answer #1, #3, #4 (and the new R5 default-flip question) before `/build` starts.

---

## Codex Adversarial View (high-signal items beyond Claude reviewers)

Codex returned 12 concerns. Most overlap with Claude reviewers; the structurally novel one is **#3 (raw-output persistence to files)** — promoted to Must Fix #1 above. Other Codex-only items:

- **#7 (finding_id over-promised):** promoted to Must Fix #3.
- **#9 (warning state model):** promoted to Must Fix #12.
- **#6 (Phase 0 ordering vs revision):** promoted to Must Fix #9.
- **#5 (snapshot refusal vs gitignore):** promoted to Must Fix #6.
- **#8 (participation failed-vs-silent):** promoted to Observation (defer).
- **Codex's full Python-script restructure:** rejected as architecture change.

---

## Decision Path

**(fix now)** — adopt all 12 Must Fix items. Restructured plan adds:
- Wave 0 spike (T-1 + T0): 30-60 min
- Wave 1 fixture tasks (T0.5): 1 hr
- T6, T7 re-estimated to XL each
- Cut T8, trim T9
- New raw-output persistence spec'd into T5/T6/T7/T14/T15

**(defer to build)** — fix critical sequencing items (Must Fix #1, #2, #7) before Wave 1 starts; defer fixture work (Must Fix #4, #5) to be done as part of T21 prep; defer Should Fix items to be applied during the relevant task. Lower friction, slightly higher rework risk.

**(hold)** — stop, regroup, re-plan.

---

## Open Questions for Justin

1. **Adopt raw-output persistence (Codex #3 / Must Fix #1)?** Recommend yes — it's a structural improvement that retires R1. Cost: one new directory, ~5 lines added to T6/T14/T15 prompts.
2. **Default-flip `PERSONA_METRICS_GITIGNORE=1` to opt-in-to-commit for adopter installs (Risk #4)?** Recommend yes for adopter safety; `MonsterFlow`'s own repo overrides via name detection. Conservative answer is "no, keep current default."
3. **Cut T8 (wrap-insights-personas subcommand) and trim T9 (adopter doc)?** Recommend yes for both — bare-arg form works, full doc premature.
4. **Codex output goes to `<feature>/<stage>/raw/codex-adversary.md` only, or also keep `/tmp` fallback?** Recommend feature-local only (clean break, simpler).
5. **Recovery story for T21 failure post-Wave-3?** Document one-sentence rollback (remove new symlinks + revert command edits + leave committed JSONL as harmless).

---

## Recommendation

**fix now** — apply all 12 Must Fix items to plan.md, then proceed to `/build`. The Should Fix items can be folded in alongside (most are minor edits to existing tasks). The Wave 0 spike is the highest-value addition — 30-60 minutes of validation that prevents a much larger Wave 2 rework.

**Approve fix-now path? (fix now / defer to build / hold)**

---

## Post-checkpoint addendum (2026-04-26 — scope (b) adopted)

After this checkpoint passed and the 12 Must Fix items were folded into plan.md v1.1, a follow-up diagram-review session surfaced an asymmetry: `/plan`'s Judge runs (it's a multi-agent gate) but the original spec emitted metrics only at `/spec-review` and `/check`. The user adopted **scope (b)** — `/plan` becomes a metrics emit site, `/check` gains a survival-classifier Phase 0 (in *synthesis-inclusion* mode, since `plan.md` is freshly synthesized rather than revised).

**Files updated for scope (b):**
- `spec.md` — Summary, In Scope (3 of 4 emit/classify bullets revised), Data & State directory tree (+ `<feature>/plan/`), Files modified (T15/T16 expanded), `survival-classifier.md` description (two-mode), Acceptance Criteria (renumbered, +2 ACs for /plan emit and /check Phase 0).
- `plan.md` — header (v1.2 note), T7 prompt description (two-mode), T15 (check: 2 responsibilities), T16 (plan: 2 responsibilities), T21 smoke test expanded to verify all three gates.
- `diagrams.md` and `diagrams-preview.html` — JS2 records edge to PM added; recipe block updated.

**Why approved:** the symmetry of "every multi-agent gate emits metrics" is more honest than the original asymmetry. Cost is contained — no new prompt files, the existing `survival-classifier.md` gains a second outcome-semantics mode (synthesis-inclusion vs addressed-by-revision), and `/check` and `/plan` each gain one new responsibility alongside their existing role. No Wave structure change; T15 and T16 absorb the new work in Wave 2.

This addendum supersedes the original scope (a) decision documented earlier in this file.
