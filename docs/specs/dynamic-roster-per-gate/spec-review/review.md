# Spec Review — dynamic-roster-per-gate

**Reviewed:** 2026-05-06
**Reviewers:** ambiguity feasibility gaps requirements scope stakeholders

---

## ambiguity

# Ambiguity Analysis — `dynamic-roster-per-gate`

## Critical Gaps

**G1. `fit_count` vs `fit_score` naming drift.** A1 defines `fit_count = len(spec.tags ∩ persona.fit_tags)`. The `selection.json` example uses field `fit_score`. The `combined` field is `fit_score × load_bearing_rate`. Two engineers will pick different field names. Pin one term in the schema and use it everywhere (spec body, AC text, JSON field, stdout format).

**G2. Test count contradicts itself.** Scope says "target: 50-70 fixtures" (line in `Test suite` bullet). A18 says "40-60 PASSes." Pick one number and reconcile.

**G3. Override precedence under SEC-01 is unspecified for CLI.** "CLI > spec > constitution" (A6) says CLI is the highest precedence layer. SEC-01 says spec-level `tier_pins` cannot downgrade a `fit_tags:[security]` persona below `security_floor`. **Does CLI `--tier-pin` obey the same floor?** If yes, document it in SEC-01 and A21. If no, CLI becomes the downgrade escape hatch the spec just deferred. Two engineers will implement this differently.

**G4. "Key-level merge, not block-level replacement" depth is undefined.** A6 + Edge Case 12 say merge is key-level. But `tier_policy` is a nested map. Concretely: if constitution has `tier_pins: {check: {scope-discipline: opus}}` and spec has `tier_pins: {plan: {risk: opus}}` — does the merged result include both, or does spec's `tier_pins` replace constitution's? Same question for `panel.opus_min` vs `panel.default_worker`. Specify the merge semantics at every nested level (recursive deep-merge vs one-level-deep merge vs leaf-replacement).

**G5. "Stale-tags warning" heuristic is undefined.** A11 + Edge Case 4 + the W5 wiring all reference "tag heuristic re-inference shows ≥1 enum delta." Is the heuristic the deterministic baseline regex (`_tag_baseline.py`), an LLM re-inference, or both? Determinism, cost, and false-positive rate diverge sharply across those three. The warning runs every gate dispatch — non-trivial.

**G6. `tier_pins` referencing unselected persona drops "other-persona" — which?** Edge Case 5 says "promoted `<persona>:opus` into panel; dropped `<other-persona>`." Drops the lowest combined-score selection? Drops the lowest-tier? Drops a Sonnet to keep Opus floor? Specify the swap-out rule deterministically.

**G7. Pre-processing pipeline omits YAML frontmatter strip.** SEC-02 lists 5 mandatory ordered steps: NFKC → lowercase → strip code fences → regex → emit. The selection.json schema description in §Data & State says regex excludes "code fences and YAML frontmatter." Frontmatter strip is missing from the ordered pipeline. Without it, `tags: [security, ...]` *in the frontmatter itself* would self-trigger the security baseline — circular detection. Specify whether frontmatter is stripped, and at what step.

## Important Considerations

**I1. "Existing specs grandfathered" needs a boundary.** §Scope: "existing specs grandfathered (treated as empty intersection → ranking-only fallback)." Created before what version? Detected how — by absence of `tags:` key, or by `created:` date < ship date? `/spec` Phase 3 will run on subsequent revisions of grandfathered specs — does that backfill, or stay grandfathered?

**I2. Cold-start threshold ambiguous.** "Fewer than 3 runs per persona." Is the cutoff applied per-persona (some personas have data, some don't) or globally (until *every* persona has 3, fall back uniformly)? The first interpretation gives partial differentiation; the second is all-or-nothing.

**I3. Edge Case numbering is chaotic.** Cases jump 1–14, then 20–23, then 15–19. Reviewers will skip 15–19 thinking they're earlier. Renumber sequentially before /plan consumes this.

**I4. "A12-style matrix" is an overloaded term.** A12 is the `/spec` Phase 3 acceptance criterion. The spec also uses "A12-style matrix" colloquially to mean the 12-axis test fixture pattern from prior work. Pick a different name (e.g., "12-axis matrix," "v0.9.0-style matrix") to avoid AC reference collision.

**I5. `persona_pins` vs `tier_pins` overlap.** `~/.config/monsterflow/config.json` example contains both `persona_pins` (legacy from `account-type-agent-scaling`) and `tier_pins` (new). What's the relationship — is `persona_pins` "include this persona" while `tier_pins` is "if included, set tier"? What if `tier_pins` references a persona NOT in `persona_pins`? (Edge Case 5 partially answers — "promote into panel" — but the relationship isn't documented in §Data & State.)

**I6. `--tier-pin` flag merge semantics unspecified.** Can `--tier-pin` be passed multiple times in one invocation? If yes, do they accumulate or last-wins? What if the same `<gate>:<persona>` is repeated with different tiers?

**I7. "Codex additive" — additive to what budget?** A7 says Codex is "not counted in `opus_count_actual` or panel size budget." But §Scope §Tier rule: "reviewer panel ≥1 Opus + remaining N-1 Sonnet" — does N include Codex or not? Edge Case 9 says "tier rule unaffected" but doesn't clarify counting. Confirm: Codex is dispatched in addition to the budget-N Claude personas, never displaces one.

**I8. `\b` word-boundary on `--` regex.** `BASELINE_KEYWORDS["api"]` includes `\b(--[a-z][a-z0-9-]+|...)\b`. `\b` is a transition between `\w` and `\W`; `-` is `\W`, so `\b--` requires a word char immediately before the first `-`, which is the opposite of typical CLI-flag context (whitespace before `--`). May silently never match. Verify with fixtures.

**I9. "session roster only" in frontmatter is undefined.** The spec's own frontmatter has `session_roster: defaults-only (no constitution)`. This isn't defined anywhere in this spec or referenced in the schema additions. If it's an `/spec` artifact unrelated to dynamic-roster, say so.

**I10. A20 is not an acceptance criterion.** "Pipeline cycle through itself … chicken-and-egg deferred." Either drop it from the AC list or carve to a real follow-up issue. Leaving "deferred" entries in ACs invites pipeline tooling to misclassify.

