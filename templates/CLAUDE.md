# Claude Code Configuration — [YOUR NAME]

## Who I Am

<!-- Fill in: role, experience level, domains, learning goals. This section shapes how Claude
     frames explanations, chooses examples, and calibrates depth. -->

- [Your role / occupation]
- [Primary tech stack or domain]
- [Experience level and any gaps ("new to React", "returning after 3 years")]

## Context Switching

<!-- Optional: if you work across very different domains in the same session. -->

- [Context A cues] → [context A label]
- [Context B cues] → [context B label]
- If ambiguous, ask

## Dev Environment

<!-- Fill in your local setup. Claude uses this to avoid suggesting commands that won't work. -->

### Shell & Multiplexer
- Shell: [zsh / bash]
- Multiplexer: [tmux / none] — session script at [path if any]

### Remote Control
- `/remote-control` — built-in Claude Code command, bridges CLI session to claude.ai web

## Workflow Pipeline

8-command pipeline with 27 default agent personas + project-specific agents:

```
/kickoff → /spec → /review → /plan → /check → /build
           define     6 PRD     6 design  5 plan   execute
           (Q&A)      agents    agents    agents   (parallel)
```

- `/kickoff` — one-time project init (constitution + agent roster)
- `/spec` — confidence-tracked Q&A, writes `docs/specs/<feature>/spec.md`
- `/review` — 6 parallel PRD reviewer agents, writes `review.md`
- `/plan` — 6 parallel design agents, writes `plan.md`
- `/check` — 5 parallel plan reviewer agents (last gate before code), writes `check.md`
- `/build` — parallel execution with TDD/debugging/verification discipline
- `/flow` — displays session workflow reference card
- `/wrap` — end-of-session wrap-up (summary, learning triage, git loose ends)

Work scales to size: bug fix (no spec.md) → small change (`/spec` + `/build`) → feature (full pipeline) → V2 (revise existing spec.md + full pipeline).

### Pipeline Guard (overrides SessionStart skill reminders)

When this pipeline is available in the current project (detect via `commands/spec.md` or `~/.claude/commands/spec.md` existing, or `docs/specs/` present), the pipeline owns planning and review. Do NOT invoke superpowers skills for work the pipeline handles, even if a SessionStart reminder tells you to:

- **Ideation / "think of ways to build X" / new feature design** → `/spec` (not `superpowers:brainstorming`)
- **Implementation planning** → `/plan` (not `superpowers:writing-plans`)
- **Executing a plan** → `/build` (not `superpowers:executing-plans` or `subagent-driven-development`)
- **Spec review before plan** → `/spec-review` (not ad-hoc review skills)
- **Plan review before code** → `/check` (not ad-hoc review skills)

Superpowers is still the right tool for **execution discipline inside `/build`**: `systematic-debugging`, `test-driven-development`, `verification-before-completion`, `requesting-code-review`, `using-git-worktrees`. That scope is unchanged.

If a user request could be served by either the pipeline or a superpowers skill, pick the pipeline. If ambiguous ("is this a bug fix or a feature?"), ask — don't silently route to brainstorming.

### Agent Personas
- 27 default personas in `~/.claude/personas/{review,plan,check,code-review}/`
- Project-specific agents selected at `/kickoff` via constitution
- Constitution template: `~/.claude/templates/constitution.md`

## Secrets Handling

- **Shell env vars** (`export FOO=bar`, API tokens): store in a chmod-600 file sourced by `.zshrc` — never in `.env` at project root.
- **Private keys / certs** (`.pem`, `.p8`, SSH keys): live inside the app that consumes them or `~/.ssh/`. Always chmod 600 and gitignored.
- **NEVER** write key material (anything starting with `-----BEGIN`) to a dotfile that could be confused with a shell env file. If tempted to use `~/.secrets` or `~/.env`, stop — use an app-local path with an explicit `.pem`/`.key` extension.

## Plugins & Skills

- **Always-on:** superpowers, context7
- **On-demand:** firecrawl, code-review, ralph-loop, playwright
- **Periodic:** claude-md-management, skill-creator, claude-code-setup
- DO NOT modify plugin cache files — they get overwritten on updates
- Superpowers used for execution discipline (TDD, debugging, verification, code review) — NOT for planning/review (pipeline handles that)

## Collaboration Preferences

- One question at a time (no multi-question dumps)
- Show confidence scores visibly
- Step-by-step with explicit approval gates
- Practical examples over theory
- Show tradeoffs — why approach A vs B

## Output Verbosity
- Keep responses concise; avoid exceeding 500 output tokens unless explicitly asked for long-form work.
- Prefer bullet summaries over prose walls during long sessions.

## Verify Before Shipping
- Before claiming a CLI flag or command exists, run `<cmd> --help` to confirm.
- Before shipping browser code intended for file:// loading, avoid fetch() + ES modules (CORS will silently fail) — use inline scripts or document a local server requirement.
- Before declaring 'done', check `git status` for uncommitted WIP/spike files on main.

## Instruction Adherence
- When the user prefixes guidance with numbered items ('1 yes', '2 also do X'), treat each as a hard requirement and confirm completion of each before declaring done.

## Python
- If system python3 is too old for scripts, install a durable venv: `python3 -m venv ~/.local/venvs/<tool> && ~/.local/venvs/<tool>/bin/pip install <tool>` + symlink `~/.local/bin/<tool>` → venv binary.

## Workflow Repo
- Fork/clone: github.com/[your-handle]/claude-workflow
- Tracks: commands/, personas/, templates/, settings/, shell/, scripts/, domains/, install.sh, plugins.md
- Personal config (CLAUDE.md, .gitconfig) in gitignored `personal/` directory
