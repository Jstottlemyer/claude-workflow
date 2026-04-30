# Implementation Plan: Autonomous Overnight Pipeline (`/autorun`)

**Created:** 2026-04-29
**Spec:** docs/specs/autonomous-overnight-pipeline/spec.md
**Review:** docs/specs/autonomous-overnight-pipeline/spec-review/review.md

---

## Design Decisions

### 1. Stage Script Calling Convention: Env Block (not positional args)
`run.sh` exports a standard env block before calling each stage script. Stage scripts read env, write to `$ARTIFACT_DIR/`, exit 0/1. This makes each script independently testable with `export SLUG=test && bash spec-review.sh`.

**Env contract** (defined in `defaults.sh`):
```
SLUG               queue item slug (e.g., "myfeature")
QUEUE_DIR          absolute path to queue/ directory
ARTIFACT_DIR       absolute path to queue/<slug>/
SPEC_FILE          absolute path to the .spec.md entry file
CONFIG_FILE        absolute path to autorun.config.json (if exists)
AUTORUN            "1" — signals headless mode to command files
AUTORUN_VERSION    from VERSION file at repo root
```

### 2. Context Handoff: Predecessor-Artifact Convention
Each stage script reads its predecessor's artifact from `$ARTIFACT_DIR/` by convention — no prompt bloat, no file-path args.
- `plan.sh` reads `$ARTIFACT_DIR/review-findings.md`
- `check.sh` reads `$ARTIFACT_DIR/plan.md`
- `build.sh` reads `$ARTIFACT_DIR/check.md`
- Risk analysis output: `$ARTIFACT_DIR/risk-findings.md` (merged with review-findings.md before plan)

### 3. In-Progress Sentinel: `state.json` + `queue/.current-stage`
Two complementary tracking artifacts:
- `$ARTIFACT_DIR/state.json` — machine-readable: `{ "stage": "build", "wave": 2, "pre_build_sha": "abc123", "started_at": "...", "pid": 12345 }`. Atomic write via temp-rename. Only `run.sh` writes it.
- `queue/.current-stage` — human-readable string updated by each stage. `cat queue/.current-stage` from any terminal.

On re-run: if `state.json` has a stale PID (`kill -0 <pid>` fails), write `failure.md` with `"orphaned: stale pid"` and let the retry path handle it.

### 4. Command File Blocking Language: Autonomy Directive (spike-gated)
The spec's autonomy directive is the primary mechanism. The `$AUTORUN=1` env var is also exported so command files can check it. **The spike must verify whether the directive reliably suppresses approval gates** (this is the #1 integration risk). If it fails: add a one-block `$AUTORUN` conditional to `spec-review.md`, `plan.md`, and `build.md` — additive only, interactive path unchanged.

### 5. Rollout Sequence (spike-gated)
```
defaults.sh → notify.sh → spec-review.sh [SPIKE GATE] → plan.sh → check.sh →
risk-analysis.sh → build.sh → run.sh → commands/autorun.md → autorun wrapper
```
The spike (`spec-review.sh`) must pass all 6 behavioral tests before the remaining 7 wrappers are written.

**Spike test checklist:**
1. 6 parallel reviewers dispatched (not serialized)?
2. Autonomy directive suppresses `"Approve to proceed to /plan?"` output?
3. Per-persona raw files written to `docs/specs/<feature>/spec-review/raw/<persona>.md`?
4. `findings.jsonl` emitted with valid schema?
5. `run.json.status: "ok"` (not `"failed"` due to untracked spec)?
6. Subprocess exits 0?

### 6. Scalability Mitigations (all low-effort, all in-scope for v1)
- **Per-call timeout:** `timeout 300 claude -p ...` on every invocation. Prevents hung processes.
- **Codex timeout:** `timeout 120 codex ...` — on non-zero exit, post a warning comment to the PR rather than blocking.
- **Build-log:** Append with wave headers (`## Wave N — YYYY-MM-DDTHH:MM:SSZ`), per-item `build-log.md`.

### 7. Security Hardening (in-scope for v1)
- **gitignore:** `queue/autorun.config.json`, `queue/*/`, `queue/STOP`, `queue/run.log`, `queue/.current-stage` — these are all transient/sensitive. Queue entry files (`*.spec.md`, `*.prompt.txt`) are gitignored too (queue is ephemeral).
- **AUTORUN_GH_TOKEN:** Separate fine-grained PAT for autorun, scoped to write `autorun/*` branches + create/merge PRs. Documented in setup instructions.
- **`$TMPDIR` not `/tmp`:** For Codex output file.
- **`--system` flag:** Spike tests whether `claude -p` supports `--system` for separating the autonomy directive from user-controlled spec content. If yes, use it.
- **Structured run log:** `queue/run.log` (gitignored) — JSON lines per wave: `{timestamp, slug, stage, exit_code}`. Forensic trail for post-mortem.

