**Verdict:** PASS WITH NOTES — The plan covers the core pipeline stages and most spec requirements, but several acceptance criteria lack explicit verification steps and two spec requirements have no corresponding task.

**Must Fix:**

- **AC #7 (.prompt.txt → `/spec --auto`) is deferred with no task.** Open Question 3 punts it to documentation only. The spec lists it as a key acceptance criterion, not optional behavior. The plan needs a task (even if small) that handles `.prompt.txt` detection and invokes `/spec --auto` before the pipeline continues — or the spec must formally descope it with the user's sign-off.

- **autorun.config.json schema has no creation task.** The spec requires a defined schema with 6 fields (`webhook_url`, `mail_to`, `spec_review_fatal_threshold`, `build_max_retries`, `test_cmd`, `max_api_calls`). `defaults.sh` sets env-var defaults but nothing in the task list writes or documents the config file schema itself (e.g., a sample `queue/autorun.config.example.json`). Without it, users have no reference and the `--help` or reference card will be hollow.

- **AC #5 (retry × 3 → rollback → failure.md → notification) has no verification step.** `build.sh` (Task 9) is listed as implementing retries and rollback, but no task describes how this acceptance criterion gets tested or validated before ship. The done-criteria for Task 9 is structurally vague — it lists behaviors but not how the implementer confirms they work.

**Should Fix:**

- **AC #6 (macOS notification fires on run completion) lacks a smoke-test task.** `notify.sh` implements the mechanism, but no task confirms it fires end-to-end (osascript + mail + webhook path) in the context of a real run.

- **AC #4 (STOP kill-switch: current wave completes then halts cleanly) has no verification step.** Task 9 mentions the STOP check, Task 10 mentions queue loop — but neither task describes how "current wave completes then halts cleanly" gets confirmed.

- **Codex review categorization logic (blocking vs. non-blocking) is in run.sh (Task 10) but the parsing contract is unspecified.** The spec defines `High:` = blocking (1 fix attempt), `Medium:`/`Low:` = non-blocking (justification comment on PR). Task 10's scope blob is already large; there's no sub-task or note describing the exact string-matching or JSON-parsing logic Codex output requires.

- **`flock -n` concurrent invocation protection: macOS availability is unverified.** `flock` is not installed by default on macOS (it's a Linux util). The plan doesn't note this or propose a fallback.

- **queue/index.md (morning artifact) is mentioned in Design Decision #9 but has no standalone task.** It's presumably inside Task 10 (run.sh), but the done-criteria for Task 10 don't mention it.

**Observations:**

- The spike-gate on Task 4 is structurally sound but creates a plan-within-a-plan risk: if the spike fails and `$AUTORUN` guards are needed (Task 5), Tasks 6–9 may need revision.
- Design Decision #3 (state.json + orphan detection via stale PID) is good but the orphan-recovery behavior isn't described.
- `AUTORUN_GH_TOKEN` is mentioned in security hardening but there's no task to document how users provision it.
- The `timeout 300 claude -p` mitigation interacts with build waves — a wave that legitimately takes >5 minutes will be killed silently.
