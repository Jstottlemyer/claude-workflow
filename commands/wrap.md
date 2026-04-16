---
description: End-of-session wrap-up — summarize work, triage learnings to CLAUDE.md vs memory, surface git loose ends
allowed-tools: Bash, Read, Edit, Glob, Grep, Write
---

You are an end-of-session assistant. Justin is wrapping up a Claude Code session. Your job is to quickly capture what matters and surface loose ends. Be fast — the user is leaving. Target 2-3 minutes total.

**Arguments**: `$ARGUMENTS`

If arguments include "quick", skip Phases 3 and 5 entirely.

---

## Phase 1: Session Summary (automatic, no input needed)

Scan the conversation context and produce a concise summary:

```
=== Session Summary ===
- [2-5 bullets of what was accomplished]
```

Then run the session cost script:

```bash
python3 ~/.claude/scripts/session-cost.py 2>/dev/null || true
```

**Paste the script's stdout verbatim into your response** (as a fenced code block, right under the Session Summary) so the user sees the cost in the message — do not rely on the tool-result pane being visible. If the script prints nothing (no session data yet), skip the cost block.

Continue immediately to Phase 2. Do NOT wait for user input.

---

## Phase 2: Learning Triage (one approval gate)

Review the session for learnings worth capturing. Most sessions produce nothing — that's fine. Don't manufacture learnings.

### Filter first (hard rule):

Before categorizing, ask: **"Could a future session reconstruct this in 30 seconds with `grep` or by reading one file?"** If yes, skip it — CLAUDE.md is not a code mirror. Specifically reject:

- Implementation details (lighting values, magic numbers, struct layouts) — these belong in code comments
- Re-statements of types, enum cases, or function signatures
- "X uses Y" facts derivable from a single grep
- Architecture decisions whose *rationale* isn't captured (the decision is in the code; the why goes in a commit message or memory)

Capture only what survives the filter: non-obvious gotchas, build/env quirks, cross-cutting workflows, and decisions whose rationale would be lost without a note.

### Categorize using this decision table:

| Learning Type | Destination | Why |
|---|---|---|
| Bash command or build pattern | CLAUDE.md | Code-derivable, helps future sessions |
| Code style convention | CLAUDE.md | Project convention |
| Environment quirk or gotcha | CLAUDE.md | Codebase-specific |
| User workflow preference | Memory (feedback) | Personal, not code-specific |
| Feedback on Claude behavior | Memory (feedback) | Behavioral correction |
| Project status/milestone (dates, deadlines, decisions) | Memory (project) | Contextual, point-in-time |
| External tool, system, or URL (Linear, Jira, Slack, Grafana, etc.) | Memory (reference) | Pointer to where info lives — even if the word "project" appears in the name |
| Architecture decision | CLAUDE.md if in project, Memory if general | Depends on context |

### Determine CLAUDE.md target:

1. Check if cwd is inside a project with its own CLAUDE.md → use that
2. If at home directory (`~`) → use `~/CLAUDE.md`
3. If no CLAUDE.md exists in the project, note that and ask if one should be created

### Present findings:

If there are CLAUDE.md updates:
```
### CLAUDE.md Updates → [target file path]

**Why:** [one-line reason per item]

\`\`\`diff
+ [the addition - keep it brief, one line per concept]
\`\`\`
```

If there are Memory updates:
```
### Memory Updates

- [type: feedback/project/reference] — [brief description of what will be saved]
```

If nothing worth capturing:
```
No learnings to capture this session. ✓
```

### Ask once:

> Apply these updates? (all / skip / pick individually)

- **For CLAUDE.md**: Use Edit tool to apply approved diffs
- **For Memory**: Write files to `/Users/jstottlemyer/.claude/projects/-Users-jstottlemyer/memory/` using this format:

```markdown
---
name: {{memory name}}
description: {{one-line description}}
type: {{user, feedback, project, reference}}
---

{{content — for feedback/project types: rule/fact, then **Why:** and **How to apply:** lines}}
```

Then update `MEMORY.md` index with a pointer to the new file.

- **For skip**: Move on, no changes made

---

## Phase 2b: Style Rules Triage (if screenshot reviews happened)

**Skip this phase if** no screenshot reviews or visual audits occurred in this session.

### Check for draft rules:

```bash
# Count draft vs permanent rules
python3 -c "
import json
rules = json.load(open('scripts/screenshot-rules.json'))
draft = [r for r in rules if r.get('status') == 'draft']
permanent = [r for r in rules if r.get('status') == 'permanent']
print(f'{len(permanent)} permanent, {len(draft)} draft')
if draft:
    for r in draft:
        print(f'  DRAFT: [{r[\"severity\"]}] {r[\"title\"]} — {r[\"description\"][:80]}')
"
```

### For each draft rule, decide:

| Action | When |
|--------|------|
| **Promote to permanent** | Rule proved useful in this session, applies going forward |
| **Refine and promote** | Rule is valid but description is vague — tighten it first |
| **Delete** | Rule was session-specific or redundant with existing rules |
| **Keep as draft** | Needs more evidence — leave for next review session |

