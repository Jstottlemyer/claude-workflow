# Stakeholder Analysis — token-economics spec v3 (round 3)

**Reviewer:** stakeholders
**Round:** 3
**Lens:** who's affected, who's missing, where needs conflict

## Critical Gaps

(none)

No stakeholder is unrepresented at a blocker level. The four round-2 important findings are all addressed at the spec-text level, and the new public-release stakeholder cohort is at least named in the Privacy section. Nothing here would block `/plan`.

## Important Considerations

### 1. Persona-author exposure via the rendered dashboard (round-2 carryover, only partially fixed)

Round 2 flagged that personas with low judge_survival/downstream-survival become identifiable as "weak contributors." v3's response is correct as far as it goes — `persona-rankings.jsonl` is gitignored (A9), and the leakage canary (A10) prevents finding text from leaking. But the rendered surface is not just the JSONL — it's `dashboard/index.html` reading that JSONL into a sortable, sharable table, and the `/wrap-insights` text section that prints "highest" / "lowest" / "never run" lists.

Concrete leak vectors v3 does NOT close:
- Adopter screenshots the Persona Insights tab and posts it (Discord, Twitter, blog post on "what I learned running MonsterFlow"). Persona names + survival rates + cost ranks are now public, attached to whoever wrote those personas.
- Adopter pastes the `/wrap-insights` output into a GitHub issue ("hey, why is my `cost-and-quotas` persona at 12%?"). Same leak, with an audit trail.
- A persona contributor whose persona shows "never run" or "12% downstream-survival" in someone else's public screenshot has no recourse — they didn't consent to the comparison being public.

The Privacy section lists three gates but all three are about the *files on disk*, not the *rendered output*. Suggest one of:
- A doc note in `commands/wrap.md` and on the dashboard tab itself: "These numbers are about your local pipeline, not about persona quality — share with care." (cheapest)
- An opt-in flag in `~/.config/monsterflow/dashboard.json` to anonymize persona names in the rendered tab (`reviewer-A`, `reviewer-B`) — keeps local debugging signal, removes the share-the-screenshot leak. (medium)
- Strip the named bottom-3 list from `/wrap-insights` text entirely; keep top-3 only. (cheapest behavioral change, biggest signal loss)

This is round-2 finding #2 partially-addressed, not fully-addressed.

### 2. Adopter-with-private-projects consent is buried

The Privacy section says `compute-persona-value.py` will read `findings.jsonl` from any project Project Discovery finds — "including private ones (Luna's, career)." Two adopter-side stakeholder problems:

- Auto-discovery default scans `~/Projects/*/docs/specs/`. An adopter who runs `/spec` in `~/Projects/client-acme-confidential/` has no way to know their findings are now flowing into the cross-project aggregate until after the first `/wrap-insights` run. The consent moment is invisible.
- The escape hatch (explicit config in `~/.config/monsterflow/projects`) only helps adopters who *already know* about the cascade. The default behavior is opt-out, not opt-in.

Suggest: on first run of `compute-persona-value.py` (no `~/.config/monsterflow/projects` file present and >1 project discovered), print a one-time banner listing the discovered projects and the path to the config file for exclusion. Persist a `~/.config/monsterflow/.discovery-acknowledged` sentinel so it doesn't nag. This is the single highest-leverage change for the adopter-trust dimension.

### 3. Pro-tier-friend commitment language is good but unenforceable

The new Summary line — "Pro-tier relief comes in v1.1 (BACKLOG #3) immediately after this lands" — addresses the round-2 "Pro-friend orphaned" finding at the *language* level. As stakeholder representation it works: the friend is named, the commitment is in the spec, the routing table backs it up.

