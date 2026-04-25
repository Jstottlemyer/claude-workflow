# Plugin Dependencies

This pipeline requires plugins from the `claude-plugins-official` marketplace.

## Required (Pipeline Won't Work Without These)

| Plugin | Purpose | Install |
|--------|---------|---------|
| **superpowers** | Execution discipline: debugging, verification, code review, worktrees | `claude plugins install superpowers` |
| **context7** | Library/framework documentation fetching | `claude plugins install context7` |

## Recommended (Full Pipeline Experience)

| Plugin | Purpose | Install |
|--------|---------|---------|
| **firecrawl** | Web scraping, research, competitive analysis | `claude plugins install firecrawl` |
| **code-review** | GitHub PR review | `claude plugins install code-review` |
| **ralph-loop** | Micro-iteration loops (repeated task execution) | `claude plugins install ralph-loop` |
| **playwright** | Browser automation, visual testing | `claude plugins install playwright` |

## Periodic (Maintenance & Optimization)

| Plugin | Purpose | Install |
|--------|---------|---------|
| **claude-md-management** | CLAUDE.md auditing and improvement | `claude plugins install claude-md-management` |
| **skill-creator** | Skill creation and optimization | `claude plugins install skill-creator` |
| **claude-code-setup** | Automation recommendations | `claude plugins install claude-code-setup` |

## Quick Install (All Required + Recommended)

```bash
claude plugins install superpowers context7 firecrawl code-review ralph-loop playwright
```

## Plugin Tiers

- **Always-on:** superpowers, context7 — enabled in settings.json, active every session
- **On-demand:** firecrawl, code-review, ralph-loop, playwright — invoke when needed
- **Periodic:** claude-md-management, skill-creator, claude-code-setup — run occasionally for maintenance

## Multi-model Review (Optional)

The pipeline supports Codex as an adversarial reviewer at `/spec-review`, `/check`, and `/build`. It runs silently — if Codex is not installed or not authenticated, those phases skip it without error.

To enable:

```bash
# 1. Add the Codex plugin from the OpenAI marketplace
/plugin marketplace add openai/codex-plugin-cc
/plugin install codex@openai-codex
/reload-plugins

# 2. Install the Codex CLI and authenticate (browser OAuth — ChatGPT account or API key)
/codex:setup          # offers to run npm install -g @openai/codex if missing
!codex login          # opens browser → sign in with ChatGPT account
/codex:setup          # confirm ready: true
```

Once authenticated, Codex activates automatically in the pipeline. No further configuration needed. Authentication persists across sessions via your local ChatGPT credential store.

**Note:** Codex uses your ChatGPT usage limits. The pipeline calls it as a read-only reviewer — it never edits files.

## Important

- DO NOT modify files in `~/.claude/plugins/cache/` — they get overwritten on updates
- Superpowers handles **execution discipline** (debugging, verification) — NOT planning/review (the pipeline commands handle that)
