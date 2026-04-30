### Key Considerations

**Rate-limit behavior for `claude -p`**
When 7 concurrent `claude -p` processes fire simultaneously, they all hit the API at roughly the same second. The likely failure mode is an HTTP 429 with a `retry-after` header — but the shell script layer almost certainly does not read that header. Instead, `claude -p` likely exits non-zero with an error message. The threshold gate may silently count a failed process as a "no objections" vote rather than an error, producing a false-pass.

**Sequential processing across N queue items**
At 30-60 min per item, 5 items = 2.5-5 hours, 10 items = 5-10 hours. A single hung `claude -p` call blocks the entire queue indefinitely. There is no per-call timeout in the spec.

**Wave retry overhead**
3 retries × ~5 min average wave time × say 4 waves per item = 60 min of retry overhead per item in the worst case.

**Codex review timing and merge blocking**
Codex CLI timing is entirely undocumented. If it runs post-PR and blocks merge, a slow or hung Codex call stalls the build stage indefinitely.

**Build-log accumulation**
At scale (10 items × 4 waves × 3 retry attempts × multi-KB output per wave), the log can reach tens of MB. Parsing becomes unwieldy.

**Stale failure.md items**
If a queue item hits max retries and writes `failure.md` but is never cleaned up, re-queuing the same item on the next `/autorun` run will replay the failure.

**No cost ceiling**
Worst-case overnight: 10 items × 4 stages × 3 retries × 7 spec-reviewer calls = 840 `claude -p` API calls. At moderate token usage (10K tokens per call), that is 8.4M tokens. At current pricing this could be $50-200+ with no circuit breaker.

---

### Options Explored

**1. Add per-call timeout (`timeout 300 claude -p ...`)**
- Pro: Prevents hung processes from blocking the queue forever; cheap.
- Con: A 300-second timeout is arbitrary.
- Effort: Low (1-line change per `claude -p` invocation).

**2. Rate-limit back-off wrapper around the 7-concurrent spec-reviewers**
- Pro: Prevents the 429 cascade; reads `retry-after` if available.
- Con: Adds meaningful complexity; may serialize spec-review, erasing parallelism benefit.
- Effort: Medium.

**3. Serialize spec-review (1 reviewer at a time)**
- Pro: Eliminates the concurrent rate-limit risk entirely.
- Con: 6× slower for spec-review; 6 calls × ~2 min = ~12 min vs ~2 min parallel.
- Effort: Low.

**4. Add a soft cost ceiling via call counter**
- Pro: Prevents runaway spend; easy to implement as a counter file incremented per `claude -p` call with a configurable `MAX_API_CALLS` in config.
- Con: A call count is a proxy for cost, not actual cost.
- Effort: Low.

**5. Per-item log files instead of a single build-log.md**
- Pro: Keeps logs bounded and scannable; natural archiving when item completes.
- Con: Minor — slightly more file management.
- Effort: Low.

**6. Codex call timeout + fallback to "skip review, warn in PR"**
- Pro: Unblocks merge if Codex is slow/unavailable.
- Con: Silently skipping Codex review undermines its purpose.
- Effort: Low-medium.

---

### Recommendation

Implement options 1, 4, and 5 as baseline mitigations — they are all low-effort and address the three highest-severity risks (hung processes, runaway cost, unmanageable logs).

Defer option 2 (rate-limit back-off) unless 429s are observed in practice.

For Codex (option 6): add a `timeout 120 codex ...` call and on non-zero exit write a warning to the PR body rather than blocking.

---

### Constraints Identified

- Personal API key rate limits are undocumented and effectively unknown until hit in practice.
- No process supervisor means a crashed orchestrator script leaves queue items in limbo with no recovery path.
- `STOP` file is checked only between build waves, not between stages — a runaway item within a stage cannot be interrupted mid-flight.
- No mechanism to detect that a `claude -p` process exited with output vs. exited with a rate-limit error producing no output — the threshold gate cannot distinguish these today.
- launchd job has no restart policy; a crash at 2 AM produces no overnight output and no notification until the user checks in the morning.

---

### Open Questions

1. What does `claude -p` actually emit on a 429 — empty stdout, an error JSON on stdout, or stderr only?
2. Is there a documented RPM/TPM limit for personal Pay-As-You-Go keys?
3. Does the Codex CLI block until its review is complete, or does it poll?
4. What is the intended behavior if the launchd job is still running when the next scheduled window starts?
5. Should `/autorun` be re-entrant — i.e., can it resume a partially-completed queue?

---

### Integration Points with Other Dimensions

- **Security/Auth:** Rate-limit failures expose the API key's tier indirectly. If the orchestrator logs `claude -p` stderr, the key itself must not appear in those logs.
- **UX/Observability:** Cost and call-count metrics should be included in the summary notification, not just pass/fail.
- **Correctness/Idempotency:** Retry logic and queue-item state need to agree — if wave 2 of item A succeeds on retry 3, the queue state must reflect that unambiguously.
- **Build/Git dimension:** Sequential one-commit-per-wave means a 3-retry wave produces 3 commits on the branch before rollback. The rollback mechanism must hard-reset, not just revert, or the branch history becomes noisy.
