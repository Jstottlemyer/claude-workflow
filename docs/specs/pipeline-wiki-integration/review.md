# Pipeline ↔ Obsidian-Wiki Integration — Review

**Reviewed:** 2026-04-17 (round 1) + 2026-04-17 (round 2, post-refinement)
**Spec:** `docs/specs/pipeline-wiki-integration/spec.md` (currently v1.1)
**Reviewers:** 6 PRD personas (requirements, gaps, ambiguity, feasibility, scope, stakeholders) + judge + synthesis passes.
**Overall health after round 2:** Good — all round-1 blockers resolved; remaining notes are non-blocking.

---

## Round 2 (against spec v1.1)

All six round-1 blockers are closed. Ambiguity's round-1 **FAIL** is now **PASS WITH NOTES**. No reviewer flagged a new critical gap.

### Round 1 → Round 2 Status

| v1.0 Blocker | v1.1 Resolution | Status |
|---|---|---|
| Session-boundary detection semantics | Pinned bash snippet (working-tree dirty + unpushed commits under `docs/specs/`), no-upstream fallback defined | Closed |
| Karpathy 4-trigger rubric | Per-trigger inspect-artifacts + candidate/none criteria + all-none fallback | Closed |
| `wiki-update` / `wiki-query` contract unverified | Contracts verified against actual SKILL.md files; steering mechanism redesigned around host-agent conversational context (no source-path args); spec gained a "Skill Contracts (verified)" section | Closed |
| Topic derivation + relevance contract | Raw `$ARGUMENTS` as query; ≥1 `[[wikilink]]` citation as render floor; 5-citation cap with overflow note | Closed |
| User-comment pass-through channel | Plain text prepended to invocation prompt; not a skill arg; shell-metacharacter safe | Closed |
| `wiki-query` timeout | 10s soft timeout; silent skip on timeout; `QUERY_TIMEOUT` log line in `$VAULT/log.md` | Closed |

### Round 2 Reviewer Verdicts

| Dimension | Round 1 | Round 2 |
|---|---|---|
| Requirements | PASS WITH NOTES | **PASS** |
| Gaps | PASS WITH NOTES | PASS WITH NOTES |
| Ambiguity | **FAIL** | PASS WITH NOTES |
| Feasibility | PASS WITH NOTES | **PASS** |
| Scope | PASS WITH NOTES | **PASS** |
| Stakeholders | PASS WITH NOTES | PASS WITH NOTES |

### Round 2 — Non-Blocking Notes

1. **Steering-via-context is empirically unverified** *(4/6 reviewers)*
   The write side's distillation quality depends on the host agent interpreting the two prepended lines (touched dirs + user comment) while executing `wiki-update`. This is not a deterministic skill contract — it's a behavioral assumption. AC #2 and AC #5 attempt to verify it ("content observably derived from the comment is present") but that pass/fail is subjective. Open Question #2 already tracks a formal `--focus`/`--comment` args upgrade to `wiki-update` as the fallback if dogfood shows steering is too weak.
   **Recommendation:** accept for v1 dogfood; record the first-dogfood comment + resulting page so a later spec has evidence to justify the formal args.

2. **Callout one-liner derivation undefined** *(1/6)*
   The callout template (`"Prior wiki knowledge"` section) shows *"one-line synthesis"* per cited page. `wiki-query` returns a single synthesized answer, not per-page lines. Three reasonable derivations: (a) truncate `wiki-query`'s prose around each `[[wikilink]]`, (b) re-prompt the agent to summarize each cited page in one line, (c) read each cited page's `summary:` frontmatter field.
   **Recommendation:** pin (c) — `summary:` frontmatter is cheap, deterministic, and was designed exactly for this retrieval pattern per `wiki-query`'s Step 2 contract.

3. **Wikilink-counting precedence** *(1/6)*
   If `wiki-query` returns *"the wiki doesn't cover X, but see [[related-topic]]"*, does the callout render (≥1 wikilink cited) or suppress (contains "doesn't cover" phrase)? Precedence not defined.
   **Recommendation:** suppress wins. Callout is about affirmative knowledge, not compensatory tangents.

4. **Touched-dirs awk edge case** *(2/6)*
   `awk -F/ '{print $1"/"$2"/"$3}'` parses `docs/specs/README.md` as feature-dir `docs/specs/README.md`. Cheap fix: `grep -E '^docs/specs/[^/]+/.+'` before the awk (requires at least one char beyond the feature-dir slash).
   **Recommendation:** apply the guard.

5. **10s timeout is advisory, not enforced** *(1/6)*
   Claude Code's Skill tool has no runtime timeout primitive. The budget is a prompt-level constraint ("if wiki-query hasn't returned in 10s, abandon"). Worth naming explicitly in the `/spec` command instructions so the host agent knows to self-enforce.

6. **CHANGELOG migration sentence** *(1/6)*
   The `/wrap` header reframes from "be fast, user is leaving" to "be thorough on capture." For public installers reading the diff, one line of user-facing migration guidance would prevent confusion.
   **Recommendation:** pin a template line, e.g., *"If you relied on `/wrap` being fast, note Phase 2c can add ~30s when spec dirs are touched; `skip` option always available."*