### Run the lint script to surface automatable violations:

```bash
./scripts/lint-style-rules.sh 2>&1 | tail -10
```

Present a quick summary of lint results — any new violations introduced this session?

### Ask once:

> Promote/refine/delete draft rules? (list actions, or "skip")

Apply changes to `scripts/screenshot-rules.json`.

---

## Phase 3: Loose Ends (conditional, one approval gate)

**Skip this phase if:**
- Arguments include "quick"
- cwd is NOT inside a git repo (check with `git rev-parse --is-inside-work-tree 2>/dev/null`)

### Run these checks:

```bash
# Current branch
git branch --show-current

# Uncommitted changes (staged + unstaged)
git status --short

# Unpushed commits
git log --oneline @{upstream}..HEAD 2>/dev/null

# Open worktrees
git worktree list

# Active specs
ls docs/specs/*/spec.md 2>/dev/null
```

### Present findings:

```
=== Git Status ===
Branch: [branch name]
Uncommitted: [count] files ([list if ≤5, summary if more])
Unpushed: [count] commits
Worktrees: [list if >1, "clean" if only main]

=== Active Specs ===
[If docs/specs/ exists: list features and their latest artifact (spec/review/plan/check)]
[If no specs directory: omit this section]
```

### Suggest actions based on findings:

| Finding | Suggestion |
|---|---|
| Unpushed branch with commits | "Run `/finish` to create a PR or merge → uses `finishing-a-development-branch` skill" |
| Significant uncommitted changes | "Want to commit before leaving? I can help stage and commit." |
| Open worktrees (besides main) | "You have open worktrees — clean up or leave for next session?" |
| Specs with partial pipeline (e.g., spec.md but no plan.md) | Note where each feature is in the pipeline for next session |
| Everything clean | "All clean. ✓" |

Ask once:
> Handle any of these, or done for today?

If the user picks something, help with that one thing (commit, close a beads task, or suggest the appropriate skill). Do NOT chain into multi-step workflows — the user is leaving.

---

## Phase 3b: Dependency Install Audit (conditional, one approval gate)

**Skip this phase if:**
- Arguments include "quick"
- No new third-party package installs or `npx` runs happened in this session

Scan the session for commands that pulled in third-party code: `npm install`, `npm i -g`, `npx`, `pnpm add`, `yarn add`, `pip install`, `pipx install`, `brew install`, `cargo install`, `gem install`. For each new package (one not already audited earlier in the session), flag it for audit.

### Present findings:

```
=== New Packages This Session ===

Package: [name@version]
  Source: [registry — npm/pip/brew/etc]
  Age: [days since first publish — run `npm view <pkg> time` if npm]
  Audited this session: [yes / no]
```

If all packages are well-known and mature (>1 year on registry, high downloads, reputable maintainer), note and move on:
```
No audit needed — all packages are established. ✓
```

Otherwise, for each unaudited or young package, offer the audit checklist (from `feedback_package_audit.md`):

1. `package.json` install hooks (preinstall/postinstall/install)
2. Package age via `npm view <pkg> time`
3. Source grep: `fetch`/`http`/`eval`/`child_process`/base64
4. URL inventory in source — every outbound URL should be documented
5. Tarball diff — `npm pack <pkg>` vs git repo
6. Direct deps sanity check (no typosquats)
7. Recommend pinned `npx` for first use, not global install
8. Skip menu-bar/LaunchAgent/$PATH features on first install

### Ask once:

> Audit now, defer, or mark trusted? (audit / defer / trust)

- **audit**: walk the checklist for each flagged package, report findings
- **defer**: log the package + version in session notes; flag at next `/wrap`
- **trust**: user has vetted this out-of-band; note the decision

---

## Phase 4: Permission Audit (automatic, one approval gate)

Scan both `settings.local.json` files for accumulated permission approvals and suggest cleanup.

### Read both files:

```bash
# Global local settings
cat ~/.claude/settings.local.json 2>/dev/null || echo "{}"

# Project local settings (if inside a project)
cat .claude/settings.local.json 2>/dev/null || echo "{}"
```

### Analyze the allow lists for:

| Pattern | Action |
|---------|--------|
| **Multiple commands with same prefix** (e.g., `Bash(gt mol:*)`, `Bash(gt rig:*)`, `Bash(gt hook:*)`) | Suggest consolidation into one glob: `Bash(gt:*)` |
| **Exact one-off commands** (long, specific, contain temp paths or session-specific values) | Suggest removal — these were session artifacts |
| **Commands already covered by a broader glob** (e.g., `Bash(git add:*)` when `Bash(git:*)` exists in `settings.json`) | Suggest removal — redundant |
| **Stale entries** (reference deleted ports, old worktree paths, killed PIDs like `kill 63122`) | Suggest removal |
| **Frequently used tools** that belong in global `settings.json` | Suggest promotion (e.g., `Bash(python3:*)`, `Bash(ls:*)`) |

