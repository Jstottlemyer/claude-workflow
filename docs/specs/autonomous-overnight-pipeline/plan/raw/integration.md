### Key Considerations

**1. install.sh — command and script registration**

`install.sh` symlinks `commands/*.md` via a glob — `commands/autorun.md` will be picked up automatically at the next `install.sh` run with no code changes needed. Scripts are also symlinked via a flat glob (`scripts/*.sh`) — but only from the top-level `scripts/` directory, not subdirectories. `scripts/autorun/*.sh` will NOT be symlinked by the current install loop. Every `autorun/` script also needs `+x` set on the source file.

**2. Persona metrics — the core compatibility problem**

The `findings-emit.md` directive is invoked by the host Claude agent during an interactive session. When `run.sh` calls `claude -p "$(cat commands/spec-review.md) ..."`, each invocation is a headless stateless subprocess. The `findings-emit` step inside that subprocess would still fire — the prompt text is injected verbatim — and the subprocess does have filesystem access to write `docs/specs/<feature>/spec-review/`. So metrics WILL be written, with important caveats:
- The subprocess's `cwd` must be set to the repo root for `git check-ignore` to function
- `model_versions.reviewer-default` will reflect whatever model `claude -p` uses

**3. Command files with human-in-loop language that will stall headless runs**

Confirmed blocking prompts in command files:
- `spec-review.md` line 146: `"Approve to proceed to /plan?"` — subprocess emits this and waits for stdin that never arrives
- `plan.md` line 113: `"Approve to proceed to /check?"`
- `build.md` line 54: `"Launch Wave 1? (go / hold)"`
- `build.md` line 120: `"Justin controls pace — approval before each wave"`

This is the largest integration risk. The autonomy-directive approach (`"...skip approval gates, proceed automatically"`) relies on the model obeying a soft override of hard-wired approval prompts. There is no guarantee a headless model will suppress an interactive approval gate from a strongly-worded command file.

**4. Context handoff — review-findings.md to plan.sh**

Three mechanical options:

| Option | Mechanics | Risk |
|--------|-----------|------|
| A. Append to prompt | `cat review.md >> plan_prompt` | Prompt grows unboundedly; context window ceiling hit on large specs |
| B. File argument in CONTEXT block | `--- CONTEXT: $(cat queue/<slug>/review.md)` | Same issue |
| C. Shared slug directory, stage reads own artifacts | Each stage script reads `queue/<slug>/` outputs from prior stages by convention | Cleanest; no prompt bloat; plan.sh reads `review-findings.md` by convention |

Option C is most robust. Each wrapper script reads its expected predecessor artifact from `queue/<slug>/` before composing its prompt.

**5. The spike — what to test and what "behavioral contract confirmed" means**

`spec-review.sh` should test these specific behaviors against a real spec:
1. Does the headless `claude -p` invocation actually dispatch 6 parallel reviewers, or does it serialize?
2. Does the autonomy-directive successfully suppress the `"Approve to proceed to /plan?"` output?
3. Are per-persona raw files written to `docs/specs/<feature>/spec-review/raw/<persona>.md`?
4. Is `findings.jsonl` emitted with valid schema?
5. Is `run.json.status: "ok"` (not `"failed"` due to git-untracked spec)?
6. Does the subprocess exit 0?

"Behavioral contract confirmed" = all 6 items pass on a real spec file. Items 1 and 2 are the most likely failure modes.

**6. launchd vs tmux**

launchd jobs run with a stripped environment: no `.zshrc`, no PATH aliases. Critical implications:
- `claude`, `gh`, `codex` must be referenced by absolute path or PATH must be explicitly set
- `flock` is at `/usr/bin/flock` on macOS — safe
- `osascript` works from launchd; `mail` may silently fail
- `run.sh` should export a minimal PATH: `/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin`

**7. queue/ gitignore**

```
queue/autorun.config.json    # may have webhook URL
queue/*/                     # per-item artifact dirs (WIP, large)
queue/STOP                   # transient kill-switch
queue/run.log                # gitignored audit trail
```

