### Critical Gaps

**1. `claude -p` behavioral contract is unverified**
The spec assumes `claude -p "<markdown prompt>"` will faithfully execute command-file logic as if it were an interactive slash command. Claude's headless mode may not replicate slash command dispatch (tool permissions, file access scope, MCP servers loaded). This needs a spike before any orchestration scaffolding is built.

**2. `claude -p` invocation model is inverted**
The spec says: `claude -p "$(cat scripts/autorun/run.sh)"` — passing a shell script as a Claude prompt. A shell script is not a prompt. Either the orchestrator is a shell script that *calls* `claude -p`, or Claude *generates* the orchestration. These are two different architectures.

**3. Codex CLI integration is unvalidated**
`codex exec --full-auto` is referenced without confirming that flag exists, that Codex can receive a PR diff as input, or that it can emit structured blocking/non-blocking signal consumable by a shell script. CLI flags must be verified via `--help` before use.

**4. Parallel `claude -p` resource limits are unknown**
7 concurrent Claude CLI processes with no stated rate limit handling. Claude API has per-minute token limits. 6 spec-review agents running simultaneously may hit limits, producing silent failures or partial outputs that the threshold gate misinterprets.

**5. Output parsing from `claude -p` is underspecified**
The threshold gate (≥2 fatal → halt), the Codex blocking signal, and test-pass detection all require structured output extraction from subprocess stdout. No output schemas, delimiters, or parsing contracts are defined.

---

### Important Considerations

**Rollback correctness depends on SHA capture timing**
If the orchestrator itself stages files before build waves start, the reset may destroy orchestrator state.

**PR creation before Codex review creates ordering risk**
Stage 5 (gh pr create) runs before Stage 6 (Codex review). If Codex finds blocking issues, the PR already exists. A failed fix attempt leaves an open PR in a broken state.

**Kill-switch file check granularity is coarse**
Checking `queue/STOP` only between waves means a wave in progress cannot be interrupted. If a build wave hangs (e.g., claude -p waiting on tool approval), the process blocks indefinitely. A timeout per subprocess invocation is missing.

**Concierge plugin dependency is not described**
Listed as an external dependency but never referenced in stages or scripts.

**`gh pr merge --squash` is destructive and non-reversible**
No human gate. The spec should acknowledge this is irreversible.

---

### Observations

- The autonomy directive will have unpredictable effects across different command contexts.
- Reading existing command files "verbatim" is good for maintenance alignment, but those files may reference "the user will confirm" that stall a headless run.
- `osascript` implies the machine must be awake and running macOS.
- The queue-based input decouples invocation from execution — good design.

---

### Verdict

**FAIL** — Two architectural ambiguities (invocation model inversion, unverified `claude -p` behavioral contract) and two unvalidated external dependencies (Codex CLI flags, parallel API limits) are blockers that would force a redesign mid-build.
