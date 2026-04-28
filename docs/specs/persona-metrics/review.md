# Persona Metrics Spec Review

**Reviewed:** 2026-04-26
**Spec version:** initial draft (confidence 0.91 self-reported)
**Reviewers:** 6 Claude PRD personas (requirements, gaps, ambiguity, feasibility, scope, stakeholders) + Codex adversarial check
**Overall health:** Concerns — coherent design with several fixable determinism / classifier-design gaps that must be pinned before `/plan`.

---

## Before You Build (12 items — must answer before `/plan`)

### 1. Classifier needs both pre-revision AND post-revision artifacts (Codex, new)

The current design feeds the classifier only the *revised* `spec.md` / `plan.md` and asks "was this finding addressed?" It has no way to distinguish *"the review caused this change"* from *"the text was already there before review."* Every finding whose concern was already addressed in v1 of the spec gets falsely tagged `addressed`, inflating every persona's `survival_rate` and corrupting `load_bearing_rate`.

**Fix:** at `/spec-review` (and `/check`) start, snapshot the artifact under review to `docs/specs/<feature>/spec-review/source.spec.md` (and equivalent for check). Survival classifier prompt receives `findings.jsonl` + the snapshot + the current revised artifact. Outcome `addressed` requires the revision to have *changed* in a way that addresses the finding, not just to *contain* an addressing passage. Update the prompt's outcome definitions accordingly.

### 2. Rotate before write, not before classify (Codex)

Spec says rotation of older `findings.jsonl → findings-<ISO-ts>.jsonl` happens at `/plan` pre-flight. But on the second `/spec-review` of the same feature, the new write *overwrites* the prior `findings.jsonl` immediately — the old round is gone before `/plan` ever runs. Rotation must happen at the *write* site (start of `/spec-review` synthesis emit), not at the read site.

**Fix:** at `/spec-review` start, if `findings.jsonl` exists in the target directory, rename it to `findings-<ISO-ts>.jsonl` *before* writing the new one. `/plan` pre-flight just reads the latest `findings.jsonl`.

### 3. `finding_id` determinism is structurally broken (4 reviewers convergent)

`finding_id = sha256(stage + sorted(personas) + title)`, but `title` is LLM-generated and varies across re-runs ("Auth flow doesn't specify token revocation timing" vs "Token revocation timing unspecified in auth flow") → different ids → `survival.jsonl` joins miss silently. `unique_to_persona` is also derived from clustering quality, not a stable property.

**Fix:** either (a) hash on a normalized cluster signature instead of `title` — e.g., sha256 of sorted list of source-persona-output substrings that fed the cluster, or (b) require synthesizer to produce title via a constrained template (e.g., "<noun>: <≤10 word concern>") at temperature=0, AND canonicalize before hashing (lowercase, trim, collapse internal whitespace). Bump hash truncation from 6 → 10 chars to reduce collision risk over time (Codex). Also weaken AC #1 to "deterministic given identical clustering output."

### 4. Persona attribution mechanics unspecified (2 reviewers convergent + Codex)

The existing `/spec-review` synthesizer produces `review.md` only. The spec assumes per-persona provenance is preserved through clustering, but doesn't say *how*. `personas[]`, `unique_to_persona`, `uniqueness_rate`, and `load_bearing_rate` all break if attribution is wrong.

**Fix:** state explicitly that synthesis must read the 6 raw persona outputs and emit `personas[]` for each cluster. Add a survey step in `/plan`: confirm `commands/spec-review.md` and `commands/check.md` have a discrete synthesizer step that can be extended; if synthesis is implicit/inlined today, factoring it out is prerequisite work.

### 5. Codex integration in `findings.jsonl` is unspecified (1 reviewer)

The drift example in the spec literally cites `"codex-adversary flagged same items"`, but Codex is never named in `personas[]` rules and `model_per_persona{}` examples only show `"claude-opus-4-7"`. Codex is already wired into `/spec-review`, `/check`, and `/build` per recent commits.

**Fix:** state that Codex findings flow through the same synthesizer → same `findings.jsonl`, with `personas[]` containing `"codex-adversary"` (or whatever the persona key is) and `model_per_persona["codex-adversary"] = "codex"`. If Codex output is appended outside the main synthesis (e.g., separate "Codex Adversarial View" section per existing `/spec-review` Phase 2b), spec must say whether/how those findings get clustered with Claude's.

### 6. Cross-platform timestamp filename format (2 reviewers convergent)

Spec example shows `findings-2026-04-26T10-15Z.jsonl` (colon-free) but doesn't *mandate* the format. `datetime.isoformat()` defaults to `2026-04-26T10:15:00+00:00` — `:` is illegal on Windows/exFAT and breaks git on Windows checkouts.

**Fix:** mandate `%Y-%m-%dT%H-%M-%SZ` UTC, explicitly forbid `:` in any rotation filename. Also pin behavior on collision (same-minute re-run): append `-<run_id>` or microseconds.

### 7. Rolling window ordering rule (2 reviewers convergent + Codex)

"Last 10 features" — by directory mtime? Git commit order? Spec date in frontmatter? `survival.jsonl` write time? Different orderings produce different windows.

