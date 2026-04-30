# Review: Autonomous Overnight Pipeline (`/autorun`)

**Date:** 2026-04-29
**Spec:** docs/specs/autonomous-overnight-pipeline/spec.md
**Reviewers:** requirements, gaps, ambiguity, feasibility, scope, stakeholders
**Codex:** no additional findings (empty output)

---

## Spec Strengths

- **Queue state machine is clean.** No dir = pending, `run-summary.md` = complete, `failure.md` = failed. Implementation-ready with one addition (in-progress state).
- **Out-of-scope list is effective.** Cost ceiling, remote CCR, persona tiering — explicitly cut. Natural Phase 2 seams are well-identified.
- **Kill-switch design is elegant.** `queue/STOP` file between waves is simple, reliable, and the right scope for local-only execution.

---

## Before You Build (10 items)

These must be answered before `/plan` can start. Each is a decision gate — implementation diverges depending on the answer.

### 1. What is a "build wave"?
*Flagged by: Requirements, Ambiguity, Feasibility, Scope — highest convergence.*
"Wave-by-wave" appears throughout Stage 4, but wave boundaries, size, count, and ordering are never defined. `scripts/autorun/build.sh` cannot be written without this. **Answer: what is one wave? Is it one file? One commit? A group of related changes decided by the build agent?**