### 8. `autorun` Wrapper Script
A `scripts/autorun/autorun` wrapper script exposes `autorun start|stop|status`. Added to install.sh. This replaces the raw `flock -n queue/.autorun.lock bash scripts/autorun/run.sh` invocation as the user-facing command.
- `autorun start` — runs with flock, exits with clear message if already running
- `autorun stop` — writes `queue/STOP`, prints "Run will halt after the current build wave. Remove queue/STOP before next run."
- `autorun status` — cats `queue/.current-stage` + last 5 lines of `queue/run.log`

### 9. `queue/index.md` — Morning Artifact
Written by `run.sh` at end of each run (full queue processed). Columns: slug | verdict | stage-reached | PR URL or failure path. One line per item. This is the morning check before reading individual `failure.md` files.

### 10. `failure.md` Schema
Structured, machine-parseable template:
```
<!-- autorun:stage=build slug=myfeature wave=2 exit_code=1 -->
# Failure: myfeature

**Stage:** build (wave 2 of 3)
**Branch:** autorun/myfeature
**Pre-build SHA:** abc123def
**Retry count:** 3 of 3
**Timestamp:** 2026-04-29T03:14:00Z

## Error
<last 50 lines of claude -p stderr>

## Re-queue
rm queue/myfeature/failure.md && cp docs/specs/myfeature/spec.md queue/myfeature.spec.md
```

### 12. Codex Fix-Attempt Mechanics (task 10c contract)
When Codex reports `**High:**` blocking findings post-PR, `run.sh` executes one fix attempt:
1. Call `claude -p "<autonomy-directive> Fix the failing issue. Context: $(cat $ARTIFACT_DIR/build-log.md) Codex findings: $(cat $TMPDIR/codex-autorun-review.txt)"` — must produce exactly one commit on `autorun/<slug>`.
2. If `claude -p` exits non-zero or no new commit is produced: write `failure.md`, halt, do NOT retry.
3. Re-run `test_cmd`. If tests pass, re-run Codex review once more.
4. If tests still fail or Codex still reports `**High:**`: close PR (`gh pr close`), delete remote branch, write `failure.md`, notify, move to next item.
5. Cap: one fix attempt per queue item total (not per finding).

### 11. PR Provenance Block Fields
Written by `run.sh` in the `gh pr create --body`:
```
## Autorun Provenance
- **Slug:** myfeature
- **Spec:** docs/specs/myfeature/spec.md
- **Pre-build SHA:** abc123def
- **Autorun version:** 0.3.0
- **Wave count:** 3
- **Test cmd:** (empty — skipped)
- **Timestamp (UTC):** 2026-04-29T03:00:00Z
- **Artifacts:** queue/myfeature/{review-findings,plan,check,build-log}.md
```

---

## Implementation Tasks