**Fix:** pin to "10 most recent features by `survival.jsonl` mtime in the `spec-review/` subdir, ascending; stages without `survival.jsonl` excluded." Also clarify: "feature" = a `docs/specs/<slug>/` directory; `runs` = count of stages where the persona contributed (so one feature contributes up to 2 — spec-review and check).

### 8. Atomic write semantics (3 reviewers convergent)

Spec says nothing about how writes happen. A crash mid-emit leaves a partial JSONL file that all future `/wrap-insights` runs trip over.

**Fix:** all `findings.jsonl` and `survival.jsonl` writes use write-to-tmp + atomic rename (`<name>.jsonl.tmp` → `<name>.jsonl`). Document in both prompt files. Add to Edge Cases.

### 9. Public-repo data semantics for adopters (2 reviewers convergent)

`findings.jsonl` `body` fields contain verbatim review prose — substantive design info. Fine for `claude-workflow`'s own (public) repo, but adopter projects may have private/sensitive content. Memory entry `feedback_public_repo_data_audit.md` is exactly this hazard.

**Fix:** add a section: "Adopters who don't want measurement data committed can set `PERSONA_METRICS_GITIGNORE=1` (or add `docs/specs/*/spec-review/findings.jsonl` etc. to their repo's `.gitignore`). Default: committed (matches `claude-workflow`'s own use)." Document in CLAUDE.md template too.

### 10. Drift arrow deadband (1 reviewer)

"↑/↓/→ on rates" — is any non-zero delta an arrow, or is there a minimum? The example shows large jumps (4%→18%, 22%→9%) and "no change: 14 personas" implies a threshold but no number is given.

**Fix:** pin: arrows render only when `|delta| ≥ 5` percentage points; below that → renders. State in `wrap-insights.md`.

### 11. `/plan` and `/build` re-run idempotency + stale survival (Codex)

If user runs `/plan` twice, does the classifier re-run and overwrite `survival.jsonl`? If user edits `spec.md` *after* `/plan` runs the classifier, `survival.jsonl` becomes stale silently.

**Fix:** record `artifact_hash: sha256(revised_artifact)` in each `survival.jsonl` row. On `/plan` re-run, if `artifact_hash` matches the current `spec.md`, skip; if differs, re-classify and overwrite. `/wrap-insights` warns when a feature's `spec.md` hash doesn't match the hash recorded in its `survival.jsonl`.

### 12. Sentinel error row breaks schema (4 reviewers + Codex convergent)

Edge case "network unavailable" emits `{"error": "...", "timestamp": "..."}` — violates the documented per-row schema. Every reader has to special-case it.

**Fix:** either (a) keep schema integrity by emitting one row per finding with `outcome: "classifier_error"`, `evidence: "<error reason>"`, `confidence: "low"`, or (b) move error metadata to a sidecar `survival.error.json`. Pick one; don't mix shapes inside `survival.jsonl`.

---

## Important But Non-Blocking (10 items)

13. **Existing synthesizer is a prerequisite, not surveyed** (2 reviewers + Codex). `/plan` should start with a "survey current synthesizer" step before planning the emit integration.
14. **Batched classifier call** (2 reviewers). Specify: one LLM call per stage transition, all findings + revised artifact in one prompt — not per-finding.
15. **Run manifest** (Codex). Add a `run.json` per stage capturing run_id, timestamp, command, prompt_version, model versions, artifact_hash, output paths, status. Closes several gaps (debuggability, schema versioning, audit) at once.
16. **Schema versioning** (1 reviewer + Codex). Add `schema_version: 1` to both JSONL row schemas; bump on any breaking change. Also `prompt_version` so old rows are interpretable.
17. **Retention / pruning of superseded files** (2 reviewers). Pin a policy now even if it's "no auto-prune; user decides." Otherwise grows unbounded.
18. **Migration / missing prior-stage `findings.jsonl`** (1 reviewer). Pin: classifier silently skips if prior `findings.jsonl` is absent (legacy spec or skipped stage). `/wrap-insights` notes it.
19. **Evidence quote substring validator** (1 reviewer). Post-classifier check: each `evidence` (when not "no change") must appear as a substring in revised artifact. If not, demote to `not_addressed` + warn — kills hallucinated quotes.
20. **`rejected_intentionally` section-header rules** (1 reviewer). Pin: case-insensitive match against `## Open Questions`, `## Out of Scope`, `## Backlog Routing`, `## Deferred`.
21. **Persona zero-findings invisibility** (Codex). A persona that runs but raises nothing has no row in `findings.jsonl`. Survivorship bias: rates only count vocal personas. Fix: emit `participation.jsonl` per stage listing every persona that *ran*, regardless of finding count.
22. **Branch / merge behavior** (Codex). Committed metrics across branches will conflict. Document: don't commit `findings.jsonl` / `survival.jsonl` until the feature merges to main; or keep them per-branch and accept divergence.

---

## Observations (non-blocking)