**I11. "(work-size option d)" is an undefined reference.** Edge Case 4 references "`/spec` revision flow (work-size option d)." Option d of what menu? Either link the menu or paraphrase the user action.

**I12. `selection.json` `dropped` ordering is unspecified.** Ordering by combined score? By alphabetical persona name? Reviewers comparing two runs need stable ordering for diffs.

## Observations

**O1.** "Hard constraint, not preference" (Tier rule) is good — but pair it with a single normative MUST in an AC. A2 has it; verify all gate dispatch code paths reference A2 directly.

**O2.** §Approach §Rationale uses "Anthropic's 90.2% finding" — the constraint section cites the URL. Good provenance; carry the citation into the rationale paragraph too so future readers don't have to scroll.

**O3.** "Multi-spec session" (Edge Case 10) clarifies cross-spec state but doesn't say what happens if two gates of the *same* spec see different `tags:` (e.g., user edits between `/plan` and `/check`). Probably out of scope, but worth a one-line "tags read at each gate dispatch independently; mid-pipeline edits take effect on next gate."

**O4.** §Scope mentions "LLM-propose-user-confirm flow" three times. Specify what "confirm" means concretely — does Enter accept the proposal, or does the user have to type the tag list? UX persona will have a stronger view here.

**O5.** Rationale comment example: `tags: [security, data, api]   # baseline: [security, data]; llm-added: [api]`. YAML inline comments after `]` are valid but some YAML loaders strip them silently. Confirm the resolver doesn't depend on parsing the comment (the `_tag_baseline.py` recompute makes it informational — good — but document this).

**O6.** `_tier_assign.py` `validate_tier_pins` returns `0/2/3` exit codes; the wrapper `case` in §Scope has fallthrough to `*) exit 4`. Worth a single normative table of "validator exit codes" so all 6 invocation sites stay synchronized.

**O7.** "Persona file missing `fit_tags`" (Edge Case 13) → "fit_tags: []" → "eligible only via cold-start fallback." But A17 mandates all 19 personas have `fit_tags`, and `tests/test-persona-frontmatter.sh` enforces it. Edge Case 13 is therefore unreachable in shipped state — keep it for forward-compat (new persona added without fit_tags) but say so.

**O8.** "`--explain` is mutation-zero" (A23) — strong AC. Tighten the test by also asserting no `~/.config/monsterflow/` writes, no `dashboard/data/` appends, no global git operations.

## Verdict

**FAIL** — G1 (fit_count/fit_score naming), G3 (CLI vs SEC-01 floor), G4 (merge depth), G5 (stale-tags heuristic), and G7 (frontmatter strip in SEC-02 pipeline) are load-bearing ambiguities that two engineers will resolve differently; resolve before `/plan` consumes this spec. G2 and G6 are quick fixes but blocking until done.

**Class tagging:** all Critical Gaps are `class: contract` (the fix is a code/schema clarification) except G3 which is `class: security` + `tags: ["sev:security"]` (security-floor enforcement is a trust-boundary question), `severity: major` across the board.

---

## feasibility

# Technical Feasibility Review: dynamic-roster-per-gate

## Critical Gaps

### CG-1: Agent tool `model` parameter is unverified for cross-tier dispatch
- **persona:** feasibility
- **finding_id:** CG-1
- **severity:** blocker
- **class:** architectural
- **title:** "Spec hard-pins on Agent(model: opus|sonnet) — never proven across all subagent_types"
- **body:** A14 + Edge Case 20 *forbid* wrapper-file fallback and require the built-in `model` parameter on the Agent tool. But the spec never demonstrates this parameter works for arbitrary `subagent_type` values in the version of Claude Code adopters run. If the harness silently ignores `model` (or only honors it for specific built-in agents), every "Opus floor" assertion (A2/A3/A4) becomes vacuous — panels would all run at the default tier and tests might still pass because `selection.json` records the *intended* tier, not the *actual* one. Same risk for `claude -p --model` against persona invocations that pass content via stdin/heredoc. Plan-stage MUST include a contract probe (`/spec-review --probe-tier-dispatch`) that runs a no-op Opus + Sonnet persona, captures the model echo from the response, and fails loudly if mismatched.
- **suggested_fix:** Add AC: "A24 — tier dispatch is observable. Each persona response includes a model-attestation line; resolver post-flight compares to intended tier and emits `tier_dispatch_verified: true|false` to selection.json. Mismatch halts /spec-review/plan/check with clear error."

### CG-2: `_tag_baseline.py` regex for `api` is dangerously over-broad
- **persona:** feasibility
- **finding_id:** CG-2
- **severity:** blocker
- **class:** contract
- **title:** "api regex `--[a-z][a-z0-9-]+` matches every CLI flag mentioned anywhere in any spec"
- **body:** Every spec in this repo mentions `--dry-run`, `--model`, `--auto`, etc. The current `api` regex will tag *every spec* with `api`, defeating discrimination. Compounded by the resolver-recompute rule (Edge Case 23): once `api` is detected, no human edit can suppress it without removing the prose mention. Result: panel will deterministically over-weight api-heavy personas on specs that aren't actually about CLI surface design. The `integration` (`hook|wrapper|symlink|install\.sh|gate|dispatch[-_ ]path`) and `migration` regexes have similar bleed — `gate` appears in nearly every pipeline spec.
- **suggested_fix:** Tighten the api regex to require a flag *definition* context, not a *mention* (e.g., require `argparse|add_argument|new flag|introduces` within N tokens). Provide negative-fixture coverage in A22: a spec that *mentions* `--auto` without introducing it must NOT get `api` tag. Apply same scrutiny to integration/migration regexes.

### CG-3: NFKC normalization is necessary-but-insufficient for homoglyph defense
- **persona:** feasibility
- **finding_id:** CG-3
- **severity:** major
- **class:** security
- **tags:** ["sev:security"]
- **title:** "NFKC normalizes Cyrillic homoglyphs but not zero-width joiners, RTL marks, or Greek confusables"
- **body:** Edge Case 22 names Cyrillic `а` (U+0430) as the threat model. NFKC handles compatibility decomposition but does NOT collapse Cyrillic→Latin (those are *canonical* in different scripts, not compatibility variants). Quick check: `unicodedata.normalize('NFKC', 'аuth')` returns `'аuth'` unchanged (the 'а' is still U+0430). The mitigation as described will *not work*. Real fix needs either a confusables map (Unicode TR39 skeleton algorithm) or restricting input to `[\x00-\x7F]` after a "is-this-script-mixed" check.
- **suggested_fix:** Either (a) replace NFKC with `unicodedata.normalize('NFKD', s).encode('ascii', 'ignore').decode()` + log dropped non-ASCII chars (lossy, but defangs), or (b) ship the `confusables` PyPI package or vendored TR39 skeleton table. Verify the chosen approach against a pytest that asserts `'аuth'` (Cyrillic) → matches `\bauth\b`. The current spec will silently fail this test.

