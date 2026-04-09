# Claude Workflow Pipeline

An 8-command pipeline for Claude Code that adds structured planning, multi-agent review, and execution discipline to any project.

## What This Is

A complete workflow system that scales to the size of the work:

| Work Size | Pipeline |
|-----------|----------|
| Bug fix | Describe it, fix it, verify |
| Small change | `/brainstorm` (quick) then `/build` |
| Feature | Full pipeline: `/kickoff` through `/build` |
| V2 / Rework | Revise existing spec, then full pipeline |

## The Pipeline

```
/kickoff → /brainstorm → /review → /plan → /check → /build
              define       6 PRD     6 design  5 plan   execute
              (Q&A)        agents    agents    agents   (parallel)
```

| Command | What It Does | Agents |
|---------|-------------|--------|
| `/kickoff` | One-time project init — creates constitution + selects agent roster | - |
| `/brainstorm` | Confidence-tracked Q&A — writes `spec.md` | Interactive |
| `/review` | Parallel PRD review — finds gaps, risks, ambiguity | 6 reviewers |
| `/plan` | Architecture + implementation design | 6 designers |
| `/check` | Last gate before code — validates the plan | 5 validators |
| `/build` | Parallel execution with TDD discipline | Superpowers |
| `/flow` | Displays workflow reference card | - |
| `/wrap` | Session wrap-up — summary, learnings, git loose ends | - |

## Agent Personas (27 Default)

### Review Stage (6)
Requirements, Gaps, Ambiguity, Feasibility, Scope, Stakeholders

### Plan Stage (6)
API, Data Model, UX, Scalability, Security, Integration

### Check Stage (5)
Completeness, Sequencing, Risk, Scope Discipline, Testability

### Code Review (10)
Correctness, Security, Performance, Resilience, Wiring, Test Quality, Style, Elegance, Smells, Commit Discipline

## Domain Extensions

The `domains/` directory contains domain-specific agents and commands:

- **mobile/** — 6 iOS development agents (Swift mentor, beta triage, test writer, feature flags, release notes, performance)
- **games/** — 6 game dev agents (game state, scene builder, accessibility, Swift mentor, performance, test writer) + 3 custom commands

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
docs/specs/<feature>/spec.md        # Living spec (from /brainstorm)
docs/specs/<feature>/review.md      # PRD review findings (from /review)
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
├── personas/                   # 27 universal agent personas
│   ├── check/       (5)
│   ├── code-review/ (10)
│   ├── plan/        (6)
│   └── review/      (6)
├── templates/
│   └── constitution.md         # Project constitution template
├── settings/
│   └── settings.json           # Base settings (permissions, plugins)
└── domains/                    # Domain-specific extensions
    ├── mobile/                 # iOS development
    └── games/                  # Game development
```