7. **AC #8 (query-timeout test) has no fixture** *(1/6)*
   "Inject `sleep 15 && …`" is a suggestion. Either define a stub skill procedure or accept the AC is tested by manual patch during dogfood.

8. **All-none + comment fires every spec-touching session** *(1/6)*
   Even pure-refactor sessions that touch a spec dir will render the findings block with four "none" rows plus the comment field. Dogfood will show whether this is useful friction or annoying friction.
   **Recommendation:** track as post-dogfood Open Question #5 if it becomes annoying.

9. **`chmod -w` portability** *(1/6)*
   AC #10's error-injection step is macOS/Linux only. Minor — add a one-line caveat or accept as tester-environment assumption.

10. **Multi-repo session edge** *(1/6)*
    `wiki-update` operates on cwd. If a session spans repos, cwd at `/wrap` time determines the scope. Rare; flag only.

11. **Observability thin** *(1/6)*
    Only `QUERY_TIMEOUT` emits a log line. No entries for Phase 2c gate-pass, sync invocation, or sync success. `wiki-update`'s own `log.md` entry may suffice — verify before shipping.

12. **PII for secondary users** *(1/6)*
    Open Question #4 (PII default tagging) is tracked. For public installers, the blast radius is higher than for solo-tool Justin. Worth surfacing when #4 revisits.

### Round 2 Observations

- `pick individually` is cleanly excised from Scope, Out of Scope, and UX with no ghost references.
- Skill Contracts (verified) section catches the v1.0 false assumption about `wiki-update` accepting source paths. Unusually good spec hygiene.
- `/wrap` header replacement pinned with exact before/after — zero interpretive latitude.
- All-none fallback preserves the comment-override escape hatch without adding branching complexity.
- Open Questions are all genuinely deferred, not hidden TODOs.
- Effort estimate (feasibility): half-day of focused work + dogfood cycle. No new code, no obsidian-wiki changes.
- Backlog Routing preserved from v1.0 — no new creep items added despite six-blocker remediation.

### Round 2 Recommendation

**Ready for `/plan`.** Apply the cheap implementation-touch-up fixes (items 2, 3, 4, 6 above) as small spec edits before `/plan`, or let `/plan`'s design agents absorb them as low-priority concerns. Either path is defensible.

---

## Round 1 (against spec v1.0 — retained for audit trail)

**Overall health after round 1:** Concerns — spec was well-bounded but four load-bearing items were underspecified. One reviewer voted FAIL.

### Round 1 Blocking Items

1. **Define "session boundary" for spec-dir detection** *(5/6)* — `git status --porcelain` is working-tree only; spec didn't define whether committed-this-session work counts. Penalizes primary user.
2. **Author the Karpathy 4-trigger rubric** *(4/6)* — labels without evaluation criteria. Load-bearing UX of Phase 2c undefined.
3. **Verify `wiki-update` and `wiki-query` contracts** *(3/6)* — spec asserted `wiki-update` "already accepts arbitrary source paths" — unverified; if false, effort doubles.
4. **Topic derivation + relevance contract** *(3/6)* — `$ARGUMENTS` → query and "relevant pages" threshold both hand-waved.
5. **User-comment pass-through channel** *(3/6)* — parameter name/format/shell-metacharacter handling undefined.
6. **`wiki-query` timeout** *(4/6)* — synchronous with no bound.

### Round 1 Non-Blocking Items

7. `pick individually` drill-down underspecified — recommend cut from v1.
8. `/wrap` header reframing vague — recommend pin exact text or strip from spec.
9. "Self-heals on next sync" asserted without citation.
10. Dogfood exit criterion implicit.

### Round 1 Reviewer Verdicts

| Dimension | Verdict | Key Finding |
|---|---|---|
| Requirements | PASS WITH NOTES | "Relevant pages" undefined; Karpathy rubric not pinned; `pick individually` untested |
| Gaps | PASS WITH NOTES | Topic derivation, relevance threshold, concurrent writes, comment channel, timeout |
| Ambiguity | **FAIL** | Karpathy rubric + session-detection + `wiki-update` source-path contract all load-bearing and undefined |
| Feasibility | PASS WITH NOTES | Verify `wiki-update` actually accepts source paths; if not, effort doubles |
| Scope | PASS WITH NOTES | Header reframing and `pick individually` are the creep vectors |
| Stakeholders | PASS WITH NOTES | Session-boundary penalizes primary user; public-user discoverability punt |

### Round 1 Conflicts Resolved

- **"Silent no-op" vs "inline error" wording tension** (one reviewer flagged): consistent as-is — silent when config missing, loud on runtime failure.
- **Effort estimate shape:** feasibility and scope both converged on the `wiki-update` source-path contract as the pivotal risk. Verified in round 2 and redesigned.

### Round 1 Recommendation

**Refine before `/plan`.** All 6 blocking items cheap to patch in the spec; `/plan` would surface them as unknowns anyway. Items 7–10 also worth pinning to prevent scope creep during `/build`.

**Outcome:** Round 2 shows refinement successfully closed all blockers; see Round 2 section above.
