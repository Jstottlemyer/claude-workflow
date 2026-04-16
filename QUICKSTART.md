# Quick Start

A hands-on 10-minute setup for the Claude workflow pipeline. Assumes you're on macOS with Claude Code installed.

## Prerequisites

- **Claude Code CLI** — https://claude.com/claude-code (install it; first `claude` run walks you through its own sign-in)
- **git** — for cloning
- **bash** — macOS ships 3.2; the installer works with it
- **gh** (GitHub CLI) — `brew install gh` then `gh auth login`. Needed to clone this private repo and to open PRs later.
- **python3** — `brew install python`. Used by the session-cost script.

The `install.sh` will warn if any of these are missing but won't block — install them when prompted or beforehand.

## 1. Before you clone

This repo is private, and Justin added you as a collaborator. Two things before the clone will work:

**a) Accept the GitHub invitation.**  Check your email for a GitHub invite from `Jstottlemyer`, or visit https://github.com/Jstottlemyer/claude-workflow/invitations and click Accept.

**b) Authenticate the GitHub CLI.**  Once-per-machine setup:
```bash
brew install gh       # skip if you already have it
gh auth login         # choose: GitHub.com → HTTPS → Login with a web browser
```
This makes `git clone` and `git pull` "just work" for private repos.

## 2. Clone + install

```bash
git clone https://github.com/Jstottlemyer/claude-workflow.git ~/Projects/claude-workflow
cd ~/Projects/claude-workflow
./install.sh
```

The installer symlinks everything from this repo into `~/.claude/`. It backs up any existing file to `<file>.bak` before linking, so it's safe to re-run.

### What gets installed

| Target | From |
|---|---|
| `~/.claude/commands/*.md` (8 pipeline commands) | `commands/` |
| `~/.claude/personas/{review,plan,check,code-review}/*.md` (27 agents) | `personas/` |
| `~/.claude/templates/*.md` (constitution, repo-signals) | `templates/` |
| `~/.claude/settings.json` (base permissions) | `settings/settings.json` |
| `~/.claude/scripts/*.{py,sh}` (session helpers) | `scripts/` |

The installer will also offer to install required plugins (`superpowers`, `context7`) and recommended ones (`firecrawl`, `code-review`, `ralph-loop`, `playwright`). Say yes unless you have a reason not to.

## 3. Add your personal layer

The pipeline is shared (checked into this repo), but **your personal context is not**. Create `~/CLAUDE.md` with things like:

```markdown
# My Claude Config

## Who I Am
- [Your role, what you're building]

## Collaboration Preferences
- [e.g., "One question at a time", "Show tradeoffs before committing to an approach"]

## Projects
- [Short pointer to each project you work on]
```

This file loads automatically in every Claude Code session and is purely for you — it's not shared with the team.

## 4. Verify install

Open a fresh terminal, `cd` into any project (or a scratch dir), and run Claude:

```bash
claude
```

First run: Claude Code walks you through its own browser sign-in (Anthropic account — separate from GitHub). Once you're in, try:
```
/flow
```

You should see the workflow reference card. If the command is unknown, the symlink didn't take — re-run `./install.sh` from the workflow repo.

## 5. Run the pipeline on a real project

Pick a small project you have lying around:

```bash
cd ~/Projects/<some-project>
claude
```

Then in Claude Code:
```
/kickoff
```

`/kickoff` will scan the repo for stack signals (Swift, Go, TS, Python, MCP, plugin...) and propose a domain-specific agent roster. Confirm or adjust, and it writes `docs/specs/constitution.md` + installs any domain agents into `.claude/agents/`.

Next, for your first feature or change:
```
/spec <one-sentence description>
```

This runs a confidence-tracked Q&A, writes `docs/specs/<feature>/spec.md`, and kicks off the rest of the pipeline when you're ready (`/review` → `/plan` → `/check` → `/build`).

End every session with:
```
/wrap
```

Captures session summary, triages learnings, checks git loose ends, and audits permissions.

## 6. The pipeline at a glance

```
/kickoff → /spec → /review → /plan → /check → /build
           define    6 PRD     6 design  5 plan   execute
           (Q&A)     agents    agents    agents   (parallel)
```

Work scales — you don't need the full pipeline for a bug fix:

| Work Size | What to run |
|---|---|
| Bug fix | Describe it, fix it, verify |
| Small change | `/spec` then `/build` |
| Feature | Full pipeline |
| V2 / rework | Revise existing spec, then full pipeline |

## Troubleshooting

**`install.sh` errored on symlinks** — you probably have existing regular files at the target path. The installer backs them up to `.bak` first; check if the `.bak` files are what you expected before re-running.

**A command isn't recognized** — slash commands live in `~/.claude/commands/`. Confirm it's a symlink pointing back to this repo:
```bash
ls -la ~/.claude/commands/
```
If entries are regular files (not symlinks), re-run `./install.sh`.

**Want to experiment without breaking your main install** — clone to a different path and just edit files locally without running `install.sh`. Use your own CLAUDE.md to point to your sandbox.

**Plugin install failed** — plugins require Claude Code CLI auth and a working Anthropic account. Run `claude plugins install superpowers context7` directly; see error output.

## Going deeper

- `README.md` — repo structure, full pipeline reference
- `plugins.md` — plugin dependencies + what each does
- `domains/mobile/CLAUDE.md` and `domains/games/CLAUDE.md` — example domain configs
- `docs/specs/example-feature/spec.md` — a real spec artifact showing the output shape

## Staying in sync

This repo is the source of truth. When Justin pushes changes, pull and re-run install:

```bash
cd ~/Projects/claude-workflow
git pull
./install.sh
```

Re-running the installer is idempotent — existing symlinks get refreshed, real files get backed up to `.bak`.