- **`load_bearing_rate` framing penalizes good correlated personas** (Codex). A strong correctness persona that overlaps with others looks weak by this metric. The metric is honest but should be presented as "uniqueness × survival" rather than as the sole indicator of value. Consider also surfacing `survival_rate` independently in the full table, so a persona with high survival but low uniqueness (a frequent-corroborator) is visible.
- **`survival == addressed` is a weak proxy for value** (Codex). A finding can be addressed because it was obvious or already planned. The `artifact_hash` fix (#11) plus the pre/post snapshot (#1) together strengthen this proxy materially.
- **`unique_to_persona` denormalization** (1 reviewer). Derivable from `personas[]`. Worth a one-line note that it's a denormalized convenience.
- **`evidence ≤120 chars`** (1 reviewer). Pin to "Unicode codepoints, not bytes."
- **`confidence` field unused in rollup math** (1 reviewer). Either use it (weighted survival) or document why it's logged but not aggregated.
- **Documentation prose reframe to "measurement loop"** (1 reviewer, scope). Could defer until `persona-tiering` lands so framing matches reality. Mermaid edges + CHANGELOG should ship now; prose reframe is optional.
- **`/wrap-insights personas` subcommand** (1 reviewer, scope). Structurally fine but could be deferred. The default drift render is the load-bearing surface.
- **What does the user *do* with drift signal between this spec and `persona-tiering`?** (1 reviewer, scope). Add one sentence: "manual roster review at `/wrap-insights` time, before tiering ships."
- **Drift render legend for new adopters** (1 reviewer). Add a one-line legend in the rendered output.
- **`/wrap-insights` performance** (2 reviewers). Pure read projection is fine at 10–20 features; at 200+ may want caching. Note in spec, ship without cache.
- **No new dependencies claim** (Codex). JSONL parsing, schema validation, sort-by-mtime, trend math — these are all LLM-driven or shell-driven in this design. Claim is true but worth confirming each piece in `/plan`.
- **Documentation update completeness** (multiple). README mermaid + docs/index.html mermaid + flow.md + CHANGELOG covers launch. No additional doc surface needed.

---

## Codex Adversarial View (findings net-new beyond Claude's 6)

Codex surfaced four findings the Claude reviewers did not:

1. **Pre/post artifact comparison** (#1 above) — material design correction; promoted to Before-You-Build.
2. **Rotate-before-write vs rotate-before-classify** (#2 above) — promoted to Before-You-Build.
3. **`load_bearing_rate` penalizes correlated personas** (Observation above) — kept as observation; it's a framing issue, not a defect.
4. **Persona zero-findings invisibility / survivorship bias** (#21 above) — promoted to Important.

Codex also reinforced 6 of Claude's findings (sentinel schema, rolling window ordering, `finding_id` determinism, schema versioning, branch workflows, performance), strengthening priority on those.

---

## Reviewer Verdicts

| Dimension | Verdict | Key Finding |
|---|---|---|
| Requirements | PASS WITH NOTES | `finding_id` determinism + evidence-quote enforcement gaps; spec is buildable but determinism guarantees are over-claimed. |
| Gaps | PASS WITH NOTES | Atomic writes, concurrent access, cross-platform filename format, missing-prior-stage migration are unaddressed. |
| Ambiguity | **FAIL** | `finding_id`, rolling window ordering, drift thresholds, and rotation collision rules will produce divergent implementations. |
| Feasibility | PASS WITH NOTES | `finding_id` determinism + persona attribution mechanics not pinned; existing synthesizer prerequisite not surveyed. |
| Scope | PASS WITH NOTES | MVP cut clean; `personas` subcommand and prose reframe are minor trim candidates; deferral to `persona-tiering` is genuine, not theater. |
| Stakeholders | PASS WITH NOTES | Codex integration unspecified; public-repo data semantics for adopters needs explicit guidance. |
| Codex (adversarial) | concerns | Four net-new findings, three of them critical-to-buildable. |

---

## Conflicts Resolved

- **Requirements (PASS) vs Ambiguity (FAIL) on overall health:** resolved by promoting Ambiguity's #1–4 to Before-You-Build because three of those were independently corroborated by Gaps, Feasibility, and Codex. The FAIL is well-founded.
- **3-state vs 5-state outcome taxonomy:** Codex proposed expanding to 5 states (`addressed_by_revision`, `already_addressed`, `not_addressed`, `intentionally_deferred`, `rejected_as_invalid`). User explicitly chose 3-state in spec Q3 to minimize classifier disagreement. Decision stands; the pre/post snapshot fix (#1) resolves Codex's `already_addressed` concern within the existing 3-state taxonomy by making "addressed" mean "addressed *by the revision*."

---

## Recommendation

**Refine the spec** to address the 12 Before-You-Build items, then proceed to `/plan`. Most fixes are 1–3 sentence pins; the biggest structural changes are:

- Pre/post artifact snapshot path (#1) — adds a snapshot step at `/spec-review` and `/check` start
- Rotate-before-write (#2) — moves rotation from `/plan` pre-flight to `/spec-review` write site
- `run.json` manifest (#15) — closes audit, schema versioning, debuggability gaps in one stroke
- `participation.jsonl` per stage (#21) — fixes survivorship bias

The Important and Observation items can be deferred to `/plan` discussions.
