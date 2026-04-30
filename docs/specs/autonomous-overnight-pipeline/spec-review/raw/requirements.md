### Critical Gaps

**1. "Tests pass" is undefined.**
Acceptance criteria 3, 4, and 5 all gate on "passing tests," but the spec never defines what test suite runs, how it is invoked, or what the pass threshold is. A builder cannot implement the test-execution step without this.

**2. No definition of a "build wave."**
The orchestrator loops "wave-by-wave," but wave boundaries, size, and ordering are never defined. Without this, `scripts/autorun/build.sh` cannot be written.

**3. Codex review trigger mechanism is unspecified.**
Stage 6 says "trigger Codex review" but gives no invocation method — no CLI command, no API call, no polling mechanism for results. This is a required integration point with no implementation path.

**4. `gh pr merge --squash` authorization is unspecified.**
Nothing defines what branch protection rules, required reviewers, or CI status checks must be satisfied before the merge is attempted. If the repo has required checks, the merge will silently fail.

**5. The autonomy directive creates a conflict with Codex's "one fix attempt" rule.**
The directive says "make the call." The spec also says "one autonomous fix attempt" and then halts. Those rules can conflict — if the autonomous fix attempt produces a new blocking finding, does the directive tell the agent to try again, or does the spec's halt rule win? No tiebreaker is stated.

**6. `git reset --hard` scope is undefined.**
"Pre-build SHA" is mentioned but never stored or named. The orchestrator must capture and persist this SHA before build starts. The mechanism for doing so is absent from the data model and from `build.sh`'s contract.

---

### Important Considerations

**A. No cost ceiling accepted risk not documented.**
A large queue with retries and 6 parallel review agents could run 50+ `claude -p` invocations overnight. Even noting "no ceiling" as accepted risk would help operators set expectations.

**B. `queue/STOP` checked after each wave — "clean" state needs clarification.**
If a wave is long-running, "clean branch state" on STOP may not be as clean as intended.

**C. Failure state machine is incomplete.**
`failure.md` present → "failed (re-run will retry unless removed)" — but nowhere is it stated what happens if a re-run item has `failure.md` but no `run-summary.md`. Does the orchestrator retry from Stage 1 or resume from the failed stage?

**D. Notification fallback ordering is ambiguous.**
"macOS `mail` (via Concierge plugin) + `osascript`" — does both fire always, or is one primary and the other fallback?

**E. `/spec --auto` confidence threshold is referenced but not defined.**
The edge case table mentions "confidence < threshold" but `autorun.config.json` has no `spec_confidence_threshold` field.

**F. PR provenance block format is unspecified.**
Acceptance criterion 1 requires a "provenance block" in the PR body. No template or required fields are given.

**G. Parallel spec-review agent coordination is unspecified.**
Six agents run in parallel, findings are "merged," then the threshold gate fires. No merge strategy (concatenate, deduplicate, severity-roll-up) is defined.

---

### Observations

- The state machine table is clean and implementation-friendly; it just needs the failure/retry resume path added.
- `autorun.config.json` is a good pattern; consider adding `spec_confidence_threshold` and a `notify_priority` field.
- The kill-switch via filesystem touch is simple and reliable.
- Acceptance criteria are binary and verifiable, which is good; they just depend on undefined sub-concepts (waves, test suite).

---

### Verdict

**FAIL** — Three critical gaps (undefined test suite, undefined build waves, unspecified Codex trigger mechanism) mean a builder cannot implement the three most complex components from this spec alone.