### Cross-reference with global settings:

Read `~/.claude/settings.json` to check which permissions are already globally allowed. Don't suggest adding what's already there.

### Present findings:

```
=== Permission Audit ===
📁 ~/.claude/settings.local.json: [N] entries
📁 .claude/settings.local.json: [N] entries (if exists)

**Consolidate** ([count]):
  - Bash(gt mol:*), Bash(gt rig:*), ... → Bash(gt:*)

**Remove (redundant)** ([count]):
  - Bash(git add:*) — covered by global Bash(git:*)

**Remove (stale)** ([count]):
  - Bash(kill 63122) — one-off PID
  - Bash(/opt/homebrew/.../python3.11 -m scripts.run_loop ...) — session-specific

**Promote to global** ([count]):
  - Bash(python3:*), Bash(ls:*) — used in every session
```

If nothing to clean up:
```
Permission lists are clean. ✓
```

### Ask once:

> Apply permission cleanup? (all / skip / pick individually)

- **Consolidation**: Replace multiple entries with one glob in the same file
- **Removal**: Delete the entry from the allow list
- **Promotion**: Add to `~/.claude/settings.json` allow list AND remove from `settings.local.json`
- Use the Edit tool for all changes. Preserve valid JSON formatting

**Important**: Only modify `settings.local.json` files (user-local). Never modify `settings.json` (shared/committed) without explicit confirmation for promotion.

---

## Phase 5: CLAUDE.md Health Check (conditional, one approval gate)

**Skip this phase if:**
- Arguments include "quick"
- Session was trivial (no code changes, just a question)

Quick drift scan of the project CLAUDE.md — not a full rewrite (that's `claude-md-management:revise-claude-md`), just catching obvious staleness.

### Run these checks:

0. **Size budget** — total length and largest section:
   ```bash
   wc -l CLAUDE.md
   # Largest H2 section line count
   awk '/^## / {if (name) print count, name; name=$0; count=0; next} {count++} END {if (name) print count, name}' CLAUDE.md | sort -rn | head -3
   ```

   Thresholds:
   - **≤250 lines**: healthy, no action
   - **>250 lines**: flag — surface in findings, suggest trimming candidates from this session's review
   - **>350 lines**: red zone — recommend `claude-md-management:revise-claude-md` for a full audit
   - **Any single H2 section >50 lines**: suggest splitting or consolidating that section

1. **Stale markers** — temporary notes that outlived their purpose:
   ```bash
   grep -nE 'revert before ship|TODO|FIXME|temporary|for testing|HACK|XXX' CLAUDE.md || echo "none"
   ```

3. **Test count drift** — compare documented count vs actual:
   ```bash
   # What CLAUDE.md claims
   grep -o '[0-9]* tests' CLAUDE.md | head -1

   # What actually exists
   grep -rn 'func test' Tests/ --include='*.swift' 2>/dev/null | wc -l
   ```

4. **"Next Up" staleness** — check if items in "Next Up" have been completed:
   ```bash
   # Show Next Up section
   sed -n '/^## Next Up/,/^## /p' CLAUDE.md | head -20
   ```

5. **Dead file references** — spot-check 5-10 file paths mentioned in CLAUDE.md:
   ```bash
   # Extract file paths from CLAUDE.md and check existence
   grep -oE 'Sources/[A-Za-z/]+\.swift' CLAUDE.md | sort -u | while read f; do
     [ ! -f "$f" ] && echo "MISSING: $f"
   done
   ```

6. **Status section freshness** — check if new files exist that aren't documented:
   ```bash
   # Find Swift files not mentioned in CLAUDE.md
   find Sources -name '*.swift' -newer CLAUDE.md 2>/dev/null | head -10
   ```

### Present findings:

```
=== CLAUDE.md Health ===

**Size**: [N] lines ([healthy / flag / red zone])
**Largest section**: [N] lines — [section name] [(>50, suggest split)]
**Stale markers**: [list with line numbers, or "none"]
**Test count**: documented [N], actual [M] → [update/matches]
**Next Up**: [stale items or "current"]
**Dead refs**: [list or "none"]
**Undocumented files**: [list or "none"]
```

If everything is current:
```
CLAUDE.md is current. ✓
```

If size is >350 lines OR significant drift (>3 issues):
```
⚠️  CLAUDE.md needs a full audit. Run `claude-md-management:revise-claude-md` next session.
```

### Ask once:

> Apply quick fixes? (all / skip / pick individually)

For quick fixes (test count update, dead ref removal), apply with Edit tool directly. For larger rewrites, defer to `claude-md-management:revise-claude-md`.

---

## Key Principles

- **Speed** — user is leaving, don't dawdle
- **One question at a time** — per Justin's preference
- **Show before change** — always display what will be modified before applying
- **Empty is fine** — "nothing to capture" is a valid outcome
- **Delegate** — point to existing skills for complex workflows, don't reimplement
- **Concise** — one line per concept, no verbose explanations
