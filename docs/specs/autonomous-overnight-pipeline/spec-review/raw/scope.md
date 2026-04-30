### Critical Gaps

1. **Squash-merge target branch unspecified** — The spec says squash merge fires when "tests pass + 0 blocking Codex findings," but there is no explicit statement of the target branch. A merged-to-main build wave that breaks something is catastrophic. The target branch and protected-branch rules must be specified.

2. **Spec-review threshold gate "fatal" is ambiguous** — "≥2 of 6 fatal → halt" is defined, but "fatal" is not.

3. **Rollback is undefined** — "3 retries then rollback" appears in scope and in AC #5, but what rollback means is never stated. Git reset to pre-run SHA? Revert PR? Delete branch?

4. **No error taxonomy for Codex "blocking" vs "non-blocking"** — Who or what classifies a finding? If delegated to Codex's own output, that's an uncontrolled external dependency on Codex's output format.

---

### Important Considerations

- **Queue ordering is unspecified** — Is the queue FIFO by filename? By mtime? By explicit priority field? If two items are queued and one is a 2-hour build, the other a 5-minute fix, order matters.

- **Idempotent re-runs need a state file definition** — "Idempotent re-runs" is listed as in-scope with no mechanism described beyond file presence.

- **Autonomy directive is scope-creep risk** — "Injected into every sub-agent invocation" implies wrapping existing pipeline commands. The out-of-scope statement says "not replacing or modifying existing interactive pipeline commands," but injection implies at least wrapping them.

- **macOS-only notification is undeclared as a constraint** — `osascript` is macOS-only. This belongs in Out of Scope explicitly.

- **No timeout or max-runtime ceiling** — A single wave could theoretically run for hours.

---

### Observations

- Natural Phase 2 seams: cost ceiling (already out-of-scope), remote CCR execution (also listed), multi-project queue support, retry backoff strategy. The out-of-scope list is doing its job.
- `.prompt.txt` entry path requires `/spec --auto` flag that doesn't appear to exist yet — undeclared dependency.
- "Provenance" in PR is undefined.

---

### Verdict

**FAIL** — Three critical gaps (undefined rollback mechanism, unresolved merge target / branch strategy, and undefined "fatal" severity) represent implementation decision points that will produce incompatible designs if left to individual judgment.
