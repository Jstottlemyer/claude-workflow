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
- **Call counter:** `max_api_calls` config field (default: 200). Counter file incremented per `claude -p` call. Halt if exceeded — protects against runaway overnight cost.
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
| 3 | `notify.sh` — mail + osascript + webhook; reads failure.md/run-summary.md | `scripts/autorun/notify.sh` | 1 | S | with 2 |
| 4 | `spec-review.sh` spike — confirm behavioral contract (6 tests) | `scripts/autorun/spec-review.sh` | 1 | M | — |
| 5 | Evaluate spike results; if approval gate not suppressed, add `$AUTORUN` guards to command files | `commands/spec-review.md`, `commands/plan.md`, `commands/build.md` | 4 | S | — |
| 6 | `risk-analysis.sh` — inline risk-analysis prompt, parallel to spec-review | `scripts/autorun/risk-analysis.sh` | 5 | S | with 7 |
| 7 | `plan.sh` — reads review-findings.md, calls plan command | `scripts/autorun/plan.sh` | 5 | S | with 6 |
| 8 | `check.sh` — reads plan.md, calls check command | `scripts/autorun/check.sh` | 7 | S | — |
| 9 | `build.sh` — wave runner: pre-build-sha.txt, STOP check, test_cmd, timeout, retry×3, rollback, state.json updates, build-log append | `scripts/autorun/build.sh` | 5 | L | — |
| 10 | `run.sh` — orchestrator: flock, queue loop, state.json, call counter, parallel spec-review, stage sequencing, PR creation with provenance, Codex review + parse, fix attempt, merge, queue/index.md, notify | `scripts/autorun/run.sh` | 6,7,8,9 | L | — |
| 11 | `autorun` wrapper — start/stop/status | `scripts/autorun/autorun` | 10 | S | — |
| 12 | `commands/autorun.md` — reference card slash command | `commands/autorun.md` | 11 | S | with 11 |

**Total: 12 tasks — 3 small solo, 5 small parallel pairs, 2 large sequential, 2 small final**

---

## Open Questions

1. **Does `claude -p` support `--system` flag?** — spike test item 6. If yes, use it for security boundary. Run `claude --help` before writing any wrapper.

2. **Does `claude -p` dispatch Agent-tool parallelism in headless mode?** — spike test item 1. If no, the 6 spec-reviewers are sequential (~12 min vs ~2 min). Acceptable (still overnight), but the spec's "parallel" claim is wrong.

3. **Does Codex review block or poll?** — affects `timeout 120 codex ...` value. If it's long-running, 120s may be too short. Check `codex review --help` and test before hard-coding.

4. **`/spec --auto` flag: hard dependency or deferred?** — AC #7 depends on it. Decision before implementation: either gate AC #7 as "requires /spec --auto to be built first" or defer AC #7 to Phase 2. Recommend: note in `commands/autorun.md` that `.prompt.txt` entries require `/spec --auto` to exist; leave the `.spec.md` path as the primary v1 flow.

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
