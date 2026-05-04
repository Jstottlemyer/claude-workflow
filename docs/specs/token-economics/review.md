# Review: Token Economics — Round 3

**Date:** 2026-05-04
**Spec:** `docs/specs/token-economics/spec.md` revision 3 (instrumentation only, public-release-ready)
**Round:** 3 (after v3 inline-edit pass that addressed 7 round-2 blockers via Q&A walkthrough)
**Reviewers:** 6 PRD personas + Codex adversarial
**Round-1 artifact:** `spec-review/findings-2026-05-04T01-37-36Z.jsonl` (23 clusters)
**Round-2 artifact:** `spec-review/findings-2026-05-04T02-12-25Z.jsonl` (29 clusters)
**Round-3 artifact:** `spec-review/findings.jsonl` (this round)
**Overall health:** **Good with One Open Question** — 6/6 primary reviewers PASS or PASS WITH NOTES with **0 critical gaps**; Codex pushes back at the artifact-join level.

## Spec Strengths

- Round-3 is the cleanest yet on every primary-reviewer dimension. Five of six explicitly stated "round 3 has substantially fewer concerns than round 2." Requirements R3 returned a straight **PASS**.
- All 7 round-2 blockers verifiably closed in v3 — survival uses two schema-grounded denominators, jaccard removed, totals not averages, A1 exact equality + A1.5 cross-check, hybrid roster handling, A0/A3/A8 tightened with named test files, Project Discovery cascade locked.
- **Phase 0 spike Open Q2 closed by probe** during this round — Feasibility R3 verified worktree sessions get their own top-level `~/.claude/projects/<sanitized>/` entry; no symlink-following required.
- Public-release additions (A9, A10, A11, Privacy section, A0 fixture redaction script) are a real specification, not a disclaimer.
- Three rounds of review with the audit trail intact (`source.spec.md` snapshots, rotated `findings-*.jsonl`, all raw outputs persisted) is exactly what the persona-metrics infrastructure was built for.

## The Round-3 Pattern: 6 PASS vs Codex FAIL

**Same pattern as round 2.** The 6 primary reviewers verify the spec against itself (do round-2 fixes land, are claims testable, are stakeholders served). Codex verifies the spec against **the actual artifact ecosystem** — schemas, file layouts, run-identity contracts. Both reads are valid; they ask different questions.

Round-3's Codex findings are largely simplifications + a few real expansions. Most concerning is the **artifact-level cost/value join** problem: even though we report totals (not per-invocation averages), the question "which `findings.jsonl` rows correspond to which Agent dispatch" isn't fully pinned. We're matching by (project, feature, gate) at best, which means re-runs of the same gate get conflated.

## Must Resolve Before Planning

**Round-3 primary reviewers report 0 critical gaps.** The blockers below are entirely Codex round-3 (5 of them); the 6 primary reviewers' notes are folded into "Should Address."