What's missing for enforceability: there's no acceptance criterion or BACKLOG.md cross-link saying "v1.1 spec exists in `docs/specs/account-type-scaling/` within N weeks of v1 merge" or "BACKLOG #3 promoted to a spec on the same calendar week as v1 ships." Without that, "immediately after" has the same enforcement profile as the v2 spec's "future work" — i.e., none. Suggest adding an A12 outcome criterion: "Within 14 days of v1 merge, `docs/specs/account-type-scaling/spec.md` exists with status ∈ {draft, ready-for-plan, ready-for-build}." Self-imposed deadline; verifiable.

### 4. New persona contributor onboarding (new in round 3)

Public release means PRs adding new personas to `personas/{review,plan,check}/`. The spec handles the data side correctly (e9: "(never run)" rows; A4: content-hash window reset). But the *contributor* stakeholder has no doc:

- A contributor who adds `personas/review/api-design.md` will see their persona in the dashboard immediately as "(never run)" — fine for accuracy, possibly confusing for them ("did I install it wrong?").
- Once their persona starts accumulating runs, `runs_in_window < 3` → rate cells render as "—". They have no signpost telling them "this is normal for the first 3 runs; not a bug."
- Worst case: a contributor adds a persona, runs it 5 times locally, sees a 20% downstream-survival rate, concludes their persona is "bad" and deletes the PR — when the real signal is "5 runs is too small a sample on one project."

Suggest: a paragraph in `commands/wrap.md` (or a `personas/CONTRIBUTING.md` if one exists) explaining the data lifecycle: insufficient-sample for the first 3 runs → rates appear → window stabilizes after ~45 runs → don't draw conclusions before then. Cheap; one paragraph. Closes the contributor-feedback loop the spec otherwise leaves open.

## Observations

- **Insufficient-sample fix (round-2 finding #4) is fully resolved.** Rendering rate cells as "—" rather than opacity-dimmed numbers does fix the sort-surface bug — a sortable column whose underlying value is the string "—" sorts as either all-low or all-high depending on collation, and either way the 1-run "100%" row no longer appears at the top of a numeric sort. e1 + A5 lock this in. From a stakeholder lens (newcomers / over-eager pruners) this is the right fix. PASS.
- **Single-consumer dashboard tab (round-2 finding #3) is moot per the public release.** Once dozens of adopters render the tab, "single consumer" disappears as a concern. The spec handles this implicitly by shipping the tab in v1; no further action needed.
- **Hybrid dashboard (data + roster file merge) helps the adopter-with-empty-data stakeholder.** A fresh-clone adopter sees all 28 personas as "(never run)" rows immediately — they understand the system has a roster even before they've run anything. Good UX choice for the public-release cohort.
- **The leakage canary (A10) is well-designed.** Asserting `LEAKAGE_CANARY_DO_NOT_PERSIST_xyz123` does NOT appear in the output JSONL is exactly the right shape of test for "does the privacy contract hold under any input." The added scan for `prompt|body|text|content` field-name patterns in the fixtures dir is a nice belt-and-suspenders.
- **No stakeholder conflict identified between adopters and the original Pro-tier friend.** Public release does not erode the "Pro relief in v1.1" commitment; it slightly strengthens it (more eyes asking "where's that spec?").

## Round-3 vs round-2 stakeholder concerns: shrank

Round 2: 4 important findings (Pro-friend orphaned, persona-author exposure, single-consumer dashboard tab, insufficient-sample sort-surface bug).
Round 3: 4 important findings, but only one (#1, persona-author exposure) is a genuine carryover and even it is partially addressed. #2–#4 are net-new stakeholder cohorts surfaced by the public-release pivot, not regressions. The other three round-2 findings are resolved (Pro-friend in commitment language; single-consumer moot; insufficient-sample fixed properly).

Direction of travel is healthy. None of the round-3 findings rise to blocker.

## Verdict

**PASS WITH NOTES** — all round-2 stakeholder findings are addressed (#2 partially, #1/#3/#4 fully); the new public-release stakeholder cohort is named in Privacy but adopter-consent and persona-author-exposure-via-rendered-output deserve the cheap mitigations listed above before public announcement, not before `/plan`.
