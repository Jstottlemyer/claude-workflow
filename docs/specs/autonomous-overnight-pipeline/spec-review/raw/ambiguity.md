### Critical Gaps

**1. "Fatal" finding is undefined**
Stage 1 halts when "≥2 fatal" spec-review findings exist, but the spec never defines what constitutes a "fatal" finding. Two engineers will implement this differently.

**2. Build "waves" are never defined**
Stage 4 references "build waves," "execute wave," and "check kill-switch" without explaining what a wave is, how many there are, how they're sized, or what determines wave boundaries.

**3. `git reset --hard` target is ambiguous**
The spec says "git reset --hard to pre-build SHA" but never defines how the pre-build SHA is captured, where it's stored, or what "pre-build" means when multiple build waves have run.

**4. Codex review "blocking" vs "non-blocking" classification is undefined**
Stage 6 splits findings into blocking and non-blocking, but the spec provides no criteria for this classification. This is the gate that determines whether auto-merge fires.

**5. "1 autonomous fix attempt" scope is unspecified**
Stage 6 allows one fix attempt for blocking Codex findings. No constraints on what the agent may change — same files? Adjacent areas? Spec file?

**6. Queue item identity is underspecified**
The spec doesn't define a queue item's canonical identifier. If `myfeature.spec.md` and `myfeature.prompt.txt` both exist, are they one item or two? What happens if the same feature name is queued twice?

---

### Important Considerations

**Notification contract is unspecified**
`webhook_url` and `mail_to` are config fields but the payload schema, retry behavior on delivery failure, and which events trigger a notification are not described.

**"Alphabetical" ordering has undefined tiebreakers and change semantics**
Adding a new item mid-run can alter the processing order of pending items. The spec doesn't say whether the queue is snapshotted at run start or re-evaluated each iteration.

**`queue/STOP` kill-switch granularity**
"Halt after current wave" — does this mean after the current build wave completes, after the current pipeline stage completes, or after the current queue item completes?

**PR provenance block format is unspecified**

**Stage 2 context handoff is unspecified**
"plan (sees stage 1 findings as context)" — how? Appended to the prompt? Written to a file the plan command reads?

**"run tests" test scope is undefined**

---

### Observations

- `spec_review_fatal_threshold` defaults to 2 but "fatal" is undefined — the config is consistent internally but meaningless until the classification scheme exists.
- The spec says the orchestrator "loops over queue entries alphabetically" but also describes parallel spec-review. It's unclear whether parallelism is within a single item only.
- `failure.md` and `run-summary.md` schemas are not defined.

---

### Verdict

**FAIL** — Three undefined terms ("fatal," "wave," "blocking/non-blocking") are used as decision gates that control branching, reset, and merge behavior; implementation cannot begin without resolving them.