`queue/<slug>.spec.md` and `queue/<slug>.prompt.txt` are inputs — committed for traceability. Or gitignore `queue/` entirely (simpler; entries are transient).

**8. Rollout sequence**

1. `scripts/autorun/defaults.sh` — pure config, unblocks everything
2. `scripts/autorun/notify.sh` — pure I/O, testable standalone
3. `scripts/autorun/spec-review.sh` — **spike gate**: confirm behavioral contract before proceeding
4. `scripts/autorun/plan.sh` — same pattern as spec-review
5. `scripts/autorun/check.sh`
6. `scripts/autorun/risk-analysis.sh` — inline prompt
7. `scripts/autorun/build.sh` — most complex: wave runner + retry + rollback
8. `scripts/autorun/run.sh` — orchestrator; only valid once all stage wrappers exist
9. `commands/autorun.md` — entry point; last, because the command is useless until run.sh works

---

### Options Explored (with pros/cons/effort)

**Option A — Autonomy directive injected at prompt-construction time**
Append `"AUTONOMY: operate headlessly, auto-approve all gates, do not prompt for input"` to the `claude -p` prompt.
- Pro: zero changes to existing command files; works today
- Con: relies on model obeying a soft override of hard-wired approval prompts; fragile across model updates
- Effort: none for existing files

**Option B — $AUTORUN guard in each command file**
Add `{% if AUTORUN %}skip-to-artifacts{% endif %}` blocks to `spec-review.md`, `plan.md`, `build.md`.
- Pro: deterministic; approval gates are structurally absent in headless mode
- Con: modifies existing command files; risk of breaking interactive flow
- Effort: medium; 3 file edits

**Option C — Wrapper-owned prompt text (no catting of command files)**
Wrapper scripts compose their own prompt from scratch.
- Pro: complete control
- Con: duplication; wrapper drifts from command file as pipeline evolves
- Effort: high; defeats "reads command files verbatim" design goal

**Recommendation:** Option A for the spike. If spike shows approval gate is NOT suppressed, escalate to Option B — add a single `$AUTORUN` env variable check at the top of each blocking section. Three affected files, one conditional block each.

---

### Constraints Identified

1. **install.sh flat-glob constraint**: `scripts/autorun/*.sh` will not be symlinked without an install.sh change. Required: add a loop for `scripts/autorun/`.
2. **`claude -p` parallelism constraint**: `claude -p` is a blocking synchronous call. Whether it honors Agent-tool parallelism in headless mode is unverified. **This is the spike's most critical test.**
3. **Git-tracked spec constraint**: `spec-review.md` refuses with `run.json.status: "failed"` if `spec.md` is not git-tracked. `/autorun` operates on pre-existing committed specs.
4. **launchd PATH constraint**: all external tools must be absolute paths or PATH explicitly exported in wrapper scripts.
5. **Context window per-invocation**: each `claude -p` subprocess starts with zero context. Long review artifacts injected into plan prompts may approach context limits.

---

### Open Questions

1. Does `claude -p` support Agent tool invocations inside the prompt execution? If not, 6 "parallel" reviewers are actually sequential.
2. Should `scripts/autorun/` be symlinked or run directly from the repo?
3. What is the expected working directory for wrapper scripts? Must be the feature's project root for `git check-ignore` to work.
4. Is `/spec --auto` a hard dependency before the first autorun sprint, or does autorun accept only pre-existing committed specs as inputs?
5. What happens to `queue/STOP` if run.sh is killed mid-stage?

---

### Integration Points with other dimensions

- **Persona Metrics**: Subprocess writes to `docs/specs/<feature>/<stage>/`. The subprocess's `cwd` must be the feature project root. `run.sh` must `cd` to the project root before each stage invocation.
- **install.sh**: Needs a new subdirectory loop. Also needs `queue/` gitignore in the sentinel-bracketed block.
- **Command file stability**: Three files with approval-gate language are shared dependencies. The `$AUTORUN` env variable approach (Option B escalation) must be additive-only.
- **Spike result**: The entire build sequence after step 3 is contingent on the spike result. Treat step 3 as a hard gate with a branch condition.
