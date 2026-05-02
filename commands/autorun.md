---
description: Run the full pipeline headlessly overnight — spec-review → plan → check → build → PR → merge
---

## Action

**Your only job is to invoke the shell pipeline. Do NOT orchestrate this in-session.**

1. Confirm `queue/<slug>.spec.md` exists in the current project. If not, copy it:
   ```bash
   cp docs/specs/<slug>/spec.md queue/<slug>.spec.md
   ```
2. Run the pipeline in a detached tmux window so it survives session end:
   ```bash
   tmux new-window -n autorun 'autorun start; echo "[autorun] done — press enter"; read'
   ```
   Or to run inline (blocks until complete):
   ```bash
   autorun start
   ```
3. Confirm it started with `autorun status`.

Do NOT read the stage commands (spec-review.md, plan.md, etc.) and simulate them yourself. The entire pipeline is driven by `scripts/autorun/run.sh` via the `autorun` CLI.

---

## Overview

`/autorun` orchestrates the existing 8-command pipeline headlessly while you sleep. It is not a replacement for the interactive workflow — you write specs interactively via `/spec` as usual, then drop the result into `queue/` and let `/autorun` drive everything else. It runs as a local process via launchd or a detached tmux session and exits cleanly on the next morning.

---

## Quick Start

1. **Queue a spec:**
   ```bash
   cp docs/specs/myfeature/spec.md queue/myfeature.spec.md
   ```

2. **Start the run:**
   ```bash
   autorun start
   # or, raw invocation:
   flock -n queue/.autorun.lock bash scripts/autorun/run.sh
   ```

3. **Check progress mid-run:**
   ```bash
   autorun status
   ```

4. **Morning check:**
   ```bash
   cat queue/index.md
   ```

---

## Queue Format

- **File naming:** `queue/<slug>.spec.md`
  - Slug must match `^[a-z0-9][a-z0-9-]{0,63}$`
  - Example: `queue/dark-mode-toggle.spec.md`
- **Contents:** a fully-written `spec.md` (the output of `/spec`) — not a partial draft
- **Multiple items:** processed sequentially, alphabetical order
- **`.prompt.txt` entries are NOT supported in v1** — queue fully-written `spec.md` files only. Phase 2 will add `.prompt.txt` support once `/spec --auto` is built.
- **Idempotent re-runs:** items with `queue/<slug>/run-summary.md` already present are skipped silently

---

## Configuration (`queue/autorun.config.json`)

All fields are optional. Create this file only when you need to override a default.

```json
{
  "webhook_url": "",
  "mail_to": "",
  "spec_review_fatal_threshold": 2,
  "build_max_retries": 3,
  "test_cmd": "",
  "timeout_stage": 1800,
  "timeout_codex": 120
}
```

| Field | Default | Notes |
|-------|---------|-------|
| `webhook_url` | `""` | Slack-compatible webhook; empty = skip |
| `mail_to` | `""` | Email address; empty = skip |
| `spec_review_fatal_threshold` | `2` | How many `Verdict: FAIL` reviewers halt the item |
| `build_max_retries` | `3` | Build wave retry limit before rollback |
| `test_cmd` | `""` | Empty = skip tests (appropriate for repos with no test suite) |
| `timeout_stage` | `1800` | Per-`claude -p` call timeout in seconds |
| `timeout_codex` | `120` | Codex review timeout in seconds |
| `timeout_verify` | `600` | Spec compliance verifier timeout in seconds |

---

## The Pipeline

Each queue item runs through these stages in order:

### Stage 1 — Spec Review (parallel)
- 6 reviewer agents run in parallel against the spec
- Findings merged into `queue/<slug>/review-findings.md`
- **Gate:** ≥ `spec_review_fatal_threshold` (default 2) agents emit `Verdict: FAIL` → item halted, `failure.md` written, next item

### Stage 2 — Risk Analysis (parallel with Stage 1)
- Lightweight risk agent reads spec + review findings
- Output: `queue/<slug>/risk-findings.md`
- Merged into `review-findings.md` before plan stage

### Stage 3 — Plan
- Sequential; receives merged review + risk findings as context
- Output: `queue/<slug>/plan.md`

### Stage 4 — Check
- 5 agents validate the plan
- **Gate:** `NO-GO` verdict → item halted

### Stage 5 — Build + Verify
- Branches from `main`: `autorun/<slug>`
- Pre-build SHA captured to `queue/<slug>/pre-build-sha.txt`
- One wave = one commit produced by the build agent
- Kill-switch checked after each wave
- After each wave: tests run (`test_cmd`), then spec compliance check (`verify.sh`)
  - Verifier checks git diff against spec requirements — "routes load" does NOT satisfy a requirement that specifies UI elements, access gates, or data fields
  - On verify failure: unmet requirements injected into the NEXT attempt's prompt as explicit `[FAIL]` items
