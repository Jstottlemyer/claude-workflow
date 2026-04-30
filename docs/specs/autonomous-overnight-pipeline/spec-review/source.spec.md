# Autonomous Overnight Pipeline (`/autorun`) Spec

**Created:** 2026-04-29
**Constitution:** none — session roster only (27 defaults)

## Confidence

| Dimension | Score |
|-----------|-------|
| Scope | 0.92 |
| UX/Flow | 0.90 |
| Data | 0.85 |
| Integration | 0.90 |
| Edge cases | 0.90 |
| Acceptance | 0.92 |
| **Overall** | **0.90** |

---

## Backlog Routing

| Item | Decision |
|------|---------|
| "Fully Autonomous Spec-to-Ship" (wrap V2 spec backlog) | In scope — this IS the spec |
| Persona tiering rules (persona-metrics deferred) | Stays in persona-metrics spec |
| pipeline-wiki open questions | Stays in pipeline-wiki-integration spec |
| Stale wrap V2 plan | Dropped (work complete) |

---

## Summary

`/autorun` is a new command that orchestrates the existing 8-command pipeline headlessly — it does **not** replace the interactive workflow. You write specs interactively via `/spec` as usual, drop the result into `queue/`, and `/autorun` drives spec-review → plan → check → build → PR → Codex review → auto-merge while you sleep. It runs as a local `claude -p` process via launchd or tmux.

---

## Scope

**In scope:**
- New `/autorun` command + `scripts/autorun/` wrapper scripts per stage
- `queue/` directory: accepts spec.md files (starts at spec-review) OR raw text prompts (runs `/spec --auto` first)
- Parallel spec-review (6 agents) + risk-analysis agent, then sequential plan → check → build
- Build wave-by-wave with up to 3 retries before rollback
- `queue/STOP` kill-switch checked between every build wave
- PR opened with full provenance (spec → review → plan → check → build artifacts linked)
- Codex review triggered post-PR; blocking findings get one autonomous fix attempt + re-test; non-blocking get justification comment posted
- Squash merge when: tests pass + 0 Codex blocking findings remain
- Notifications: macOS `mail` (via Concierge plugin) + `osascript` desktop banner; falls back to `queue/run-summary.md`
- Autonomy directive injected into every sub-agent invocation
- Spec-review threshold gate: halt if ≥2 of 6 reviewers flag fatal
- Failure artifact written to `queue/<slug>/failure.md` on rollback
- Idempotent re-runs: items with `run-summary.md` present are skipped

**Out of scope:**
- Cost ceiling
- Remote CCR execution (local only)
- Replacing or modifying existing interactive pipeline commands
- Auto-tiering persona roster

---

## Approach

**Wrapper-script orchestrator** (`scripts/autorun/`): a thin shell layer that assembles prompts, invokes `claude -p`, checks the kill-switch, handles retries, and logs artifacts. The existing markdown command files (`commands/spec-review.md`, `commands/plan.md`, `commands/check.md`, `commands/build.md`) are read verbatim and prepended with the autonomy directive. Each stage = one `claude -p` subprocess. The orchestrator (`scripts/autorun/run.sh`) loops over queue entries, drives stages sequentially (with parallel spec-review + risk-analysis as the exception), writes results to `queue/<slug>/`.

Chosen over a single long-running session (too hard to kill cleanly) and over prompt-injection-only (wrapper scripts are independently testable per stage).

---

## Autonomy Directive

Prepended to every `claude -p` invocation:

> "You are running in fully autonomous overnight mode. At every decision point, pick the safest reversible option and execute. If you find yourself about to write 'Should I', 'Do you want', 'Which approach', 'Before I proceed' — stop. Delete the sentence. Make the call. Log your reasoning in the end-of-run summary."

---

## UX / User Flow

1. **Queue a spec:** `cp docs/specs/myfeature/spec.md queue/myfeature.spec.md`
   — or a raw prompt: `echo "Add dark mode toggle to settings" > queue/dark-mode.prompt.txt`
2. **Start the run:** `claude -p "$(cat scripts/autorun/run.sh)"` — or via launchd schedule
3. `/autorun` loops over `queue/` entries in alphabetical order:
   - Skips items with `queue/<slug>/run-summary.md` (already complete)
   - Detects entry type: `.spec.md` → start at spec-review; `.prompt.txt` → run `/spec --auto` first
   - **Stage 1:** parallel spec-review (6 agents) + risk-analysis agent → merge findings → threshold gate (≥2 fatal → halt + notify + next item)
   - **Stage 2:** plan (sequential, receives stage 1 findings as context)
   - **Stage 3:** check (gates stage 4)
   - **Stage 4:** build waves → per wave: check kill-switch → execute wave → run tests → on fail: retry up to 3× → on 3rd fail: `git reset --hard` to pre-build SHA + write `failure.md` + notify + next item
   - **Stage 5:** `gh pr create` with provenance block in body (links to all stage artifacts)
   - **Stage 6:** trigger Codex review; parse findings by severity → blocking: one autonomous fix attempt + re-test; non-blocking: post justification comment on PR
   - **Stage 7:** if 0 blocking findings + tests pass → `gh pr merge --squash`; else halt + notify
