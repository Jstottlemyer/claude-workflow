### Key Considerations

**Queue directory as primary UX surface**
The `queue/` directory is both the input mechanism and the live status board. Operators drop files to enqueue work and read subdirectories to monitor progress. This dual role creates tension: a busy queue dir is hard to scan at a glance during a run.

**Invocation ergonomics**
`flock -n queue/.autorun.lock bash scripts/autorun/run.sh` is the actual invocation. The slash command `commands/autorun.md` likely wraps this, but the raw form is what launchd or tmux actually calls. These two surfaces need to be consistent in what flags/env they accept.

**Config discoverability**
`autorun.config.json` is described as optional with no fallback documentation. Operators won't know what's configurable until they read source. Defaults need to be surfaced in `autorun.config.json` itself (commented example) or in `autorun.md`.

**Shell script API surface**
Each stage script (`spec-review.sh`, `plan.sh`, etc.) needs a stable calling convention: what positional args, what env vars, what exit codes, and what files it writes. This is currently unspecified. Without it, `run.sh` and each stage script are coupled at the source level.

**Error surfacing**
`failure.md` is the error artifact, but there's no defined schema. Operators waking up to a failed run need to know: which stage failed, what the verdict was, what was attempted, what the pre-build SHA is to roll back.

---

### Options Explored

**A. Queue dir layout: flat vs. namespaced status files**

*Flat (current):* All stage artifacts in `queue/<slug>/`. Simple but hard to parse run state at a glance.

*Namespaced status:* Add `queue/<slug>/status.json` with `{stage, state, timestamp, exit_code}` written by `run.sh` at each transition.

| | Pros | Cons | Effort |
|---|---|---|---|
| Flat | Zero new files, matches spec | No machine-readable run state | — |
| status.json | `watch cat queue/*/status.json` works; enables idempotent resume | Another file to maintain schema for | Low |

Recommendation: add `status.json` — it's low effort and solves monitoring + resume in one shot.

---

**B. Stage script calling convention: positional args vs. env vars**

*Positional:* `spec-review.sh <slug> <spec-file>` — explicit, shell-scriptable.

*Env-var:* `SLUG=myfeature SPEC_FILE=... bash spec-review.sh` — easier to source `defaults.sh` first.

*Mixed (recommended):* `run.sh` exports a standard env block (`SLUG`, `QUEUE_DIR`, `ARTIFACT_DIR`, `CONFIG_FILE`) before calling each stage. Stage scripts read env, no positional args. This makes each script independently testable with `export SLUG=test && bash spec-review.sh`.

| | Pros | Cons | Effort |
|---|---|---|---|
| Positional | Explicit in `ps aux` | Breaks if arg order drifts | Low |
| Env-only | Uniform, sourceable | Hidden deps | Low |
| Mixed env block | Testable, uniform | Requires `defaults.sh` discipline | Low |

---

**C. STOP kill-switch: file presence vs. named pipe vs. signal**

*File presence (current):* `run.sh` polls `[ -f queue/STOP ]` between stages. Simple, works across tmux/launchd.

*Signal (SIGTERM):* launchd can send SIGTERM; `run.sh` traps it. More immediate but doesn't compose with manual use.

Recommendation: keep file-presence STOP but define exactly when it's checked (between stages only, not mid-stage) and document that it does NOT abort mid-build (safe by design — wave completes).

---

**D. `autorun.config.json` — optional vs. required with defaults**

If absent, `defaults.sh` must define all fallbacks. Risk: operator edits `defaults.sh` thinking it's the config surface, creating drift.

Better: ship a `queue/autorun.config.json.example` (or embed the schema + defaults as a comment block in `defaults.sh`) so the config surface is self-documenting.

---

### Recommendation

1. **Define a stage script env contract in `defaults.sh`:** Document the 6–8 env vars every stage script can rely on (`SLUG`, `QUEUE_DIR`, `ARTIFACT_DIR`, `SPEC_FILE`, `CONFIG_FILE`, `DRY_RUN`). Stage scripts read env, write to `$ARTIFACT_DIR/`, exit 0/1.

2. **Add `queue/<slug>/status.json`** written by `run.sh` at each stage transition: `{slug, stage, state: "running|passed|failed|skipped", timestamp, exit_code}`. This costs ~10 LOC in `run.sh` and unlocks monitoring + idempotent resume.

3. **Define `failure.md` schema** as a fixed template: stage name, verdict line, claude-p stderr tail (last 50 lines), pre-build SHA, retry count. `notify.sh` reads this file — it needs structure.

4. **`autorun.md` should document:**
   - How to enqueue (drop `.spec.md` or `.prompt.txt`)
   - Config keys with defaults inline
   - STOP semantics (checked between stages, not mid-wave)
   - How to invoke manually vs. via launchd
   - Exit codes from `run.sh` (0 = all passed, 1 = at least one item failed, 2 = lock held)

5. **Ship `queue/autorun.config.json.example`** with all keys and their defaults.

---

### Constraints Identified

- `flock -n` returns immediately if lock is held (exit 1) — launchd will log this as a failure unless `run.sh` wraps it and exits 0 when lock is contended.
- Stage scripts call `claude -p` which requires the CLI to be on `$PATH`. `run.sh` sources `~/.zshenv.local` but launchd has a minimal `$PATH`. Explicit `export PATH=...` in `run.sh` or the launchd plist is required.
- The 7 parallel `claude -p` processes for spec-review share the same API key. Rate-limit risk is accepted per spec, but `notify.sh` should log HTTP 429 occurrences so the operator can tune parallelism post-run.
- `/spec --auto` is an undeclared dependency. `run.sh` must guard: if `--auto` flag doesn't exist, the `.prompt.txt` path fails silently. Add a capability check at startup or a clear error in the `.prompt.txt` handler.

---

### Open Questions

1. **Stage 2 context handoff:** How does `review-findings.md` reach the plan wrapper? Is it appended to the `--- CONTEXT:` block in the `claude -p` invocation, or read as a second file? This is the most load-bearing unresolved interface question.

2. **PR provenance block:** What fields does the PR body include? At minimum: slug, spec file path, pre-build SHA, wave count, Codex verdict summary. Who writes it — `build.sh` or a dedicated section of `run.sh`?

3. **Idempotency on re-run:** If `queue/<slug>/plan.md` already exists when `run.sh` processes a slug, does it skip the plan stage? Define: "if `<artifact>` exists, stage is skipped" as the universal rule.

4. **`notify.sh` event model:** Which events fire notifications — per-stage failure, per-item completion, end-of-queue? Webhook payload schema is undefined.

5. **DRY_RUN mode:** Is there a way to run the orchestrator without invoking `claude -p` (for testing the queue/artifact logic)?

---

### Integration Points with Other Dimensions

- **Orchestration/flow control:** The env contract defined here is the primary input to `run.sh` stage-sequencing. These dimensions need to agree on which layer owns the stage transition loop.
- **Security/credentials:** `run.sh` sources `~/.zshenv.local` — the security dimension needs to confirm this is safe for launchd (full disk access, no TTY). The `$PATH` gap for `claude` binary is a security-adjacent ops concern.
- **Testing/verification:** The `status.json` artifact and `failure.md` schema defined here are what a test harness would assert against.
- **Notification/reporting:** `notify.sh` is a consumer of `failure.md`, `run-summary.md`, and `pr-url.txt`. The schemas for all three need to be locked before `notify.sh` is implemented.
