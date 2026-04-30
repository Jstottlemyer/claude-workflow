### Key Considerations

**1. Invocation verbosity is a UX cliff**
`flock -n queue/.autorun.lock bash scripts/autorun/run.sh` requires the user to remember exact syntax at 10pm when they're tired. One mistyped flag silently does nothing (flock exits 1 if locked — user may not notice).

**2. Monitoring gap is the highest-anxiety period**
Once the run starts, there's no obvious "is it still running?" signal without knowing where to look. Desktop banners are best-effort and macOS may suppress them.

**3. Kill-switch discoverability is near-zero**
`touch queue/STOP` is not memorable. User discovering a bad build in progress has no intuitive escape.

**4. Recovery UX assumes the operator can parse shell artifacts**
`failure.md` + `pre-build-sha.txt` require knowing where to look and what to do with them. No guided recovery path.

**5. Queue management is implicit**
No affordance for "what's in my queue right now?" before launching.

---

### Options Explored

**A. Invocation: raw flock command vs. `autorun` alias vs. wrapper script**

| Option | Pros | Cons | Effort |
|---|---|---|---|
| Raw flock (current) | Transparent, no magic | Unmemorable, fragile at night | None |
| `~/.local/bin/autorun` wrapper | One word, handles flock internally, can print status on "already running" | Requires install step | Low |
| `commands/autorun.md` slash command that prints the invocation | Discoverable via tab-complete, copyable | Still requires the user to paste + run | Very low |

**Recommendation:** Wrapper + slash command. The slash command becomes the discovery surface; the wrapper is what you actually run.

**B. Monitoring: tail log vs. `autorun status` vs. live tmux pane**

| Option | Pros | Cons | Effort |
|---|---|---|---|
| `queue/run.log` (append) | Simple, always there | User must know to `tail -f` it | None |
| `autorun status` command | Prints current stage, queue depth, last heartbeat | Adds a status subcommand to maintain | Low |
| `queue/.current-stage` file | Dumb, writable by any stage | No logic needed, `cat` is enough | Very low |

**Recommendation:** `queue/.current-stage` (updated by each stage, content like `Stage 4/7 — build wave 2 of 3 — feature-auth`) + `queue/run.log`.

**C. Kill-switch: `touch STOP` vs. named command vs. signal**

| Option | Pros | Cons | Effort |
|---|---|---|---|
| `touch queue/STOP` (current) | Simple mechanism | Not discoverable | None |
| `autorun stop` subcommand | Self-documenting, confirms "stopping after current wave" | Needs wrapper anyway | Low (bundled with wrapper) |
| `kill $(cat queue/.pid)` | Immediate | Dangerous — mid-wave kill can leave branch dirty | None (bad) |

**Recommendation:** `autorun stop` writes the STOP file and prints "Run will halt after the current build wave."

**D. `failure.md` content depth**

| Option | Pros | Cons | Effort |
|---|---|---|---|
| Current (implied: error output) | Exists | Unclear schema; operator guesses what's in it | Low |
| Structured failure.md (stage, wave, error, rollback sha, re-queue command) | Operator can act immediately | Spec must define schema | Low |

**Recommendation:** Structured `failure.md` with a literal copyable re-queue command in the last line.

**E. Run summary: single file vs. per-item vs. index**

| Option | Pros | Cons | Effort |
|---|---|---|---|
| `queue/run-summary.md` (current) | Simple | Multi-item runs become one wall of text | None |
| Per-item: `queue/<slug>/run-summary.md` | Clean separation | Already implied by queue structure | Very low |
| Index: `queue/index.md` listing all slugs + pass/fail | Morning overview in one file | Must be written by orchestrator | Low |

**Recommendation:** Per-item summaries (already in spec) + a top-level `queue/index.md` written at run end.

---

### Recommendation

**Prioritized by effort-to-UX-gain ratio:**

1. **`autorun` wrapper script** (15 min): wraps flock, exposes `autorun start | stop | status`. This single change fixes invocation verbosity, kill-switch discoverability, and monitoring in one shot.

2. **`queue/.current-stage` file** (5 min): each stage script overwrites it. `autorun status` cats it. User can check from any terminal.

3. **Structured `failure.md` schema** (30 min): define once in spec, emit from build stage. Include: failed stage, wave, error summary, branch name, rollback sha, and a literal "re-queue with: `cp queue/<slug>/spec.md queue/`" line.

4. **`queue/index.md`** (20 min): written at run completion. Columns: slug | verdict | stage-reached | PR URL or failure path. The morning artifact.

5. **`commands/autorun.md` content** — reference card:
```
## /autorun — Autonomous Overnight Pipeline
Start:    autorun start
Status:   autorun status          (or: cat queue/.current-stage)
Stop:     autorun stop            (halts after current build wave)
Queue:    cp docs/specs/<feature>/spec.md queue/<slug>.spec.md
State:    pending | running | done (run-summary.md) | failed (failure.md)
Morning:  cat queue/index.md
Logs:     tail -f queue/run.log
```

---

### Constraints Identified

- **macOS notification suppression** — Focus mode/DND during sleep hours eats desktop banners. `mail` is the only reliable async channel. Both are truly best-effort.
- **launchd vs. manual start** — launchd has minimal environment; wrapper must source PATH explicitly.
- **Queue dir as both config and state** — editing spec.md after queuing but before the run starts silently uses the edited version. Worth a note in the reference card.
- **Branch proliferation** — repeated failures leave `autorun/<slug>` branches. `failure.md` should note the branch name.
- **`queue/STOP` does NOT self-clear** — operator must `rm queue/STOP` before the next run. Document explicitly in reference card.

---

### Open Questions

1. Should `autorun status` exit non-zero when no run is in progress, to support scripting (`autorun status || autorun start`)?
2. Is there a max queue depth? Operator queuing 8 specs overnight needs to understand blast radius.
3. What happens if a spec fails Stage 1 gate (≥2 FAIL verdicts)? Item-level failure + continue (maximizes overnight yield) vs. halt-all (minimizes blast radius). Spec implies item-level continue.
4. For the Codex review stage: if Codex is unavailable at 3am, is that a fatal failure or a skip-with-warning?

---

### Integration Points with Other Dimensions

- **Security/Secrets:** `autorun` runs `claude -p` and `gh` with ambient credentials. The autonomy directive explicitly suppresses "should I?" prompts — the security persona should gate on what operations are permitted without confirmation.
- **Reliability/Error handling:** Stage 1 halt behavior (item-level vs. run-level) is both a UX and a reliability decision.
- **Install/Onboarding:** The wrapper script must be in `install.sh` or the day-one experience is "command not found."
