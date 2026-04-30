# Claude Workflow Pipeline

An 8-command pipeline for [Claude Code](https://claude.com/claude-code) that adds structured planning, multi-agent review, and execution discipline to any project.

**You say WHAT. Claude handles HOW.** Bug fix, small change, feature, or full V2 — the same pipeline scales. 27 default agent personas review your spec and plan before code gets written, and an end-of-session `/wrap` compiles what you learned into durable memory.

**Install (one-liner):**
```bash
git clone https://github.com/Jstottlemyer/claude-workflow.git ~/Projects/claude-workflow && cd ~/Projects/claude-workflow && ./install.sh
```

Then open any project and type `/kickoff` to initialize, or `/flow` to see the reference card.

**License:** MIT — see [LICENSE](LICENSE).

## What This Is

A complete workflow system that scales to the size of the work:

| Work Size | Pipeline |
|-----------|----------|
| Bug fix | Describe it, fix it, verify |
| Small change | `/spec` (quick) then `/build` |
| Feature | Full pipeline: `/kickoff` through `/build` |
| V2 / Rework | Revise existing spec, then full pipeline |

## The Pipeline

```mermaid
flowchart LR
    K["/kickoff<br/><sub>constitution<br/>+ agent roster</sub>"]:::setup
    S["/spec<br/><sub>Q&A · confidence-tracked</sub>"]:::define
    SR["/spec-review<br/><sub>requirements · gaps · ambiguity<br/>feasibility · scope · stakeholders</sub>"]:::review
    JS1["Judge · Dedupe · Synth<br/><sub>cluster · attribute · compose<br/>→ review.md</sub>"]:::synth
    P["/plan<br/><sub>api · data-model · ux<br/>scalability · security · integration</sub>"]:::plan
    JS2["Judge · Dedupe · Synth<br/><sub>→ plan.md</sub>"]:::synth
    C["/check<br/><sub>completeness · sequencing · risk<br/>scope-discipline · testability</sub>"]:::gate
    JS3["Judge · Dedupe · Synth<br/><sub>→ check.md</sub>"]:::synth
    B["/build<br/><sub>parallel execute</sub>"]:::execute
    W["/wrap"]:::wrap

    K --> S --> SR --> JS1 --> P --> JS2 --> C --> JS3 --> B --> W

    SP["Superpowers<br/><sub>TDD · verification</sub>"]:::side
    CX["Codex<br/><sub>adversarial review</sub>"]:::accent
    KL["Knowledge layer<br/><sub>graphify · wiki</sub>"]:::side
    PM["Persona Metrics<br/><sub>load-bearing · silent ·<br/>survival rates</sub>"]:::metrics

    SP -.-> B
    CX -.-> SR
    CX -.-> C
    CX -.-> B
    W -.-> KL
    JS1 ==records==> PM
    JS2 ==> PM
    JS3 ==> PM
    W ==surfaces drift==> PM

    classDef setup fill:#bfdbfe,stroke:#1e3a8a,color:#1e3a8a,stroke-width:2px
    classDef define fill:#5eead4,stroke:#0f766e,color:#134e4a,stroke-width:2px
    classDef review fill:#fdba74,stroke:#9a3412,color:#7c2d12,stroke-width:2px
    classDef plan fill:#c4b5fd,stroke:#5b21b6,color:#4c1d95,stroke-width:2px
    classDef gate fill:#fda4af,stroke:#9f1239,color:#881337,stroke-width:2px
    classDef execute fill:#86efac,stroke:#15803d,color:#14532d,stroke-width:2px
    classDef wrap fill:#d4d4d8,stroke:#3f3f46,color:#27272a,stroke-width:2px
    classDef synth fill:#7dd3fc,stroke:#075985,color:#0c4a6e,stroke-width:2px
    classDef side fill:#e2e8f0,stroke:#475569,color:#1e293b,stroke-width:2px,stroke-dasharray: 4 3
    classDef accent fill:#fde68a,stroke:#92400e,color:#78350f,stroke-width:2px,stroke-dasharray: 4 3
    classDef metrics fill:#a78bfa,stroke:#5b21b6,color:#2e1065,stroke-width:3px
```

```
/kickoff → /spec → /spec-review → /plan → /check → /build
           define    6 PRD        6 design  5 plan   execute
           (Q&A)     agents       agents    agents   (parallel)
```

### The knowledge loop

`/wrap` doesn't just end a session — it compiles what you learned into stores that **the next session reads from**. Every `/spec` and `/kickoff` starts smarter than the last.

```mermaid
flowchart LR
    subgraph SN["Session N"]
      direction TB
      W["/wrap<br/><sub>distill · capture · index</sub>"]:::wrap
    end

    W --> G[("graphify graph<br/><sub>code structure ·<br/>god nodes</sub>")]:::store
    W --> WIKI[("Obsidian wiki<br/><sub>distilled<br/>knowledge pages</sub>")]:::store
    W --> MEM[("CLAUDE.md<br/>+ auto-memory<br/><sub>preferences ·<br/>decisions</sub>")]:::store
    W --> RAW[("_raw/<br/><sub>cheap<br/>captures</sub>")]:::store

    RAW -. wiki-ingest at next /wrap .-> WIKI

    subgraph SN1["Session N+1, N+2, ..."]
      direction TB
      S["/spec  ·  /kickoff<br/><sub>starts with full prior context</sub>"]:::define
    end

    G -. /graphify query .-> S
    WIKI -. wiki-query · &quot;what do I know about X&quot; .-> S
    MEM -. auto-loaded at session start .-> S

    classDef wrap fill:#3f3f46,stroke:#d4d4d8,color:#fff
    classDef define fill:#0f766e,stroke:#5eead4,color:#fff
    classDef store fill:#1e293b,stroke:#7c9cff,color:#e7e9ee
```

**Compile, don't retrieve.** Capture is cheap during the session (`"capture this: X"` → `_raw/`). Distillation happens once at `/wrap`. Reads at the start of the next session are free — the wiki is already structured, the graph is already built, memory is already loaded.

| Command | What It Does | Agents |
|---------|-------------|--------|
| `/kickoff` | One-time project init — scans repo, drafts constitution, selects agent roster | - |
| `/spec` | Confidence-tracked Q&A — writes `spec.md` (falls back to session roster if no constitution) | Interactive |
| `/spec-review` | Parallel PRD review — gaps, risks, ambiguity; + Codex adversarial pass (optional) | 6 reviewers |
| `/plan` | Architecture + implementation design | 6 designers |
| `/check` | Last gate before code — validates the plan; + Codex adversarial pass (optional) | 5 validators |
| `/build` | Parallel execution with verification discipline; + Codex implementation review (optional) | Superpowers |
| `/autorun` | Headless overnight pipeline — queues a spec and drives all 8 stages unattended via `autorun start` | Shell |
| `/flow` | Displays workflow reference card | - |
| `/wrap` | Session wrap-up — summary, learnings, git loose ends | - |

<details>
<summary><strong>The full <code>/flow</code> reference card</strong> — click to expand</summary>

```text
╔══════════════════════════════════════════════════════════════╗
║                    SESSION WORKFLOW                          ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║  PROJECT SETUP (once per project)                            ║
║  /kickoff  →  constitution + agent roster                    ║
║                                                              ║
║  FEATURE (full pipeline)                                     ║
║  /spec  →  /spec-review  →  /plan  →  /check  →  /build      ║
║   define    6 PRD          6 design   5 plan     execute     ║
║   (Q&A)     agents         agents     agents     (parallel)  ║
║  + firecrawl (research) · context7 (API docs)                ║
║  + codex adversarial review at spec-review, check, build     ║
║    (optional — silent skip if not set up)                    ║
║                                                              ║
║  WORK-SIZE SCALING                                           ║
║  Bug fix:      describe it → fix it → verify                 ║
║  Small change: /spec (quick) → /build                        ║
║  Feature:      full pipeline above                           ║
║  V2/Rework:    revise existing spec → full pipeline          ║
║                                                              ║
║  PARALLEL WORK                                               ║
║  "work on X, Y, and Z in parallel"                           ║
║    → Each dispatched to a subagent                           ║
║                                                              ║
║  IN-SESSION DISCIPLINE                      [Superpowers]    ║
║  → systematic-debugging · verification-before-done           ║
║  → requesting-code-review · ralph-loop (micro-iteration)     ║
║                                                              ║
║  CODE REVIEW                                                 ║
║  Quick:  superpowers requesting-code-review                  ║
║  PR:     /code-review plugin                                 ║
║  Full:   9 parallel code-review personas                     ║
║                                                              ║
║  ARTIFACTS                                                   ║
║  docs/specs/constitution.md     (project principles)         ║
║  docs/specs/<feature>/spec.md   (living spec)                ║
║  docs/specs/<feature>/review.md (PRD review findings)        ║
║  docs/specs/<feature>/plan.md   (implementation plan)        ║
║  docs/specs/<feature>/check.md  (gap checkpoint)             ║
║                                                              ║
║  KNOWLEDGE LAYER                   [graphify + obsidian]     ║
║  Fires automagically at /wrap — no typing, no friction:      ║
║    _raw/ → wiki pages           (wiki-ingest)                ║
║    session → projects/<name>/   (wiki-update)                ║
║    graph export + lint          (wiki-export · wiki-lint)    ║
║    graphify digest → _raw/      (silent arch snapshot)       ║
║  Manual (rare):                                              ║
║    /graphify [path]    build code knowledge graph            ║
║    /graphify query "Q" graph traversal answer                ║
║    "what do I know about X"  wiki-query                      ║
║    "capture this: X"         wiki-capture → _raw/            ║
║  Compile, don't retrieve. Capture cheap, distill at /wrap.   ║
║                                                              ║
║  SESSION END                                                 ║
║  /wrap → summary · learnings · knowledge flush · git ends    ║
║                                                              ║
╠══════════════════════════════════════════════════════════════╣
║  AGENTS: review(6) plan(6) check(5) code-review(9)           ║
║  + judge · synthesis · domain agents                         ║
║                                                              ║
║  PLUGINS                                                     ║
║  Always-on:  superpowers · context7                          ║
║  On-demand:  firecrawl · code-review · ralph-loop            ║
║              playwright                                      ║
║  Periodic:   claude-md-management · skill-creator            ║
║              claude-code-setup                               ║
║  Optional:   codex — adversarial review at spec-review,      ║
║              /check, /build (silent skip if not set up)      ║
║                                                              ║
║  Superpowers: in-session execution discipline                ║
║  Plugins: specialized capabilities                           ║
║  You say WHAT. Claude handles HOW.                           ║
╚══════════════════════════════════════════════════════════════╝
```

</details>

## Agent Roster (37 personas)

The repo ships **37 personas**: 28 always-available pipeline agents + 9 domain agents.
A single session calls **only the subset relevant to the current phase** — never all 37 at once. Each `/spec-review`, `/plan`, `/check`, or `/build` invokes its own slice.

### Pipeline agents (28) — always available

| Stage | Count | Personas |
|-------|-------|----------|
| Review (`/spec-review`) | 6 | Requirements · Gaps · Ambiguity · Feasibility · Scope · Stakeholders |
| Plan (`/plan`) | 6 | API · Data Model · UX · Scalability · Security · Integration |
| Check (`/check`) | 5 | Completeness · Sequencing · Risk · Scope Discipline · Testability |
| Code review (full mode) | 9 | Correctness · Dependency · Design Quality · Documentation · Performance · Resilience · Security · Test Quality · Wiring |
| Synthesis layer | 2 | Judge (quality scoring) · Synthesis (multi-agent consolidation) — used by `/spec-review`, `/plan`, `/check` |

### Domain agents (9) — loaded conditionally at `/kickoff`

`domains/` ships extra personas that are **not** globally active. `install.sh` symlinks them into `~/.claude/domain-agents/<domain>/`, and `/kickoff` inspects the target project and copies only the relevant ones into `<project>/.claude/agents/`.

- **mobile/** — 6 iOS agents: swift-mentor, beta-feedback-triage, test-writer, feature-flag-manager, release-notes-writer, performance-advisor
- **games/** — 3 game-dev agents: game-state-reviewer, swiftui-scene-builder, accessibility-guardian

Projects can also carry their own agents in `<project>/.claude/agents/` (e.g. AuthTools adds 5 auth-specific agents from a separate private repo, bringing that project's roster to 42).

## Install

```bash
git clone <this-repo> ~/Projects/claude-workflow
cd ~/Projects/claude-workflow
./install.sh
```

The installer symlinks commands, personas, templates, and settings into `~/.claude/`, then offers to install plugins.

## Plugin Dependencies

See [plugins.md](plugins.md) for the full list. Quick install:

```bash
# Required
claude plugins install superpowers context7

# Recommended
claude plugins install firecrawl code-review ralph-loop playwright
```

**Optional — Codex multi-model review:** `/spec-review`, `/check`, and `/build` can call Codex as an adversarial reviewer. It silently skips if Codex isn't configured. See [plugins.md](plugins.md) for setup.

## Artifacts

The pipeline writes persistent spec artifacts to each project:

```
docs/specs/constitution.md          # Project principles (from /kickoff)
docs/specs/<feature>/spec.md        # Living spec (from /spec)
docs/specs/<feature>/review.md      # PRD review findings (from /spec-review)
docs/specs/<feature>/plan.md        # Implementation plan (from /plan)
docs/specs/<feature>/check.md       # Gap checkpoint (from /check)
```

### Persona Metrics (v0.2.0+)

Every multi-agent gate (`/spec-review`, `/plan`, `/check`) emits structured measurement artifacts under `docs/specs/<feature>/<stage>/`:

```
spec-review/
  source.spec.md          # snapshot of spec.md at /spec-review start
  raw/<persona>.md        # one file per reviewer (incl. codex-adversary if applicable)
  findings.jsonl          # clustered findings, persona-attributed
  participation.jsonl     # every persona that ran (with status: ok/failed/timeout)
  run.json                # run_id, prompt_version, hashes, status
  survival.jsonl          # written at next stage's Phase 0 — judges what survived revision
```

`/wrap-insights` reads these to render per-persona `load_bearing_rate`, `survival_rate`, and `silent_rate` across a rolling 10-feature window. The pipeline becomes a measurement loop — over time, drift signals which personas are earning their slot.

**Privacy for adopters:** these artifacts contain verbatim review prose (`body` field) that may be sensitive. Adopter installs default to **opt-in-to-commit** (`PERSONA_METRICS_GITIGNORE=1` is set automatically; metrics paths are appended to your `.gitignore`). To commit metrics intentionally, set `PERSONA_METRICS_GITIGNORE=0` before running `install.sh`. `claude-workflow`'s own repo overrides this default via name-detection in the installer.

## Customization

1. **Add project-specific agents** — create personas at `/kickoff` via the constitution template
2. **Add domain extensions** — drop agent `.md` files in `domains/<your-domain>/agents/`
3. **Personalize** — create a `~/CLAUDE.md` with your own context (role, projects, preferences)

## Structure

```
claude-workflow/
├── install.sh                  # Installer — symlinks everything into ~/.claude/
├── plugins.md                  # Plugin dependency manifest
├── commands/                   # 8 pipeline commands
├── personas/                   # 28 agent personas (26 stage + judge, synthesis)
│   ├── check/       (5)
│   ├── code-review/ (9)
│   ├── plan/        (6)
│   └── review/      (6)
├── templates/
│   ├── constitution.md         # Project constitution template
│   └── repo-signals.md         # Domain-detection reference for /kickoff + /spec
├── settings/
│   └── settings.json           # Base settings (permissions, plugins)
├── scripts/
│   ├── session-cost.py         # Per-session cost reporter (used by /wrap)
│   └── doctor.sh               # Diagnostic report → auto-files GitHub Issue
└── domains/                    # Domain-specific extensions
    ├── mobile/                 # iOS development
    └── games/                  # Game development
```
