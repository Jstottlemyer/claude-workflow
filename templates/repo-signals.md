# Repo Signals — Domain Detection Reference

Used by `/kickoff` (initial setup) and `/spec` (when no constitution exists) to detect the project domain from files in the current working directory, so agent rosters can be proposed from evidence instead of Q&A.

## Signal Scan (run in cwd)

```bash
# Package / project manifests
ls Package.swift project.yml Podfile Package.resolved *.xcodeproj *.xcworkspace 2>/dev/null
ls go.mod go.sum 2>/dev/null
ls package.json tsconfig.json pnpm-lock.yaml yarn.lock bun.lockb 2>/dev/null
ls Cargo.toml 2>/dev/null
ls pyproject.toml requirements.txt setup.py Pipfile 2>/dev/null
ls build.gradle pom.xml settings.gradle build.gradle.kts 2>/dev/null
ls Gemfile 2>/dev/null
ls plugin.json manifest.json SKILL.md 2>/dev/null

# Language files (sample to confirm mix)
find . -maxdepth 3 -type f \( -name '*.swift' -o -name '*.go' -o -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.py' -o -name '*.rs' -o -name '*.kt' -o -name '*.java' \) -not -path '*/node_modules/*' -not -path '*/.build/*' -not -path '*/target/*' 2>/dev/null | head -20

# iOS / Xcode specifics
find . -maxdepth 3 -name 'Info.plist' -o -name 'AppDelegate.swift' -o -name '*App.swift' 2>/dev/null | head -5

# Game engine signals
grep -l 'SpriteKit\|SceneKit\|RealityKit\|GameplayKit' *.swift Sources/**/*.swift 2>/dev/null | head -3

# MCP / plugin / skill signals
[ -f plugin.json ] && echo "MCP/plugin marker: plugin.json"
[ -f SKILL.md ] && echo "Skill marker: SKILL.md"
grep -l '"@modelcontextprotocol"\|"mcp-server"' package.json 2>/dev/null

# README voice / stack
head -40 README.md 2>/dev/null

# Recent commit themes
git log --oneline -20 2>/dev/null
```

## Domain Detection Matrix

| Evidence | Inferred Domain | Propose Agents |
|---|---|---|
| `Package.swift` + `*App.swift` + SwiftUI imports | **iOS/mobile** | `domains/mobile/agents/*` — 6 agents |
| Mobile + `SpriteKit`/`SceneKit`/`RealityKit` in sources | **iOS/games** | `domains/mobile/*` + `domains/games/*` — 9 agents |
| `Package.swift` + `bin/` + CLI entry (`@main` in CLI target) | **Swift CLI** | Consider AuthTools agents (`cli-wrapper-ergonomics`, `keychain-safety-reviewer`) |
| `plugin.json` or `SKILL.md` or `commands/*.md` + `agents/*.md` | **Claude plugin/skill** | `skill-plugin-specialist` + `mcp-protocol-expert` if MCP |
| `go.mod` + `cmd/` | **Go service/CLI** | No domain roster yet — ask user |
| `package.json` + `"next"` or `"react"` in deps | **Web frontend** | No domain roster yet — ask user |
| `package.json` + `"express"`/`"fastify"`/`"@nestjs/*"` | **Node backend** | No domain roster yet — ask user |
| `pyproject.toml` + `fastapi`/`flask`/`django` | **Python web** | No domain roster yet — ask user |
| MCP markers (`"@modelcontextprotocol"`, `plugin.json` with `mcpServers`) | **MCP server** | `mcp-protocol-expert` + `oauth-flow-auditor` if auth involved |

## Agent Roster Sources

- **Pipeline defaults (always included — 28):** `~/.claude/personas/{review,plan,check,code-review}/*.md` + `~/.claude/personas/{judge,synthesis}.md`
- **Domain add-ons (installed globally by install.sh at `~/.claude/domain-agents/`):**
  - `mobile/` — 6 agents: beta-feedback-triage, feature-flag-manager, performance-advisor, release-notes-writer, swift-mentor, test-writer
  - `games/` — 3 agents: accessibility-guardian, game-state-reviewer, swiftui-scene-builder
- **Project-specific (AuthTools pattern):** custom agents live in `<project>/.claude/agents/*.md` — added per-project, not globally installed. AuthTools ships 5: cli-wrapper-ergonomics, keychain-safety-reviewer, mcp-protocol-expert, oauth-flow-auditor, skill-plugin-specialist

## Presentation Format

After scanning, present one concise block:

```
=== Repo Signals ===
Stack: [detected stack in one line]
Signals: [bullet list of concrete evidence — file paths, deps, commit themes]
Proposed domain: [mobile / games / cli / mcp / plugin / unknown]

Proposed roster additions (on top of 27 defaults):
- [agent-name] ([source]) — [one-line why]
- ...

Confirm? (yes / adjust / start over)
```

## Guardrails

- **Evidence > inference.** If you can't find a concrete file/dep, say "unknown domain" rather than guessing.
- **One round of confirmation.** Show evidence + proposal once; accept "yes", take corrections, or fall back to Q&A on "start over".
- **Hybrid OK.** Mobile + games projects combine both rosters. CLI + MCP wrapper projects combine AuthTools relevant agents.
- **Session-scope vs persistent.** `/kickoff` writes the roster into `docs/specs/constitution.md` (persistent). `/spec` without a constitution writes the roster into the spec's frontmatter as a session-scope roster (not saved as a constitution).