- Retry up to `build_max_retries`× on either test or compliance failure
- On exhaustion: `git reset --hard <pre-build-sha>` + `failure.md` written
- Compliance gaps preserved in `queue/<slug>/verify-gaps.md`

### Stage 6 — PR Creation
- `gh pr create --base main --head autorun/<slug>`
- PR body includes full provenance block: spec → review → plan → check → build artifacts

### Stage 7 — Codex Review
- `codex exec review` fires post-PR
- **`**High:**` findings** are blocking — one autonomous fix attempt is made, then tests re-run, then Codex re-run once
- **`**Medium:**` / `**Low:**`** are non-blocking — justification comment posted to PR

### Stage 8 — Squash Merge
- Executes if: 0 `**High:**` findings remain AND tests pass
- `gh pr merge --squash`
- Otherwise PR is left open, findings logged, notification sent

---

## Kill-Switch

```bash
touch queue/STOP     # halts after current build wave
autorun stop         # same via wrapper
```

The run halts cleanly after the current wave completes — no partial commits, no uncommitted state. Remove `queue/STOP` before the next run.

---

## Dry-Run Mode

```bash
AUTORUN_DRY_RUN=1 autorun start
```

Stage scripts write stub artifacts and exit 0 without calling `claude -p`. Use this to test orchestration wiring without API cost.

---

## Testing Retry + Rollback

Force exhaustion of all build retries by setting `test_cmd` to always fail:

```json
{ "test_cmd": "exit 1" }
```

Expected behavior:
1. Wave 1 runs, tests fail → retry 1
2. Retry 2, retry 3 → all fail
3. `git reset --hard <pre-build-sha>` fires
4. `queue/<slug>/failure.md` written
5. Notification sent; pipeline continues to next queue item

---

## Failure Handling

On any stage failure, `/autorun` writes `queue/<slug>/failure.md` and moves to the next item. The file includes:

- Stage that failed, wave number, exit code
- Branch name and pre-build SHA
- Last 50 lines of stderr
- A ready-to-run **re-queue command:**
  ```bash
  rm queue/myfeature/failure.md && cp docs/specs/myfeature/spec.md queue/myfeature.spec.md
  ```

`queue/index.md` is written after all items complete with a per-item summary table (slug | verdict | stage-reached | PR URL or failure path).

---

## Notifications

All channels are optional. The macOS banner fires automatically on macOS without any config.

| Channel | How to enable |
|---------|--------------|
| **macOS banner** | Automatic (`osascript`) — fires on completion or failure |
| **Mail** | Set `mail_to` in `autorun.config.json` |
| **Webhook** | Set `webhook_url` (Slack-compatible) |

Note: macOS notification (AC #6) is manual-verification only — no pipeline stage depends on it. If all channels fail, `queue/run-summary.md` is the fallback forensic artifact.

---

## Scheduling Overnight

### Option 1 — tmux (simplest)
```bash
# Start a detached session that runs the queue and exits
tmux new-session -d -s autorun 'autorun start'
```

### Option 2 — launchd
See `QUICKSTART.md` for a full launchd plist example. Key points:
- Use a LaunchAgent (not LaunchDaemon) so it runs as your user
- `run.sh` sources `~/.zshenv.local` at startup for credentials

---

## Security Notes

- **`AUTORUN_GH_TOKEN`** — keep in `~/.zshenv.local` (chmod 600); use a fine-grained PAT scoped to `autorun/*` branches only (create PR + merge, nothing else)
- **`queue/` is gitignored** — specs, config, and run artifacts never committed
- **`queue/run.log`** — JSON-lines forensic trail written per wave: `{timestamp, slug, stage, exit_code}`
- **Credentials** — `run.sh` sources `~/.zshenv.local` at startup; all subprocesses inherit `ANTHROPIC_API_KEY`, `GH_TOKEN`, and Codex auth

---

## Queue Directory Layout (reference)

```
queue/
  autorun.config.json         # optional config overrides
  STOP                        # kill-switch: touch to halt
  myfeature.spec.md           # queue entry
  index.md                    # written after each full run
  run.log                     # JSON-lines forensic trail
  .autorun.lock               # flock file (auto-managed)
  .current-stage              # human-readable current stage
  myfeature/
    review-findings.md        # merged spec-review + risk output
    risk-findings.md
    plan.md
    check.md
    build-log.md
    pre-build-sha.txt         # written once at Stage 5 entry
    verify-gaps.md            # per-requirement [PASS]/[FAIL] from compliance check
    state.json                # machine-readable run state
    failure.md                # written on rollback (presence = failed)
    pr-url.txt
    run-summary.md            # written on success (presence = complete)
```
