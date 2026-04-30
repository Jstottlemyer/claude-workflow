### Critical Gaps

**1. Secret / credential handling at runtime**
The pipeline invokes `gh`, `claude -p`, Codex, and potentially a webhook. The spec says nothing about how credentials are available to the launchd process (which runs in a minimal environment — no `.zshrc`, no keychain unlock, no `SSH_AUTH_SOCK`). This is a production-incident-waiting-to-happen on first overnight run.

**2. Branch strategy and conflict handling**
`/build` writes code and `gh pr create` opens a PR, but the spec never says: what branch does the item run on? Who creates it? What happens if a prior item's PR is still open and touches the same files — does item 2 branch from main or from item 1's branch?

**3. Rollback scope**
"git reset --hard" after 3 failed build waves is mentioned but not defined. Reset to what ref? The branch tip at stage entry? The pre-autorun HEAD on main? If a partial build wave wrote 4 files before failing, which files survive the reset?

**4. Test suite definition**
"Tests pass" is an auto-merge trigger, but the spec never says how tests are run, what counts as passing, or what to do when there is no test suite (the repo may have none).

**5. queue/autorun.config.json ownership and bootstrapping**
The config is referenced but never specified: who creates it, what are valid values and defaults, is it committed to the repo or gitignored (it may contain `mail_to`, `webhook_url` — sensitive). First-run behavior is undefined.

**6. Concurrent invocation**
Nothing prevents two launchd jobs or two terminal sessions from running `/autorun` simultaneously against the same queue. No lock file, no PID file, no advisory mechanism.

---

### Important Considerations

**7. macOS mail + osascript dependency on logged-in session**
`osascript` requires an active GUI session. A launchd `LaunchDaemon` (root) or screen-locked session will silently fail osascript.

**8. Codex "one autonomous fix attempt" — scope undefined**
What does the fix attempt look like? Does the agent open a new commit on the same branch, force-push, amend?

**9. Partial-queue failure recovery**
If the orchestrator process crashes mid-queue, an in-progress item has neither `run-summary.md` nor `failure.md`. Re-run behavior on a partially-executed item (branch exists, PR may be open, some files written) is unspecified.

**10. PR provenance contents**
"Full provenance" is mentioned but not defined.

**11. Alphabetical queue ordering — priority mechanism absent**
If the user queues a hotfix alongside a large feature, there is no way to prioritize it.

**12. Notification failure is silent**
"Notification fails → run-summary.md fallback" — but nothing monitors whether `run-summary.md` is ever read.

**13. Autonomy directive content**
"Autonomy directive injected into every sub-agent invocation" — the directive itself is specified in the spec but adopters won't know which decisions agents will make autonomously.

---

### Observations

- `spec_review_fatal_threshold` in config is good, but the default value should be stated in the spec itself.
- `.prompt.txt → /spec --auto` flow is mentioned but the `--auto` flag may not exist in the current `/spec` command.
- No mention of max queue depth or what happens if queue contains many items.

---

### Verdict

**FAIL** — Three gaps (credential availability, branch/conflict strategy, rollback target ref) are concrete enough to cause a corrupted git state or a silent credential failure on the very first overnight run.