### CG-4: Codex tier-mixing math collides with "Codex additive" rule under opus_min math
- **persona:** feasibility
- **finding_id:** CG-4
- **severity:** major
- **class:** contract
- **title:** "Codex stays 'additive, not counted' but Codex is GPT-5 lineage — does it satisfy spec's Opus floor or not?"
- **body:** Spec says Codex is `additive` and "not counted in panel size budget" / not in opus_count_actual. But the Anthropic 90.2% finding (cited in Constraints) is specifically about *Opus orchestrator + Sonnet subagents*. Codex is *neither*. If the goal of opus_min ≥ 1 is the published quality floor, Codex doesn't substitute. If the goal is "≥1 strong reviewer," Codex (GPT-5 reasoning class) arguably does. The spec doesn't pick a side. This matters for budget=1 panels where Codex is present: do we still upgrade the sole Claude persona to Opus, or does Codex's presence relax the floor? A8 says Opus wins, but doesn't address the Codex-present subcase.
- **suggested_fix:** Add explicit rule: "Codex presence does NOT substitute for opus_min; opus_min applies to Claude panel only. Codex is a separate quality axis." Add A24 fixture: budget=1, opus_min=1, codex=available → sole Claude persona gets Opus AND Codex dispatches.

## Important Considerations

### IC-1: Resolver-recompute on every dispatch is a per-gate cost not budgeted
- **persona:** feasibility
- **finding_id:** IC-1
- **severity:** major
- **class:** scope-cuts
- **title:** "Edge Case 23 mandates re-running _tag_baseline.py at every gate dispatch — multiplies regex passes 3×"
- **body:** Each `/spec-review`, `/plan`, `/check` invocation re-runs the full regex pipeline (NFKC + lowercase + fence-strip + 9 regex patterns) over potentially-large spec bodies. For a 50KB spec, that's ~3× per pipeline run, plus subset-comparison logic. Negligible at v1 scale, but the spec doesn't document the wall-clock budget. Risk: future specs with 200KB+ content (some autorun specs already approach this) push resolver wall-clock past the per-gate timeout budget. No telemetry to detect drift.
- **suggested_fix:** Add wall-clock assertion to A22: `_tag_baseline.py` over a 100KB synthetic spec completes in <500ms. Cache recompute result keyed by `sha256(spec.md)` within a single autorun pipeline (legitimate cache; spec content can't change mid-pipeline).

### IC-2: `tier_pins` promotion (Edge Case 5) has no deterministic tiebreak
- **persona:** feasibility
- **finding_id:** IC-2
- **severity:** major
- **class:** contract
- **title:** "When tier_pin promotes a persona INTO panel and multiple lower-ranked personas could be dropped, which is dropped?"
- **body:** Edge Case 5: "tier_pin promoted X into panel; dropped <other-persona>". When budget=4 and 2 personas are below the cut-line with identical combined scores (cold-start makes this likely — load_bearing_rate=0.5 uniform), the spec doesn't say which gets dropped. Non-determinism here means the same spec produces different panels on different runs, which breaks the "deterministic, auditable" property called out in the Approach rationale.
- **suggested_fix:** Add to A5: "Drop ordering is deterministic: lowest combined score wins drop; ties broken by `fit_score DESC, persona name ASC`." Codify in `_tier_assign.py` and assert in test matrix.

### IC-3: Persona registry source-of-truth ambiguity
- **persona:** feasibility
- **finding_id:** IC-3
- **severity:** major
- **class:** contract
- **title:** "SEC-01 validation reads `personas/<gate-dir>/*.md` — but install.sh symlinks personas into ~/.claude/personas/"
- **body:** Adopter installations symlink personas from MonsterFlow into `~/.claude/personas/`. The `_tier_assign.py` registry-load step reads the on-disk persona files. Question: does it read from the local repo (`personas/`) or the user's global location (`~/.claude/personas/`)? In an adopter project that has both (overrides), conflict resolution isn't specified. A `--tier-pin check:scope-discipline:opus` could pass validation against the global registry and fail against a stale local override (or vice versa).
- **suggested_fix:** Document explicit resolution order in spec: project-local `personas/` wins over `~/.claude/personas/`; missing local falls through to global; both missing = error. Add A21 fixture covering each path. Mirror the lookup logic that `resolve-personas.sh` already uses (don't reinvent).

### IC-4: Stale-tags warning heuristic is unspecified
- **persona:** feasibility
- **finding_id:** IC-4
- **severity:** major
- **class:** contract
- **title:** "A11 says 'tag heuristic re-inference shows ≥1 enum delta' but doesn't define heuristic"
- **body:** Stale-tags warning fires when "fresh inference" disagrees with recorded tags. But fresh inference is *baseline ∪ LLM*, and LLM is non-deterministic — every gate run could plausibly show drift. Result: warning becomes noise (cried-wolf), users tune it out, real drift escapes notice. The defense for `security` is the resolver-recompute (Edge Case 23), but the *warning* pathway uses a different signal that isn't pinned down.
- **suggested_fix:** Restrict stale-tags warning to baseline-only delta (deterministic). LLM-additions are excluded from drift detection. Reword A11: "drift = recorded baseline ⊊ recomputed baseline (strict-subset only)". This piggybacks on the SEC-02 mechanism and avoids LLM noise.

### IC-5: A20 "ship through itself" is hand-waved
- **persona:** feasibility
- **finding_id:** IC-5
- **severity:** minor
- **class:** tests
- **title:** "Chicken-and-egg dogfood deferred — but this is the highest-confidence integration test"
- **body:** A20 acknowledges the dogfood test is deferred. But this is exactly the test that catches "model param doesn't dispatch the way we think" (CG-1) and "fit_tags backfill missed personas" (W3) — the integration risks the test suite can't catch with fixtures. Without it, first real signal is post-merge.
- **suggested_fix:** Add a post-merge AC: first 5 specs through the renamed pipeline emit a `tier_dispatch_verified: true` audit row in selection.json with no human escalation. Track in CHANGELOG.

## Observations

### O-1: Backfill of 19 personas' fit_tags is the schedule risk
W3 backfills `fit_tags:` across all 19 personas. The closed enum is small (9 values), but persona role boundaries blur (ambiguity vs. completeness; gaps vs. requirements). Expect ≥1 round of human override during backfill. Worth budgeting a session for human review, not just LLM-propose.

### O-2: opus_min budget cost is unstated
Constitution defaults to `opus_min: 1`. For a 4-persona panel, that's 25% Opus / 75% Sonnet. For budget=2 (token-economics defaults), it's 50% Opus. No per-pipeline cost estimate is published. Adopters with strict cost ceilings need a back-of-envelope number to set `opus_min: 0` knowingly.

### O-3: `_explain_format.py` and SEC-03 mutation-zero test are well-scoped
The read-only formatter approach is correct; the `find -newer` mutation-zero assertion is a strong test discipline. Apply same pattern to `_tag_baseline.py` (it should also be I/O-pure: stdin→stdout, no file writes).

### O-4: Edge Case 21 grammar is correct but escape-sensitivity is undertested
The 3-or-more-backtick balanced-fence regex is right, but the spec's own A22 fixtures need to include a fixture that *itself contains nested fences in markdown* (this very review document, for example). Test this on a real prior spec like `pipeline-gate-permissiveness/spec.md`.

### O-5: Constitution-rename carve-out is good scope hygiene
Splitting `monsterflow-pipeline-config-rename` to a sibling spec is correct — it's pure find/replace + symlink risk and would have doubled this spec's surface area for zero behavioral gain.

## Verdict

**FAIL** — three blockers (CG-1 unverifiable tier dispatch, CG-2 over-broad api regex, CG-3 NFKC doesn't actually collapse Cyrillic homoglyphs as claimed) must be resolved before `/plan`; CG-4 Codex/opus-min interaction needs an explicit rule. Once those four are addressed, the spec is solid and the IC items can ride into `/plan`.

---

## gaps

# Missing Requirements Review — `dynamic-roster-per-gate`

## Critical Gaps
*(Must be answered before implementation can start)*

1. **Concurrent resolver invocations / `selection.json` write race.** Two `/spec-review` runs in parallel shells, or autorun retry overlapping with manual gate, both write `selection.json`. No lock strategy specified. Edge Case 10 says "no cross-spec state" but doesn't address same-spec concurrent dispatch. *Class: contract.*

2. **Audit logging for SEC-01 rejection events.** A21 documents the rejection error string but only specifies stderr. A spec-level downgrade attempt against a security persona is a security boundary breach by definition — it must persist somewhere durable (followups.jsonl row? dedicated `security-events.jsonl`?). Stderr is lost on autorun's piped tee. *Class: security, tags: ["sev:security"].*

3. **Backwards-compat for existing `selection.json` without `tier` field.** Dashboard W6 reads `selection.json` for the "Panel Tier Mix" column. Pre-feature rows have no `tier`. Render-path behavior (skip / show "—" / crash?) is unspecified. *Class: contract.*

4. **Closed-enum source-of-truth.** The 9-value tag enum lives in three places: `schemas/spec-frontmatter.schema.json`, `_tag_baseline.py` `BASELINE_KEYWORDS`, and every persona's `fit_tags`. No lockstep guard specified — this is exactly the "schema/validator drift" pattern flagged in MEMORY (`feedback_schema_bump_grep_prose_drift`). Add a CI test asserting the three sources agree. *Class: architectural* (carve-out: integrity).

5. **Tiebreaker rule for equal combined scores.** When two personas tie on `(fit_score × load_bearing_rate)` and only one panel slot remains, ordering is non-deterministic across Python dict / shell array iteration. Different runs of the same spec can dispatch different panels. Specify a deterministic tiebreaker (alphabetical persona name? roster-file order?). *Class: contract.*

6. **Bootstrap behavior when `~/.config/monsterflow/config.json` is missing or malformed.** Spec says "constitution provides default" but doesn't specify: does the resolver synthesize an in-memory default? Refuse to run? Write a default file? Adopters running for the first time post-merge will hit this immediately. *Class: contract.*

## Important Considerations

- **Cost quantification.** Adding ≥1 Opus reviewer to every panel × 3 gates × N adopters has a real token-cost delta. No estimate, no opt-out, no monitoring hook. At minimum, document expected cost increase in `docs/budget.md`.
- **Multi-user repo / per-user tier policy.** A repo where contributor A is on Pro (Opus rate-limited) and B is on Max — `pipeline-config.md` is git-tracked, so policy is shared. No per-user override layer (e.g., `~/.config/monsterflow/local-config.json`) specified.
- **`fit_tags` backfill migration.** "LLM proposes, user reviews" — but no spec on idempotency (re-running shouldn't re-classify), rollback (if backfill is wrong), or version-pinning the backfill batch.
- **Schema versioning for the closed enum.** How does an adopter add `infra` or `compliance` to the tag enum? No documented procedure; today's hardcoded list will become tomorrow's blocker.
- **TOCTOU between resolution and dispatch.** Resolver names persona X; persona file edited/deleted before Agent tool dispatches. No revalidation step.
- **Anthropic deprecates / outages Opus mid-pipeline.** A model outage on Opus = full pipeline halt under current spec. The Out-of-scope says "user is responsible for setting `opus_min` they can afford" but not what happens when Opus is down. Sibling spec `pipeline-rate-limit-resilience` is carved out — confirm this gap is the carve-out's scope, not a different one.
- **Permissions on `~/.config/monsterflow/config.json`.** This file now contains `security_floor` and `spec_overridable_keys` — security-policy-bearing data. No chmod requirement specified (cf. CLAUDE.md `chmod 600` discipline for keyed material; this isn't a key but it IS a policy floor).
- **Telemetry on LLM tag-inference accuracy.** No mechanism to know whether `/spec` Phase 3 LLM proposals are landing right tags. After 50 specs, are we routing correctly?
- **Rollout strategy.** Big-bang at merge, or feature-flagged behind `tier_policy.enabled: false` default? In-flight autorun runs during upgrade are not addressed.
- **`tier_pins` referencing a persona with empty `fit_tags`.** Edge Case 13 covers persona missing `fit_tags` (eligible only via cold-start). But what if `tier_pins` explicitly pins such a persona? Promotion path unclear.

## Observations

- **I18N for `_tag_baseline.py`.** NFKC closes Cyrillic homoglyphs (good), but baseline regex still only matches Latin keywords. Spec content in CJK or non-Latin scripts won't match `auth`/`token`. Probably OK to defer, but worth noting in Out-of-scope.
- **Dashboard tier-mix accessibility.** "1 Opus / 5 Sonnet + Codex" as a text label is screen-reader-friendly, but if any color coding is added at render, ensure it's not color-only signal.
- **Cold-start "graduation" criteria.** Spec says "fewer than 3 runs per persona → uniform 0.5". When does the system transition? Per-persona threshold or panel-wide? Reproducibility around the boundary (run 2 vs run 3) is unspecified.
- **Support runbook gap.** With `--explain` deferred to a sibling spec, ops debugging "why didn't persona X run?" requires reading raw `selection.json`. Acceptable for v1; document the field meanings in `docs/`.
- **AC count vs claim.** A18 says "40–60 PASSes"; A1–A23 plus matrix expansion easily exceeds this. Update the count or clarify it's matrix-only.
- **A20 chicken-and-egg.** Self-application deferred; reasonable, but worth a one-line follow-up note in `BACKLOG.md` so it doesn't get lost.
- **Edge Case 19 silent demotion.** `--explain` silently demotes `--emit-selection-json`. Logging the demotion is good, but consider exit-code signal (nonzero with explanation) to prevent CI scripts from missing the suppression.

## Verdict

**PASS WITH NOTES** — Scope is well-disciplined and security carve-outs (SEC-01/02/03) are unusually mature for a draft, but six operational/compat gaps (concurrency, audit-log persistence, backcompat render path, enum lockstep, tiebreaker determinism, bootstrap-without-config) need explicit answers before `/plan` so design doesn't paper over them.

---

## requirements

# Requirements Completeness Review: dynamic-roster-per-gate

## Critical Gaps

**CG-1: "Stale tags" drift detection has no defined heuristic.**
- finding_id: req-completeness-stale-tags-heuristic
- severity: blocker
- class: contract
- A11 says "tag heuristic re-inference shows ≥1 enum delta" but the heuristic is undefined. Is it a re-run of `_tag_baseline.py`? An LLM call? A diff against a stored hash? A QA engineer cannot write a deterministic test for "drift detected" without knowing what comparison runs. **Suggested fix:** define drift as `_tag_baseline.py(current_content) ⊋ recorded_tags ∪ baseline_recorded`, or pin the comparison to recompute-baseline-only and document the exact rule.

**CG-2: A18 test count contradicts Scope's stated target.**
- finding_id: req-completeness-test-count-conflict
- severity: major
- class: tests
- Scope says "target: 50-70 fixtures." A18 says "40-60 PASSes." Plus security tests in A21–A23 add at minimum 8-10 fixtures, pushing total to ≥50. The two numbers cannot both be the acceptance criterion. **Suggested fix:** pick one — recommend "≥50, target 50-70, deterministic, <10s wall-clock" — and align Scope and A18.

**CG-3: A20 explicitly defers an acceptance criterion ("chicken-and-egg") without a recovery plan.**
- finding_id: req-completeness-a20-deferred
- severity: major
- class: tests
- "Pipeline cycle through itself … deferred — chicken-and-egg" is not an acceptance criterion; it's a known gap stated as one. Either drop A20, or define a concrete bootstrap test (e.g., "after this spec ships, the next spec written exercises dynamic-roster end-to-end and lands in `tests/test-dynamic-roster-dogfood.sh`"). **Suggested fix:** delete A20 or replace with a measurable post-ship dogfood test.

**CG-4: Performance / latency budget undefined for the resolver hot path.**
- finding_id: req-completeness-resolver-perf-budget
- severity: major
- class: contract
- The resolver now runs `_tag_baseline.py` regex over full spec content at *every* gate dispatch (Edge Case 23, mandatory). On large specs (this one is ~600 lines) across 3 gates × autorun, that's 3-6 invocations per run. No latency target is stated. A18 covers test wall-clock but not production dispatch overhead. **Suggested fix:** add NFR like "resolver-recompute adds ≤500ms p95 to gate dispatch on a 1000-line spec" and a benchmark fixture.

**CG-5: Failure mode for `_tag_baseline.py` crash / regex error is undefined.**
- finding_id: req-completeness-baseline-crash-mode
- severity: major
- class: architectural
- If `_tag_baseline.py` raises (malformed input, regex catastrophic backtrack, encoding error post-NFKC), what does the resolver do? Halt? Fall through to ranking-only? Emit empty baseline (which would FAIL the subset-check on the recorded baseline if anything was recorded)? This is load-bearing because it's a security control — silent failure mode is the attacker's win condition. **Suggested fix:** define fail-closed behavior: "any exception in `_tag_baseline.py` halts dispatch with `error: baseline classifier failed; refusing to dispatch (fail-closed for security)`. Exit 4."

## Important Considerations

**IC-1: A19 "schema lockstep" lacks the grep-test for prose drift learning.**
- finding_id: req-completeness-schema-prose-drift
- severity: major
- class: tests
- MEMORY.md flags that file-pair lockstep guards miss inline JSON examples in `commands/*.md` and heredocs. This spec has many such inline examples (selection.json blocks, frontmatter blocks). A19 should require the grep-test, not just file-pair stubs. **Suggested fix:** A19 adds "and `tests/test-schema-prose-drift.sh` greps `commands/*.md`, `scripts/autorun/*.sh`, `docs/index.html` for stale schema literals."

**IC-2: Edge Case 6 ("typo class — halt-and-fix") uses an inconsistent verdict pattern.**
- finding_id: req-completeness-typo-halt-vs-permissive
- severity: minor
- class: contract
- v0.9.0 just shipped permissive-by-default. A `tier_pins` typo halting is the right call, but the spec doesn't tell us which exit code (2? 3? 4?) versus the SEC-01-followup CLI exit codes (which are documented: 0/2/3/4). Be explicit. **Suggested fix:** standardize all config-load halts to exit 2 (invalid input) per the documented contract; emit a single `[tier-policy] config error: <reason>` prefix.

**IC-3: Observability — no logging requirement for `tier_policy_applied` resolution.**
- finding_id: req-completeness-observability
- severity: minor
- class: documentation
- `selection.json` records `tier_policy_applied.source` (constitution|spec|cli), but there's no requirement that the *override chain* (which key came from where) is logged. With 3 layers × multiple keys × CLI partial overrides, debugging an unexpected dispatch will be painful. **Suggested fix:** require `tier_policy_applied.merge_trace: [{key, source, value}]` and surface in the deferred `--explain`.

**IC-4: A11 "stale-tags" warning has no auto-mode policy beyond Edge Case 11.**
- finding_id: req-completeness-stale-tags-auto-mode
- severity: minor
- class: contract
- Edge Case 11 says "warning only, no halt" in auto. But under per-axis policy, stale tags on a security-tagged spec where current content suggests the security tag should now be absent (or vice versa) is a class-routing risk. Should there be a *minor* policy: "if drift adds `security` and recorded didn't have it, recompute treats as additive (already covered by SEC-02), but log the warn at WARN level"? Currently only INFO/warning is implied. **Suggested fix:** clarify the warning level and confirm autorun never blocks on it.

**IC-5: A14 "verified end-to-end" is not testable without a defined verification mechanism.**
- finding_id: req-completeness-a14-verification
- severity: minor
- class: tests
- "Both dispatch paths receive model param" — how is this verified? Mock the Agent tool? Inspect process args? Trace logs? **Suggested fix:** specify "tests assert `claude -p --model <tier>` appears in the autorun spawn args (via `set -x` capture or `BASH_XTRACEFD`); Agent-tool dispatch path tested via a fixture that records the `model:` argument."

## Observations

**O-1:** "Reliability uptime targets" and "acceptable error rates" are not stated. For a developer-tooling pipeline this is reasonable to omit, but worth noting the resolver becomes a single-point-of-failure for all three gates. A note like "resolver failure halts dispatch (fail-closed); no SLO" would close the question explicitly.

**O-2:** Accessibility / WCAG is N/A for a CLI tool, but the dashboard tier-mix column (W6) is HTML. No accessibility note. Probably fine for a private dashboard, worth a one-liner.

**O-3:** A21–A23 are excellent examples of binary, machine-verifiable acceptance criteria. A1–A20 lean more on prose; consider making A1–A14 more testable by referencing the specific fixture file each will live in.

**O-4:** "Recovery time" for a security-floor rejection (SEC-01) — is the user expected to edit and re-run, or is there a `--force-rerun` path? Per scope-discipline carve-out the escape hatch is v2. Worth noting the v1 recovery is "edit spec, re-run gate" explicitly.

**O-5:** The 7 baseline keyword classes use word-boundary `\b` regex. Cyrillic homoglyphs are NFKC'd first (good), but `\b` behavior with Unicode is Python-version-dependent — `re.UNICODE` flag should be explicit in the regex compile call. Worth a note in the W2 implementation.

**O-6:** Edge Case 20 (D7 anti-pattern) is well-written but classed implicitly. Recommend adding `class: security` + `tags: ["sev:security"]` to that finding when the implementation lands, since it's an architectural-trust-boundary rule.

## Verdict

**PASS WITH NOTES** — Spec is unusually thorough on the security axis (SEC-01/02/03 with named carve-outs and worked adversarial fixtures) and on scope discipline (every deferral has a sibling-spec name); the 5 critical gaps are all completable without architectural change — they're tightening of test heuristics, perf budgets, and fail-closed behavior, plus reconciling the A18-vs-Scope test-count conflict before /plan.

---

## scope

# Scope Analysis — dynamic-roster-per-gate

## Critical Gaps

**C1. Scope/Deferral contradiction — constitution rename.** The "Out of scope" section explicitly defers constitution rename to sibling spec `monsterflow-pipeline-config-rename`, but the spec body keeps the work fully scoped:
- W6 in Integration lists "All references… rename to `pipeline-config.md`" as build work
- A15 is an acceptance criterion for the rename
- Data & State defines the new `pipeline-config.md` file structure
- Edge Case 8 covers the rollback symlink for the rename
- `~/.config/monsterflow/config.json` example references the renamed file

Either the carve-out is wrong (rename is actually in v1) or the spec body is wrong (these references must be deleted). This must be resolved before implementation — otherwise the "deferred" sibling spec becomes a no-op and reviewers can't trust the carve-outs at all.

**C2. Scope/Deferral contradiction — `--explain` flag.** Same pattern. Out-of-scope carve-out says "`--explain` flag — sibling spec `pipeline-resolver-debugging`," but:
- W2 lists `scripts/_explain_format.py (NEW)` and `--explain` as resolver build work
- A23 (SEC-03) is a full acceptance criterion for `--explain` mutation-zero behavior
- Edge cases 18, 19 cover `--explain` semantics
- `tests/test-explain-mutation-zero.sh` is in W7

If SEC-03 (mutation-zero `--explain`) is genuinely required for v1's security posture, then `pipeline-resolver-debugging` is not actually deferred and the carve-out is misleading. If `--explain` truly is v2, then SEC-03 must be re-scoped or deleted. Pick one.

**C3. AC count drift.** Scope says "target: 50-70 fixtures." A18 says "40-60 PASSes." Test work estimates differ by ≥25%. Pin a single number — this affects effort sizing and `/check`'s test-orchestrator-wiring verification.

**C4. A20 is not an acceptance criterion.** "Pipeline cycle through itself… deferred — chicken-and-egg" is a TODO, not an AC. Either delete it or convert to "v1 ships under v0.9.0 defaults; dogfood pass is explicitly out of scope" with no test obligation. Leaving an AC that says "deferred" makes the AC matrix ambiguous.

## Important Considerations

**I1. MVP question — feature is bundling 4 independent capabilities.** The spec ships, simultaneously:
1. Content-tag inference + matching (tags + fit_tags + intersection)
2. Tier-mixing rule (≥1 Opus floor, override layers)
3. SEC-01 security floor enforcement
4. SEC-02 deterministic baseline + adversarial-resistant inference

Each could ship independently. A natural phasing exists:
- v1a: tags + fit_tags + tag-matching dispatch (no tier work)
- v1b: tier rule + override layers (matches v0.9.0 gate_mode pattern)
- v1c: SEC-01/02 hardening
- v1d: dashboard column + stale-tags warning

The current "big bang" framing collapses these into one ship-unit. Given this spec is itself the result of carving 3 sibling specs out at run #6, the remaining bundle is still large. Worth asking: what's the smallest version that delivers value? Probably v1a alone — tier-mixing without tag-matching is just renaming v0.9.0; tag-matching without tiers is the more novel piece.

**I2. SEC-01/02/03 scope weight.** The three security-axis additions account for ~30% of the test surface (A21, A22, A23 plus 3 dedicated test files), introduce 2 new Python modules (`_tag_baseline.py`, `_explain_format.py`), and add NFKC normalization, code-fence regex, resolver-side recompute, and AST banlists. These are all defensible but represent a security-hardening sub-spec inside a roster-selection spec. Day-after-launch question: will reviewers ask "why is the deterministic baseline regex coupled to the tier-mixing rule?" The answer is "they aren't, but this spec ships both." Consider whether SEC-02 belongs in `pipeline-security-escape-hatches` alongside the deferred downgrade hatches.

**I3. 19-persona fit_tags backfill is a separate change-class.** W3 buries a one-time data-migration of all 19 existing personas (LLM-propose-user-confirm) inside the implementation. That's content-creation work, not code. It has different review needs (does the security-architect persona's fit_tags actually claim `security`? Does the testability persona claim `tests`?) than the resolver code. Treat it as either (a) its own ship-unit gated on user content review, or (b) explicitly call out that backfill quality is reviewed separately from `/build` agent work — otherwise a `/build` agent will fabricate fit_tags from persona descriptions and ship without a human pass.

**I4. Dashboard tier-mix column is "while we're in there."** The "Panel Tier Mix" column on `dashboard/index.html` is genuinely useful but not load-bearing for the resolver feature. Day-after-launch users will dispatch fine without it; it's observability. Consider deferring to a v1.1 dashboard pass — it'll let `/build` finish faster and gives natural follow-on work.

**I5. Stale-tags warning is orthogonal feature.** `/spec-review` Phase 1 step 0 drift detection is genuinely useful but is its own concern (spec hygiene). It belongs more cleanly in a "spec-frontmatter validation at gate dispatch" spec. In this spec it's a 1-AC bolt-on (A11) without supporting infrastructure.

## Observations

**O1. Closed-enum tags (9 values) will need extension.** The closed enum `[security, data, api, ux, integration, scalability, docs, refactor, migration]` will inevitably be asked to grow (e.g., `performance`, `observability`, `compliance`). Edge Case 14 says unknown values halt-and-fix. Plan the extension path now — even a one-line "to add an enum value, edit `schemas/spec-frontmatter.schema.json` + every persona's `fit_tags` if relevant + bump schema version." Otherwise the first user PR adding `performance` to a spec will block on schema review.

**O2. `pipeline-gate-rightsizing` siblings folded vs. left.** The "Backlog Routing" table pulls lever 2 of `pipeline-gate-rightsizing` into this spec but leaves levers 1, 3, 4, 5, 6 in BACKLOG. Once this ships, rightsizing's surface area shrinks — worth a re-spec pass on the BACKLOG entry to confirm it still stands on its own (or whether some levers are now obsolete given content-aware selection).

**O3. Cold-start defaults are load-bearing.** A10 + Edge Case 13 specify cold-start fallbacks: empty fit_tags → ranking-only; no rankings → seed-list; both empty → tier rule on seed list. This is the path for any new project before personas have run enough times. Worth promoting to a named "Cold-Start Behavior" subsection (alongside Edge Cases) — adopters will want to know "what does this look like on day 1 of a fresh project?"

**O4. Override precedence merge semantics.** Edge Case 12 says "key-level merge, not block-level replacement." This is correct but easy to get wrong in implementation. Worth one explicit example: constitution sets `tier_pins: {check: {scope-discipline: opus}}`, spec sets `tier_pins: {plan: {sequencing: opus}}` → merged result has both pins. Without this example, the first `/build` agent will probably write block-level replacement and break A6.

**O5. The `agent_budget` interaction with `opus_min` deserves a worked example in §UX.** Budget=2, opus_min=2 is fine. Budget=2, opus_min=1 → top-1 Opus + #2 Sonnet. Budget=1, opus_min=2 → opus_min clamps to 1 (Edge Case 7) or wins (Edge Case 1)? The two edge cases describe different scenarios but adopters will conflate them. Add a 2x2 table.

**O6. A19 file-pair stub language is correct precedent.** Good — explicitly cites v0.9.0 lockstep guard. This is the right shape for schema work.

## Verdict

**FAIL** — C1 and C2 (deferred items still fully implemented) are blocking; reviewers cannot assess scope when the carve-outs and the implementation list contradict each other. C3 and C4 are smaller but compound the AC-matrix ambiguity. Resolve all four before `/plan` can produce a coherent build wave plan.

---

## stakeholders

# Stakeholder Analysis Review: dynamic-roster-per-gate

## Critical Gaps

**CG-1. Adopters of MonsterFlow with existing constitutions are unaddressed.**
- `class: architectural`, `severity: blocker`
- The spec renames `constitution.md` → `pipeline-config.md` (carved to sibling spec) but the dynamic-roster spec itself depends on a `tier_policy` block landing in *that* file. Adopters who have already run `install.sh` and customized their constitution are a stakeholder group with conflicting needs: (a) they need their existing constitution preserved through the rename; (b) they need the new `tier_policy` block to materialize without overwriting their roster pins; (c) they cannot be told "wait for the sibling spec." The spec's symlink-for-one-release plan is in the *carved* sibling — meaning v1 ships requiring `tier_policy` from a file that has not yet been renamed. **Who reads pipeline-config.md if it doesn't exist yet for adopters?** The spec needs an explicit "adopters on `constitution.md`" path: the resolver MUST also accept `tier_policy` from the legacy filename until the rename ships, OR this spec must hard-block on the rename spec landing first. Sequencing claim "ships unblocked" is wrong if `pipeline-config.md` is the canonical source and that file is being introduced by another spec.

**CG-2. Rate-limit / Opus unavailability stakeholder (Pro-tier users) gets one-line dismissal.**
- `class: architectural`, `severity: major`
- Out-of-scope says: *"Auto-detecting model availability per account tier (Opus may be rate-limited on Pro; user is responsible for setting opus_min they can afford)."* This punts a real stakeholder group — Claude Pro adopters whose autorun pipeline will now hard-fail when Opus 429s — onto the user. The carved-out `pipeline-rate-limit-resilience` spec is referenced but the **MVP behavior on 429** is undefined: does the panel halt? Auto-degrade to all-Sonnet? Retry? Without an MVP answer, autorun runs at 2am will silently fail mid-gate and adopters won't know why. Either define minimum behavior (e.g., "on Opus 429, degrade panel to all-Sonnet + emit warning + continue") or block on the sibling spec.

## Important Considerations

**IC-1. Persona authors as a stakeholder are under-served.**
- `class: documentation`, `severity: major`
- The spec backfills `fit_tags:` into 19 existing personas (W3) via "LLM proposes, user reviews." But who decides the canonical mapping? Future persona authors (the 28th persona, the 35th persona) need a written rubric: *when does a persona qualify for `security` fit_tag vs `integration`?* Without it, fit_tags drift over time, ranking degrades, and the security-floor (SEC-01) protection becomes inconsistent (a security-relevant persona without `fit_tags:[security]` escapes the floor entirely — silent failure of the protection). Add a `docs/personas-authoring-guide.md` deliverable to W3.

**IC-2. QA/testability stakeholder — A20 admits the dogfood test is deferred.**
- `class: tests`, `severity: major`
- AC#20 says *"this spec ships under v0.9.0 defaults AND its own dynamic-roster framework once merged (last-mile dogfood test ... chicken-and-egg, deferred)."* The QA stakeholder ("can they test this?") is told the spec doesn't fully verify itself. At minimum, define an explicit post-merge validation step: rerun `/spec-review` against this spec.md *after* merge with the new framework active and capture the panel composition; fail the release if the panel doesn't include security-architect:opus given `tags:[security, ...]`. Without that, A2 (Opus floor) is unverified in production.

**IC-3. Customer-support / autorun-overnight stakeholder needs error-string contracts.**
- `class: contract`, `severity: major`
- The spec defines several halt-with-error paths (SEC-01 downgrade rejection, SEC-02 baseline drift, Edge Case 6 nonexistent persona, Edge Case 14 unknown enum). When autorun halts at 2am, the user wakes to a stderr line. The spec quotes some error strings verbatim (good) but not all (Edge Case 6, 7, 13, 14). Lock down all halt-error strings as a contract and test them. Otherwise support tickets will be "autorun stopped, no idea why" and Justin (sole maintainer-support) absorbs the cost.

**IC-4. The "user editing spec.md to remove a baseline tag" workflow has a dead end.**
- `class: ux`, `severity: major`
- Edge Case 17 + the deferred `--acknowledge-baseline-mismatch` flag combine to create a UX trap: if the baseline regex falsely-positives on a user's spec content (e.g., the word "session" appears in a non-security context — `/spec` Phase 3 itself is a "session"), the user *cannot* set `tags:` without `security` until they edit the spec body to remove the matched keyword. For a docs-only spec that mentions "session" in passing, this forces a Opus reviewer they don't need. The escape hatch is carved out, so v1 ships with a known false-positive trap. At minimum: (a) document the trap loudly in the user-facing error, (b) ensure the BASELINE_KEYWORDS list is conservative enough that false positives are rare (the current `session` regex with no qualifier WILL false-positive — recommend `session[-_ ](token|cookie|hijack|fixation|management)` to scope it).

**IC-5. Dashboard maintainer / data-analytics stakeholder — selection.json schema versioning.**
- `class: contract`, `severity: minor`
- A19 mentions schema lockstep but the new `tier_policy_applied` block on `selection.json` is a schema bump. Existing dashboard renderers reading older `selection.json` rows must continue to work (downstream `judge-dashboard-bundle.py` runs over historical data). Spec needs an explicit version field on `selection.json` and a migration path note.

## Observations

**O-1. Codex stakeholder is well-served** — the additive-not-counted rule is explicit at A7 and Edge Case 9. Good.

**O-2. Security stakeholder is heavily represented** — SEC-01/02/03, dedicated test files, run #6 followups inline. Strong. The class-tagging follows the precedence rule well.

**O-3. Conflict — speed vs safety on autorun.** The spec leans safety (halt-and-fix on Edge Case 6, 14; SEC-01 reject; SEC-02 drift halt). Combined with v0.9.0 permissive gates, this is the right balance — but four halt paths × autorun-overnight × no escape hatches in v1 means the probability of overnight autorun completion drops. Acceptable trade-off, but call it out in CHANGELOG so adopters can lower expectations.

**O-4. Conflict — power users vs new adopters on `tier_policy`.** Three layers (constitution → spec → CLI) plus `spec_overridable_keys` plus `tier_pins` is genuinely complex. New adopters running `/kickoff` need a sane default that "just works." Confirm the default constitution shipped by `install.sh` carries `opus_min: 1` and an empty `tier_pins: {}` so adopters don't have to think about this on day 1.

**O-5. "Veto power" stakeholder check** — the security-architect persona effectively has veto power over its own tier (SEC-01 floor). That's correct and intentional, but the spec doesn't name it. Worth a one-liner in the security section: "The constitution is the floor; security-class personas cannot be downgraded by spec authors."

**O-6. Launch communication missing.** No mention of CHANGELOG entry beyond "[Unreleased]" or a release-notes user-facing summary. For a feature this central to the pipeline, adopters need a "what changed in v0.10.0" doc. Add to W6.

## Verdict

**PASS WITH NOTES** — the spec covers most stakeholders well and the security-axis treatment is unusually strong, but two stakeholder gaps (existing-constitution adopters during the rename, Pro-tier users hitting Opus rate limits) need MVP answers before implementation, and four important considerations (persona-authoring rubric, dogfood verification, error-string contracts, baseline false-positive UX) should be folded in or explicitly carved before /plan.