4. After all items: write `queue/run-summary.md`, send notification (mail + desktop banner)

---

## Data & State

### Queue directory layout

```
queue/
  autorun.config.json         # optional config
  STOP                        # kill-switch: touch to halt after current wave
  myfeature.spec.md           # queue entry (already-written spec, starts at spec-review)
  dark-mode.prompt.txt        # queue entry (raw prompt, runs /spec --auto first)
  myfeature/                  # created per item during run
    review-findings.md        # merged spec-review + risk-analysis output
    risk-findings.md
    plan.md
    check.md
    build-log.md
    failure.md                # written on rollback; presence = failed
    pr-url.txt
    run-summary.md            # written on success; presence = complete
```

### `autorun.config.json` schema

```json
{
  "webhook_url": "https://hooks.slack.com/...",
  "mail_to": "user@example.com",
  "spec_review_fatal_threshold": 2,
  "build_max_retries": 3
}
```

All fields optional. Defaults live in `scripts/autorun/defaults.sh`.

### Queue entry state machine

- No `queue/<slug>/` dir → pending
- `run-summary.md` present → complete (skipped on re-run)
- `failure.md` present → failed (re-run will retry unless removed)

---

## Integration

**Existing commands — untouched:**
- `commands/spec-review.md`, `commands/plan.md`, `commands/check.md`, `commands/build.md`

**New files:**

| File | Purpose |
|------|---------|
| `commands/autorun.md` | Slash command entry point; documents queue format and how to start a run |
| `scripts/autorun/defaults.sh` | Default config values |
| `scripts/autorun/run.sh` | Orchestrator loop over queue entries |
| `scripts/autorun/spec-review.sh` | Assembles spec-review prompt + autonomy directive, invokes `claude -p` |
| `scripts/autorun/risk-analysis.sh` | Lightweight risk agent (inline prompt, not a named persona) |
| `scripts/autorun/plan.sh` | Plan stage wrapper |
| `scripts/autorun/check.sh` | Check stage wrapper |
| `scripts/autorun/build.sh` | Wave runner with kill-switch check, retry, and rollback |
| `scripts/autorun/notify.sh` | mail + osascript + optional webhook |

**External dependencies:**
- `gh` CLI — PR creation, merge, Codex review trigger
- `claude` CLI — headless `claude -p` invocations
- Concierge plugin — `mail` delivery
- `osascript` — macOS desktop notifications

---

## Edge Cases

| Scenario | Handling |
|----------|---------|
| ≥2 of 6 spec-review agents flag fatal | Halt item, write `review-findings.md`, notify, move to next item |
| Build wave fails 3× | `git reset --hard` to pre-build SHA, write `failure.md`, notify, next item |
| `queue/STOP` touched mid-run | Checked after each wave; run halts after current wave completes (clean state) |
| Raw prompt → `/spec --auto` confidence < threshold | Spec written with Open Questions flagged; pipeline continues in autonomy mode |
| Codex blocking finding not fixable after 1 attempt | PR left open, findings logged, notify — no merge |
| Notification fails (mail/webhook) | Write `queue/run-summary.md` as fallback; continue without halting |
| Queue empty | Exit 0, no notification |
| Machine loses power mid-run | `queue/<slug>/` artifacts survive; re-run skips completed items, retries failed ones |
| Item already has `run-summary.md` | Skipped silently (idempotent re-run) |

---

## Acceptance Criteria

1. Drop a real (small) `spec.md` into `queue/`; run `/autorun` manually; the full pipeline completes — spec-review + risk-analysis in parallel, plan + check sequentially, build wave-by-wave, PR opened on GitHub with provenance block.
2. Codex review fires post-PR; findings appear as PR comments categorized blocking/non-blocking.
3. With 0 blocking findings and passing tests: `gh pr merge --squash` executes and PR closes.
4. Touch `queue/STOP` during a build wave; the current wave completes then the run halts with a clean branch state.
5. Force a test failure; verify 3 retries fire, then `git reset --hard` to pre-build SHA, `failure.md` written, notification sent.
6. Notification (macOS banner and/or mail) fires on run completion.
7. A `.prompt.txt` queue entry triggers `/spec --auto` first, then continues the full pipeline.

---

## Open Questions

None — all dimensions resolved at ≥0.85.

---

## Roster Changes

No roster changes. 27 default personas cover this domain. The risk-analysis agent is a lightweight inline prompt defined in `scripts/autorun/risk-analysis.sh`, not a named persona file.
