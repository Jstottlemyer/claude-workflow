# claude-workflow — Repo-level Instructions for Claude

Personal-tooling repo. Holds commands, personas, templates, and cross-project
reference docs for Justin's 8-command pipeline (`/kickoff → /spec → /review
→ /plan → /check → /build`, plus `/flow` and `/wrap`).

Apply in addition to user-level `~/CLAUDE.md`.

## Built-in Claude Code commands

`/plan` is the canonical planner — it stays in the terminal and writes `docs/specs/<feature>/plan.md`. Avoid `/ultraplan` for pipeline work; it dispatches a remote browser session and produces no local artifact. `/insights` is opt-in via `/wrap insights` (measurement mode); `/powerup` is ad-hoc educational and not wired into any flow.

## graphify

This project has a graphify knowledge graph at graphify-out/.

Rules:
- Before answering architecture or codebase questions, read graphify-out/GRAPH_REPORT.md for god nodes and community structure
- If graphify-out/wiki/index.md exists, navigate it instead of reading raw files
- After modifying code files in this session, run `graphify update .` to keep the graph current (AST-only, no API cost)