### 2. How are tests run, and what counts as "passing"?
*Flagged by: Requirements, Gaps, Ambiguity, Scope.*
"Tests pass" gates auto-merge (AC #3) and 3-retry rollback (AC #5). No test runner, invocation command, exit-code contract, or handling for "no test suite" is defined. **Answer: which test runner, what command, what exit code = pass, what to do when the repo has no tests?**

### 3. How is the pre-build SHA captured and stored?
*Flagged by: Requirements, Gaps, Ambiguity, Scope.*
`git reset --hard to pre-build SHA` appears as the rollback mechanism, but the data model has no field for this SHA and the scripts have no contract for capturing it. **Answer: capture SHA at the start of Stage 4 and store in `queue/<slug>/pre-build-sha.txt`? Define the capture point and storage.**

### 4. What does "fatal" mean for the spec-review threshold gate?
*Flagged by: Ambiguity, Scope, Stakeholders.*
`spec_review_fatal_threshold: 2` is configurable, but "fatal" has no definition. Two engineers will parse this differently. **Answer: define "fatal" — is it a severity label the reviewer must emit (e.g., a `FATAL:` prefix in output)? A regex? A verdict word?**

### 5. How are Codex findings classified as blocking vs. non-blocking?
*Flagged by: Requirements, Ambiguity, Scope.*
This classification gates auto-merge. If delegated to Codex's own uncontrolled output format, the gate is fragile. **Answer: does Codex `review` output a structured severity field, or does the orchestrator parse for keywords? What's the parsing contract?** (Note: the correct Codex command is `codex review [PROMPT]`, not `codex exec --full-auto`.)

### 6. What is the `claude -p` invocation model?
*Flagged by: Feasibility — unique but architectural.*
The spec shows `claude -p "$(cat scripts/autorun/run.sh)"` — but a shell script is not a prompt. Additionally, whether `claude -p` faithfully executes slash command markdown (with correct tool permissions, MCP servers, and file access scope) is unverified. **Answer: run a spike — can `claude -p "$(cat commands/spec-review.md)"` be passed the spec file content and produce usable review output? This determines whether the wrapper-script architecture is valid.**

### 7. How are credentials available to the launchd process?
*Flagged by: Gaps — unique but first-run blocking.*
`gh`, `claude`, and Codex all require auth tokens. A launchd job runs in a minimal environment with no `.zshrc`, no keychain auto-unlock, no `SSH_AUTH_SOCK`. The first overnight run will silently fail without explicit credential wiring. **Answer: specify how each credential is made available — env file sourced by launchd plist, keychain entry, or token file path.**

### 8. What branch does each queue item run on?
*Flagged by: Gaps, Scope, Stakeholders.*
`/build` writes code, but the spec never says: who creates the feature branch, what's it named, what happens if two queue items touch the same files, and what branch does `gh pr create` target. **Answer: define branch naming convention (e.g., `autorun/<slug>`), creation point (start of Stage 4), and PR target (main or a designated integration branch).**

### 9. Concurrent invocation protection
*Flagged by: Gaps — unique but data-corruption risk.*
Nothing prevents two `/autorun` invocations against the same queue simultaneously (two terminal sessions, two launchd firings). The result is competing git operations and corrupted artifacts. **Answer: write a PID file to `queue/.autorun.lock` at run start; fail fast if it already exists.**

### 10. `claude -p` parallel API rate limits
*Flagged by: Feasibility.*
7 concurrent `claude -p` processes (6 spec-reviewers + risk-analysis) with no rate-limit handling. API per-minute token limits may produce silent partial outputs that the threshold gate misreads. **Answer: either run reviewers sequentially or add a semaphore / back-off; document which.**

---

## Should Address (non-blocking)

These can be resolved during `/plan` or implementation, but leaving them open will produce inconsistent output across queue items.

1. **PR provenance block format** *(4 agents)* — define required fields: spec path, queue item slug, review/plan/check artifact links, retry count, Codex finding hashes. AC #1 asserts a "provenance block" with no template.

2. **Stage 2 context handoff** — "plan sees Stage 1 findings as context" is undefined. Is `review-findings.md` appended to the plan prompt? Passed via file path argument? The plan wrapper script needs a contract.

3. **osascript GUI session requirement** — `osascript` fails silently in a locked-screen or LaunchDaemon context. Document this as a known limitation: overnight desktop banner is best-effort; `run-summary.md` is the reliable artifact.

4. **"One autonomous fix attempt" exit condition** — if the fix generates a new blocking finding, the spec says halt. But the autonomy directive says "make the call." Document explicitly: the spec's halt rule wins over the directive for fix-loop exit. No infinite loop.

5. **Queue item identity / name collision** — if `myfeature.spec.md` and `myfeature.prompt.txt` both exist, define behavior: treat as two items or error. Define what happens when the same slug is queued after a prior failed run.

6. **`/spec --auto` flag is an undeclared dependency** — AC #7 requires this flag but it doesn't exist in the current `/spec` command. Building `/autorun` before building `--auto` mode creates a broken AC. Sequence the work or defer AC #7 to Phase 2.

7. **PR creation before Codex review** — Stage 5 (PR open) runs before Stage 6 (Codex review). A failed fix attempt leaves an open broken PR. Consider: run Codex review before `gh pr create`, open the PR only on clean pass.

8. **`autorun.config.json` gitignore** — the config may contain `webhook_url` and `mail_to` (sensitive). Define whether it should be gitignored (recommend: yes, add to `.gitignore` on first run).

9. **Partial queue failure recovery** — if the orchestrator process crashes mid-item, neither `run-summary.md` nor `failure.md` exists. A re-run will start the item from Stage 1, potentially with an orphaned branch or open PR. Document the manual cleanup procedure.

10. **Notification event triggers** — "notification fires on completion" is defined (AC #6), but what about per-item failure vs. per-run completion vs. halt-on-threshold? Define which events trigger `notify.sh`.

---

## Watch List

- **Autonomy directive vs. existing command files** — commands like `build.md` may contain language like "confirm before committing" that stalls headless runs. Audit each command file for human-in-loop language before wrapping.
- **"No human gate before auto-merge" is an accepted risk** — user explicitly chose autonomous operation. Accepted. Worth documenting in spec's Out of Scope: "No human approval gate before merge — by design."
- **Codex crash = clean pass** — a Codex process that exits 0 with empty output looks identical to a clean review. Distinguish: empty output = "Codex: no findings" is fine; non-zero exit or parse error = treat as "Codex unavailable, skip Stage 6 and notify."

---

## Reviewer Verdicts

| Dimension | Verdict | Key Finding |
|-----------|---------|-------------|
| Requirements | **FAIL** | Test suite, build waves, and Codex trigger mechanism are all undefined |
| Gaps | **FAIL** | Credential handling and branch strategy would corrupt state on first run |
| Ambiguity | **FAIL** | "Fatal," "wave," and "blocking" are undefined decision gates |
| Feasibility | **FAIL** | `claude -p` invocation model is architecturally inverted; needs spike |
| Scope | **FAIL** | Rollback mechanism, merge target, and "fatal" severity all undefined |
| Stakeholders | **PASS WITH NOTES** | Stakeholder surface is small; auto-merge risk is accepted by design |

---

## Conflicts Resolved

- **"No human gate" (Stakeholders flagged as critical gap vs. user intent)** → Demoted to accepted risk. User explicitly chose autonomous operation in Q&A. Document as "by design" in spec, not a gap to fill.
- **Stakeholders PASS vs. 5 others FAIL** → FAIL overall. The PASS was on the narrow stakeholder dimension; the five FAILs are on foundational spec completeness.
- **Codex `exec --full-auto` (spec-review workflow referenced this flag)** → Does not exist. Correct command verified: `codex review [PROMPT]`. This is a spec-review workflow bug, not an `/autorun` spec bug — but the spec's Stage 6 invocation method is affected.

---

## Consolidated Verdict

**1 of 6 agents passed. FAIL.**

The spec has strong structural bones (state machine, queue layout, kill-switch, out-of-scope list) but 10 undefined terms that are load-bearing decision gates. "Wave," "fatal," "blocking/non-blocking," "pre-build SHA," and "tests pass" must all be defined before implementation can start — these aren't edge cases, they're the core of Stage 4's control flow. Additionally, the `claude -p` invocation model needs a spike to confirm feasibility before building the wrapper-script architecture.

**Recommended action:** Revise the spec to address all 10 Before-You-Build items, then re-run `/spec-review` or proceed directly to `/plan` with the revised spec.

---

## Accepted Risks (documented)

- No cost ceiling — explicit user decision
- No human gate before auto-merge — explicit user decision ("go big")
- macOS-only notifications — local-only scope, documented constraint
