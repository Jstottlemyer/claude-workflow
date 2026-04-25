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
    SR["/spec-review<br/><sub>6 PRD agents</sub>"]:::review
    P["/plan<br/><sub>6 design agents</sub>"]:::plan
    C["/check<br/><sub>5 plan agents</sub>"]:::gate
    B["/build<br/><sub>parallel execute</sub>"]:::execute
    W["/wrap<br/><sub>summary · learnings ·<br/>knowledge flush</sub>"]:::wrap

    K --> S --> SR --> P --> C --> B --> W

    SP["Superpowers<br/><sub>TDD · debugging ·<br/>verification</sub>"]:::side
    KL["Knowledge layer<br/><sub>graphify · obsidian wiki</sub>"]:::side
    SP -.in-session.-> B
    W -.compiles.-> KL

    classDef setup fill:#1e3a8a,stroke:#60a5fa,color:#fff
    classDef define fill:#0f766e,stroke:#5eead4,color:#fff
    classDef review fill:#7c2d12,stroke:#fdba74,color:#fff
    classDef plan fill:#5b21b6,stroke:#c4b5fd,color:#fff
    classDef gate fill:#9f1239,stroke:#fda4af,color:#fff
    classDef execute fill:#166534,stroke:#86efac,color:#fff
    classDef wrap fill:#3f3f46,stroke:#d4d4d8,color:#fff
    classDef side fill:#18181b,stroke:#71717a,color:#a1a1aa,stroke-dasharray: 4 3
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
| `/spec-review` | Parallel PRD review — finds gaps, risks, ambiguity | 6 reviewers |
| `/plan` | Architecture + implementation design | 6 designers |
| `/check` | Last gate before code — validates the plan | 5 validators |
| `/build` | Parallel execution with verification discipline | Superpowers |
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

## Artifacts

The pipeline writes persistent spec artifacts to each project:

```
docs/specs/constitution.md          # Project principles (from /kickoff)
docs/specs/<feature>/spec.md        # Living spec (from /spec)
docs/specs/<feature>/review.md      # PRD review findings (from /spec-review)
docs/specs/<feature>/plan.md        # Implementation plan (from /plan)
docs/specs/<feature>/check.md       # Gap checkpoint (from /check)
```

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
