### Key Considerations

**File-based state machine gaps**
The three states (pending / complete / failed) leave no in-progress sentinel. A crashed run leaves a slug directory with partial artifacts but neither `run-summary.md` nor `failure.md`. On re-run, the orchestrator has no way to distinguish "never started" from "died mid-stage 3."

**Artifact content contracts are undefined**
The spec names files but does not say what structured content each must contain. Downstream stages consuming `review-findings.md` or `check.md` need predictable delimiters or schema.

**`build-log.md` overwrite vs append**
Multiple retry waves each produce build output. If the orchestrator overwrites on each attempt, the post-mortem record is lost. If it appends without clear delimiters, log analysis becomes brittle.

**Dual-slug collision**
`myfeature.spec.md` and `myfeature.prompt.txt` both resolve to slug `myfeature`, pointing at the same output directory. The spec is silent on resolution order and conflict behavior.

**Config validation boundary**
`autorun.config.json` is optional and schema-free. If `webhook_url` is malformed or `build_max_retries` is 0, the orchestrator discovers failures late.

**`pre-build-sha.txt` race window**
SHA is captured at Stage 4 entry. `flock` prevents concurrent autorun invocations, but does not address interleaved commits from unrelated tooling.

---

### Options Explored

**A. In-progress sentinel: `running.pid`**
Write `<pid>` to `queue/<slug>/running.pid` at item start; remove on clean exit.
- Pro: trivial to detect orphaned state on re-run; PID allows stale-lock detection (`kill -0 <pid>`).
- Con: PID files are unreliable across machine reboots (PIDs recycle). Requires cleanup logic.
- Effort: low.

**B. In-progress sentinel: `stage.txt` (current stage name)**
Write current stage name on entry, update on each transition.
- Pro: richer diagnostics; crash stage is immediately visible.
- Effort: low-medium.

**C. Structured artifact headers (YAML front matter)**
Each artifact file begins with a YAML block.
- Pro: machine-parseable without external index.
- Con: all `claude -p` prompts consuming these files must be told to skip the header.
- Effort: medium.

**D. Sidecar JSON index per slug (`queue/<slug>/state.json`)**
Single JSON file holds all mutable state: current stage, wave count, timestamps, SHA, status.
- Pro: single source of truth; easy to `jq`; atomic writes with temp-file rename.
- Con: introduces a second state layer alongside the file-presence conventions.
- Effort: medium.

**E. Build-log append with wave headers**
`build-log.md` appends; each retry prefixed with `## Wave N — <timestamp>`.
- Pro: full history preserved; trivial to implement with `>>`.
- Effort: trivial.

**F. Slug collision: last-writer-wins vs explicit error**
- F1: first entry wins, second is skipped with a warning written to `queue/COLLISION.log`.
- F2: slug is disambiguated by appending `-spec` / `-prompt` suffix.
- F1 is simpler; F2 allows both items to run.

---

### Recommendation

1. **Add `running.pid` as in-progress sentinel** (Option A). On re-run, check for `running.pid`; if PID is alive, skip the item. If PID is dead (stale), move `running.pid` to `running.pid.stale`, write a `failure.md` with reason `"orphaned: stale pid"`.

2. **Adopt append-with-wave-headers for `build-log.md`** (Option E). One line: `printf "## Wave %d — %s\n" "$wave" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> build-log.md`.

3. **Minimal artifact content headers** — a one-line HTML comment sentinel at the top of each file: `<!-- autorun:stage=spec-review slug=myfeature status=ok -->`. Lightweight, strippable in shell with one `sed` call.

4. **Slug collision: Option F1 (first-entry-wins + COLLISION.log)**. Operator configuration error should be surfaced loudly.

5. **`state.json` for mutable scalars only** — store: `{ "stage": "build", "wave": 2, "pre_build_sha": "abc123", "started_at": "...", "pid": 12345 }`. File-presence sentinels remain canonical for complete/failed; `state.json` covers in-progress mutable data. Atomic write via temp-rename.

6. **`autorun.config.json` validation at startup** — `run.sh` validates schema before processing any queue items. Reject: `build_max_retries < 1`, malformed `webhook_url`, `spec_review_fatal_threshold` outside `[1, 10]`.

**`run-summary.md` / `failure.md` conflict rule:** If both exist, `failure.md` wins.

**PR provenance block minimum required fields:** `slug`, `pre_build_sha`, `autorun_version` (from `VERSION`), `wave_count`, `test_cmd`, `timestamp_utc`. Optional: `codex_findings_count`, `webhook_notified`.

---

### Constraints Identified

- All state writes must be shell-native (no Python, no `jq` dependency for writes).
- `state.json` temp-rename pattern: write to `state.json.tmp`, then `mv -f state.json.tmp state.json` — POSIX `mv` is atomic on same-filesystem writes.
- `pre-build-sha.txt` is write-once. If Stage 4 is re-entered on retry, the orchestrator must NOT overwrite it.
- `build-log.md` must be created (empty) at item start so Stage 4 consumers can append without checking existence.

---

### Open Questions

1. **Stage 2 context handoff**: `review-findings.md` feeds the plan wrapper — does the prompt template inject it via `$(cat queue/<slug>/review-findings.md)` or via a file path arg?
2. **`state.json` write ownership**: only `run.sh` should write `state.json`; `claude -p` processes write only their own output files.
3. **Queue ordering**: alphabetical shell default. Extension point: `queue/ORDER` file listing slugs line-by-line. No action needed now.
4. **`failure.md` content contract**: should include machine-parseable fields (stage at failure, wave number, exit code) not just prose.
5. **Retention policy**: completed `queue/<slug>/` directories accumulate indefinitely. Extension point: `retain_days` config field for v2.

---

### Integration Points with Other Dimensions

- **Execution / Orchestration**: `running.pid` and `state.json` writes are orchestrator responsibilities. Write timing: on entry to each stage, not on exit.
- **Notification / Reporting**: `run-summary.md` and `failure.md` are trigger inputs for webhook/mail dispatch. `state.json` for structured fields, `run-summary.md`/`failure.md` for human body text.
- **PR / Git**: PR provenance block field list feeds directly into the git dimension's PR description template. The `pre-build-sha.txt` write-once constraint is a shared invariant.
- **Config / Validation**: `autorun.config.json` is consumed by both orchestrator and notification. Validation at startup is the execution dimension's job.
