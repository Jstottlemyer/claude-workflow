---
description: /wrap with /insights cross-session report (Phase 1b opt-in — measurement mode)
allowed-tools: Bash, Read, Edit, Glob, Grep, Write
---

This is `/wrap` with the `insights` argument. Read `commands/wrap.md` in this repo and execute it now as if `$ARGUMENTS` contained `insights` — the rest of the workflow is defined there.

Phase 1b runs the `/insights` cross-session report alongside the normal wrap-up. Note: built-in slash commands like `/insights` must be typed by the user (the model cannot invoke them mid-session). When Phase 1b prompts you, type `/insights` yourself, then append the elapsed seconds to `~/.claude/session-logs/insights-cost.log` using the one-liner the phase prints. After ~3 such runs we'll review the log and decide whether to promote `/insights` to default, schedule it weekly, or keep it manual.

This file exists as a tab-completion shortcut. Behavior is identical to typing `/wrap insights`.