### 1. Cost/value join is still under-specified at the artifact level *(Codex Blocker #1)*
- Spec windows over (persona, gate) invocations, but value side comes from `findings.jsonl` / `survival.jsonl` / `raw/<persona>.md` which don't carry a stable `agent_tool_use_id`. Re-runs of the same gate, retries, renamed specs, or overwritten stage directories conflate.
- **Two paths forward, both small:**
  - **(A) Best-effort aggregate** — explicitly state v1 aggregates by `(project, feature, gate)` directory, not by invocation. The 45-window then counts "the most recent 45 directories that have findings.jsonl across all projects" — coarser, but honest. Acceptance criteria adjust accordingly. Smallest change to spec; smallest change to mental model.
  - **(B) Add dispatch-id linkage at emit time** — extend `findings-emit` directive to record `parent_agent_tool_use_id` (or equivalent from spike's findings) into `run.json`. New field; minor schema bump. Joinable to cost-side. More work but invocation-level metrics are what the spec actually wants.
- *Recommended:* (A) for v1; (B) becomes a v1.1 add-on if the data shape proves valuable.

### 2. Content-hash reset isn't implementable from current-state alone *(Codex Blocker #2)*
- Spec says persona prompt edits reset `(persona, gate)` window via `persona_content_hash`. But historical `findings.jsonl` rows don't record which persona-content-hash was active at dispatch time — `compute-persona-value.py` only knows the *current* hash.
- A4's test ("after editing persona, run one fresh dispatch, see `runs_in_window: 1`") implies the system can drop pre-edit data after one fresh dispatch — but there's no boundary marker in existing artifacts.
- **Fix:** weaken e2 + A4. Replace with: "On hash change, the *current row* is marked with the new hash. Historical attribution is best-effort (cannot determine which old runs used old vs new content). Window starts accumulating fresh under the new hash; old data may persist transiently until the window rolls out." Document this honestly; don't claim deterministic boundary detection we can't do.
- Per-dispatch hash capture (the proper fix) is its own micro-spec — out of scope here.

### 3. Run states unspecified — `runs_in_window` denominator ambiguous *(Codex Blocker #3)*
- If an Agent dispatch exists but Judge failed / findings are malformed / survival is missing / `/wrap-insights` never ran for that gate → does that invocation count in `runs_in_window`?
- Spec implies yes for cost (we see the dispatch in session JSONL), but value denominators depend on artifacts that may not exist.
- Will bias survival upward (failed runs skipped) or unpredictably (cost-only runs count with zero emitted).
- **Fix:** add a `run_state` column to each row's metadata: one of `complete_value`, `missing_raw`, `missing_findings`, `missing_survival`, `malformed`, `cost_only`. Define which states count toward `runs_in_window`, token totals, and each rate denominator. Lock in spec.

### 4. Bullet counting is a weak survival denominator — rename the metric *(Codex Blocker #4)*
- Counting `- ` / `* ` bullets under headings assumes stable markdown output and treats Observations equal to Critical Gaps.
- More importantly, **Judge can merge multiple raw bullets into one finding or split one bullet into multiple findings.** So `judge_survival_rate = findings / bullets` is not a true survival rate — it's a compression ratio.
- **Fix:** rename `judge_survival_rate` → **`judge_retention_ratio`** (Codex's term). Don't oversell what the metric measures. Update docs everywhere. The downstream-survival metric is unaffected. The only change is honest naming.

### 5. Privacy tests are too shallow — allowlist > canary *(Codex Blocker #5)*
- A10 only canary-checks for "LEAKAGE_CANARY" string + a few field-name patterns (`prompt`, `body`, `text`, `content`). Misses leakage through file paths, user/project names in session IDs, descriptive timestamps, model metadata, persona names from private workflows, or arbitrary nested fields.
- `contributing_finding_ids[]` being "sha256-derived" doesn't guarantee privacy if hash input is guessable.
- **Fix:** rewrite A10 as **allowlist schema**. Define exactly which JSONL row fields and which fixture fields are permitted; tests reject every field not in the allowlist. This is one extra schema file (`schemas/persona-rankings.allowlist.json`) and a stricter test — pre-public-release table stakes.

## Should Address (non-blocking, address in `/plan`)

### From Codex round 3 (Major #6–#11):
- **Project Discovery is over-broad for a public tool** — auto-discovery via `~/Projects/*/docs/specs/` will scan private repos by default. Codex recommends: default to current-repo-only + `~/.config/monsterflow/projects`; make `~/Projects/*` scan opt-in via flag. **Stakeholders R3 (#2) flagged the same concern from a different angle** ("adopter-with-private-projects consent is buried"). Convergent — fix.
- **`run.json` location not defined** in this spec — `last_seen` sources from it but the spec doesn't pin the path. Fix: cite `docs/specs/<feature>/<stage>/run.json` (which the persona-metrics directive already creates).
- **Freshness race check is insufficient** — "compare last_seen, if older abort" can drop valid updates (different gates have different max timestamps). Fix: lock file or per-(project, gate) high-water mark, OR document last-writer-wins explicitly.
- **Totals without averages for cost ranking is awkward** — "lowest total cost" penalizes frequently-used personas. Fix: add `avg_tokens_per_invocation` as derived field, OR rank cost by avg in the dashboard text.
- **Downstream survival timing unspecified** — when is survival "final"? Different gates may have non-comparable survival semantics. Fix: add `survival_observed_at` + `pending_downstream` state; document that low downstream-survival may mean "not evaluated yet."
- **"Ready-for-plan" while Phase 0 Q1 unresolved** — A1.5 is designed to close it via test outcome, but Codex argues Phase 0 should fully close before claiming ready. *Defer to user judgment* — this is the path /plan was designed to handle.

### From primary reviewers (round 3):
- **Hybrid roster discovery in JS is structurally impossible under `file://`** — dashboard avoids `fetch()` per existing pattern. Fix: have `compute-persona-value.py` emit a sibling `persona-roster.js` (or extend `dashboard-bundle.sh`). (Feasibility R3 #1 — concrete and important.)
- **`survival.jsonl` schema has no `kept` enum value** — only `addressed`, `not_addressed`, `rejected_intentionally`, `classifier_error`. Spec's filter `outcome ∈ {addressed, kept}` reduces to `outcome == "addressed"`. Fix: drop `kept` from spec (one-line). (Feasibility R3 #2.)
- **`contributing_finding_ids[]` no length cap** — soft-cap (e.g., last 50 + `truncated_count`) for public release. (Feasibility R3 #3.)
- **A8 idempotency needs `sort_keys=True`** in `json.dumps` (verified by Feasibility). (Feasibility R3 #4.)
- **`~/.config/monsterflow/projects` should respect `$XDG_CONFIG_HOME`** when set. (Feasibility R3 #5.)
- **Three render surfaces is one too many** — drop `/wrap-insights ranking` bare-arg full-table; duplicates the dashboard tab. (Scope R3 #1.)
- **A0 redaction script borderline meta-spec** — bound it in one sentence as single-purpose, not a general redaction tool. (Scope R3 #2.)
- **A11 needs day-1 fresh-install degradation** — "≥10 historical gate runs" is unsatisfiable for fresh adopters; spec the empty-state. (Scope R3 #4 + Gaps R3 #1.)
- **A11 outcome criterion underspecified at boundary** — ground to `findings.jsonl` distinct pairs, not "runs." (Requirements R3 #1.)
- **A10 doesn't cover stderr/stdout** — `compute-persona-value.py` warning paths could echo finding titles. (Requirements R3 #2.)
- **A1.5 disagreement branch lacks forcing function** — on disagreement, A1.5 fails the build and `/plan` re-opens Open Q1. (Requirements R3 #3.)
- **A4 doesn't assert `contributing_finding_ids[]` cleared on persona-prompt change** — pre-edit findings could persist in drill-down. (Requirements R3 #4.)
- **Tier-1 config file lifecycle missing** — who creates it, what happens on missing-path entries, how adopters discover. (Gaps R3 #2.)
- **Multi-machine sync gap** — JSONL gitignored; per-machine windows diverge. State the semantics explicitly. (Gaps R3 #3.)
- **No `schema_version` field on rows** — additive evolution to v1.1 will be lossy against pinned idempotency allowlist. (Gaps R3 #5.)
- **No row-TTL / cleanup story** — JSONL grows unbounded over years. (Gaps R3 #6.)
- **No Project Discovery telemetry** — one-line stderr summary of discovered projects prevents adopter "where's my data" questions. (Gaps R3 #7.)
- **Persona-author exposure via rendered output (carryover)** — screenshots of dashboard tab and copy-pastes of `/wrap-insights` text leak persona names. Add warning banner or anonymization flag. (Stakeholders R3 #1.)
- **Pro-tier-friend commitment unenforceable** — Stakeholders R3 #3 suggests A12: `docs/specs/account-type-scaling/spec.md` exists within 14 days of v1 merge. Probably out of scope for this spec, but worth noting.
- **Persona contributors have no doc on data lifecycle** — risk: contributor sees 20% rate from 5 runs and self-rejects PR. (Stakeholders R3 #4.)
- **"All bullets" definition residual edge cases** — nested/continuation bullets, Verdict section. Top-level only; Verdict is not a finding. (Ambiguity R3 #1.)
- **Schema example lacks denominator annotations** — inline JSONC comments distinguishing `/total_emitted` vs `/total_judge_survived`. (Ambiguity R3 #2.)
- **`outcome` enum currency** — spec asserts a closed set without anchoring to `survival.jsonl` schema. (Ambiguity R3 #3.)
- **Null-rate sort position unspecified** — pick: nulls always sort to bottom. (Ambiguity R3 #4.)
- **Worktree-discovery dedup policy** — Open Q2 leaks into Project Discovery (phantom/duplicate projects). Pre-commit policy now. (Gaps R3 #4.)

## Watch List

- Codex round-3 #12: dashboard "(never run)" hybrid layer needs canonical roster source — current `personas/` files include disabled/experimental personas; will render as never-run noise.
- Codex round-3 #13: deleted-persona behavior conflicts with content-hash reset (`null` collapses all deleted versions).
- Codex round-3 #14: A9 covers JSONL gitignore but `tests/fixtures/persona-attribution/` is committed — needs strictest privacy gate. *(This is partially addressed by A10 + the redaction script, but Codex is right that A9 should explicitly cover the fixture path.)*
- Codex round-3 #15: Open Q3 lacks abort criterion — define minimum linkage success threshold (e.g., "fewer than 99% resolved → exit non-zero unless `--best-effort`").

## Agent Disagreements Resolved

- **Should `/wrap-insights ranking` bare-arg ship in v1?** Scope R3 says drop (duplicates dashboard). Spec ships it. **Resolution:** Scope wins — ASCII duplication of a graphical tab is YAGNI; cut from v1.
- **Is `compute-persona-value.py` reading from private projects acceptable?** Stakeholders R3 + Codex both flagged. Spec acknowledges in Privacy section but defaults to opt-out. **Resolution:** flip to opt-in for `~/Projects/*` scan; current-repo + explicit config remain default. Per-project opt-out also added to Out of Scope per Scope R3.
- **6 PASS vs Codex FAIL again — proceed or revise?** Round-2 same situation; user chose to revise via Q&A. Round-3 Codex blockers are smaller and most are simplifications (rename one field, weaken one acceptance, add one column, default-to-narrower discovery). **Resolution:** present as "Good with One Open Question" — the user calls.

## Codex Adversarial View

Codex round-3 full review at `spec-review/raw/codex-adversary.md`. Net-new findings beyond the 6-reviewer consensus (numbered to match Codex's own output):

- **#1 Cost/value join under-specified at artifact level** — see Blocker #1 above.
- **#2 Content-hash reset not implementable from current-state alone** — see Blocker #2 above.
- **#3 Run states unspecified** — see Blocker #3 above.
- **#4 Bullet-counting is compression ratio, not survival** — see Blocker #4 above. Concrete fix: rename to `judge_retention_ratio`.
- **#5 Privacy tests too shallow** — see Blocker #5 above. Concrete fix: allowlist schema.
- **#6 Phase 0 Q1 unresolved makes "ready-for-plan" risky.**
- **#7 Project discovery over-broad for public tool.**
- **#8 `run.json` location not defined** in this spec.
- **#9 Freshness race check insufficient.**
- **#10 Totals without averages awkward for cost ranking.**
- **#11 Downstream survival timing unspecified.**
- **#12–#15 (non-blocking)** — never-run roster source ambiguity, deleted-persona vs hash collision, A9 doesn't cover fixture path, Open Q3 missing abort criterion.

## Reviewer Verdicts

| Dimension | Verdict | R3 vs R2 | Key Finding |
|---|---|---|---|
| Requirements | **PASS** | substantially tighter; all 4 R2 testability gaps closed | Acceptance coverage genuinely complete; ready for `/plan` and public release |
| Gaps | PASS WITH NOTES (0 critical) | both R2 blockers cleanly closed | 7 polish items; pre-public-release-tightening class |
| Ambiguity | PASS WITH NOTES (0 critical) | dramatically smaller surface | 4 one-liners; bullet definition + schema-comment + enum anchor |
| Feasibility | PASS WITH NOTES (0 critical) | A1 ±5% retired; **Phase 0 Q2 closed by probe** | `survival.jsonl` has no `kept` enum (one-line fix); JS hybrid needs server-side roster emit |
| Scope | PASS WITH NOTES (0 critical) | "ship to /plan"; all 4 R2 items landed | 4 tunings; drop bare-arg full table; bound redaction script |
| Stakeholders | PASS WITH NOTES (0 critical) | R2 blockers vanished | Persona-author exposure via rendered output (carryover); private-project consent buried |
| Codex | **FAIL for public-release-ready** | 5 blockers + 6 majors | Cost/value artifact-join, content-hash historical limitations, rename `judge_survival_rate` → `judge_retention_ratio`, allowlist privacy tests |

## Consolidated Verdict

**6 of 6 primary reviewers PASS or PASS WITH NOTES with zero critical gaps; Codex FAIL for public-release-ready with 5 simplification-shaped blockers.**

Round-3 trajectory is overwhelmingly positive — the v3 inline-edit pass cleanly closed every round-2 blocker the primary reviewers raised. Codex's new round-3 blockers are mostly **honest naming** (`judge_retention_ratio`), **safer defaults** (opt-in project discovery), **boundary-case admission** (content-hash historical limitations), **state taxonomy** (`run_state` column), and **stricter privacy** (allowlist schema). None require a structural rewrite.

**Recommended path:** apply Codex's 5 blockers as inline edits (estimated ~30 minutes — they're targeted), then either approve directly or run round 4. The simplifications make the spec more honest, not more complex.

---

**Approve to proceed to `/plan`** with Codex's 5 blockers applied as inline edits **/ refine** (specific guidance) **/ approve as-is** (accept Codex's pushback as `/plan`-grade questions).