| # | Task | File(s) | Depends On | Size | Parallel? |
|---|------|---------|-----------|------|-----------|
| 1 | `defaults.sh` — env contract + all config defaults | `scripts/autorun/defaults.sh` | — | S | — |
| 2 | install.sh subdirectory loop + queue gitignore | `install.sh`, `queue/.gitignore` | — | S | with 1 |
| 3 | `notify.sh` — mail + osascript + webhook; reads failure.md/run-summary.md | `scripts/autorun/notify.sh` | 9 | S | with 10a |
| 4 | `spec-review.sh` spike — confirm behavioral contract (6 tests) | `scripts/autorun/spec-review.sh` | 1 | M | — |
| 5 | Evaluate spike results; if approval gate not suppressed, add `$AUTORUN` guards to command files | `commands/spec-review.md`, `commands/plan.md`, `commands/build.md` | 4 | S | — |
| 6 | `risk-analysis.sh` — inline risk-analysis prompt | `scripts/autorun/risk-analysis.sh` | 5 | S | — |
| 7 | `plan.sh` — reads merged review-findings.md (after risk merge) | `scripts/autorun/plan.sh` | 6 | S | — |
| 8 | `check.sh` — reads plan.md | `scripts/autorun/check.sh` | 7 | S | — |
| 9 | `build.sh` — wave runner: pre-build-sha.txt (write-once), STOP check, test_cmd, timeout 300, retry×3, rollback + remote cleanup, state.json updates, build-log append. **Done-criteria:** (a) `test_cmd="exit 1"` triggers 3 retry entries in build-log.md, then git reset --hard fires and failure.md written; (b) `touch queue/STOP` mid-wave: after current wave, git status clean, state.json.stage matches last completed wave, no uncommitted files, STOP file still present; (c) on rollback, pre-build-sha.txt unchanged by retries 2+3; (d) remote cleanup on final failure: gh pr close + git push origin --delete autorun/<slug> | `scripts/autorun/build.sh` | 2,5 | L | — |
| 10a | `run.sh` core — flock, queue loop, orphan cleanup (delete stale remote branch before Stage 1 re-entry), AUTORUN_DRY_RUN stub mode, state.json writes, parallel spec-review + risk dispatch, stage sequencing with context handoff | `scripts/autorun/run.sh` | 6,7,8,9 | M | — |
| 10b | `run.sh` PR — `gh pr create` with provenance block (Design Decision #11 fields) | `scripts/autorun/run.sh` | 10a | S | — |
| 10c | `run.sh` Codex — Codex review invocation (timeout 120), **High:** parsing, fix-attempt mechanics (Design Decision #12), squash merge gate | `scripts/autorun/run.sh` | 10b | S | — |
| 11 | `autorun` wrapper — start/stop/status (optional, post-AC #1) | `scripts/autorun/autorun` | 10a | S | with 12 |
| 12 | `commands/autorun.md` — reference card | `commands/autorun.md` | 11 | S | with 11 |

**Total: 14 tasks (10 split into 10a/10b/10c). Critical path: 1→4→5→6→7→8→9→10a→10b→10c. notify.sh (3) runs parallel with 10a after 9.**

---

## Open Questions

1. **Does `claude -p` support `--system` flag?** — spike test item 6. If yes, use it for security boundary. Run `claude --help` before writing any wrapper.

2. **Does `claude -p` dispatch Agent-tool parallelism in headless mode?** — spike test item 1. If no, the 6 spec-reviewers are sequential (~12 min vs ~2 min). Acceptable (still overnight), but the spec's "parallel" claim is wrong.

3. **Does Codex review block or poll?** — affects `timeout 120 codex ...` value. If it's long-running, 120s may be too short. Check `codex review --help` and test before hard-coding.

4. **`/spec --auto` flag — AC #7 formally deferred to Phase 2.** AC #7 (`.prompt.txt` queue entries trigger `/spec --auto` first) requires `/spec --auto` which does not exist in v1. The `.prompt.txt` path is descoped from v1. The `.spec.md` path is the primary and only v1 flow. Note in `commands/autorun.md`: "`.prompt.txt` entries are not supported in v1 — drop a fully-written `spec.md` into the queue instead. Phase 2 will add `.prompt.txt` support once `/spec --auto` is built."

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Approval gate not suppressed by directive | Medium | High — pipeline stalls headless | Spike test item 2; `$AUTORUN` env var escalation ready |
| `claude -p` parallelism is sequential | Medium | Low — 6× slower spec-review; overnight window still works | Spike test item 1; update time estimates if sequential |
| 429 rate-limit on 7 concurrent processes | Low-Medium | Medium — threshold gate misfire | Accepted risk; `notify.sh` logs 429 occurrences post-hoc |
| Codex CLI timing unknown | Medium | Low — timeout+warn fallback mitigates | `timeout 120` + skip-with-warning path |
| Bad wave auto-merges to main | Very Low | Very High — accepted design risk | Documented accepted risk; structured run log for forensics |
| `/spec --auto` missing for `.prompt.txt` path | High | Low — only AC #7 affected; spec.md path works | Note in autorun.md; defer .prompt.txt support until --auto built |

---

## Files Created/Modified

**New:**
- `queue/` directory (with `.gitignore`)
- `queue/autorun.config.json.example`
- `scripts/autorun/defaults.sh`
- `scripts/autorun/notify.sh`
- `scripts/autorun/spec-review.sh`
- `scripts/autorun/risk-analysis.sh`
- `scripts/autorun/plan.sh`
- `scripts/autorun/check.sh`
- `scripts/autorun/build.sh`
- `scripts/autorun/run.sh`
- `scripts/autorun/autorun` (wrapper)
- `commands/autorun.md`

**Modified (if spike fails):**
- `commands/spec-review.md` — add `$AUTORUN` guard around approval gate
- `commands/plan.md` — add `$AUTORUN` guard around approval gate
- `commands/build.md` — add `$AUTORUN` guards around wave-launch and pace prompts
- `install.sh` — add `scripts/autorun/` subdirectory loop + queue gitignore block

**Always modified:**
- `install.sh` — add `scripts/autorun/` subdirectory loop (regardless of spike result)
