# graphify — Adoption Playbook

**Version:** 1.0 (migrated 2026-04-17)
**Last reviewed against graphify version:** graphifyy 0.4.20 (PyPI)
**Author:** Justin Stottlemyer
**Home:** `~/Projects/claude-workflow/docs/graphify-usage.md` (this file — durable)
**Audit trail:** `~/Projects/graphify/docs/specs/graphify-adoption/` (throwaway clone, ephemeral)

> This is the durable home for the graphify adoption playbook. Refresh it
> using the triggers in §9. The §10 migration step is already done; that
> section is preserved below as historical context.

> **How to read this playbook.** §1–§2 give you the mental model — what
> graphify is and where it fits in your broader setup. §3 shows what it
> actually looks like when you run it. §4 is the decision table for your four
> projects. §5–§7 are copy-paste setup. §8 explains how your existing
> pipeline uses the graph automatically. §9–§10 are maintenance. §11 is a
> *"what to learn next"* section — time-bound scaffolding that we'll prune
> once graphify feels routine.

---

## 1. What graphify does

graphify turns any folder of code, docs, PDFs, images, or audio/video into a
queryable knowledge graph. Three passes: (1) deterministic AST extraction via
tree-sitter for 25 languages — local, free, fast; (2) local Whisper transcription
for audio/video; (3) Claude-driven semantic extraction for docs, papers, and
images, run in parallel subagents. Results merge into a NetworkX graph, get
clustered by Leiden community detection, and export as interactive HTML,
queryable JSON, and a one-page `GRAPH_REPORT.md` audit.

**Architecture (one line):** `detect → extract → build → cluster → analyze → report → export`. Every edge carries a confidence tag: `EXTRACTED` (explicit in source), `INFERRED` (reasonable deduction with a score), `AMBIGUOUS` (flagged for review).

**Privacy surface:** code files never leave your machine (tree-sitter is local). Docs / papers / images DO go through Claude's API for semantic extraction. Audio/video are transcribed locally via faster-whisper — audio never leaves the machine, but the resulting transcripts then go through Claude like any other doc. No telemetry, no credential storage, no network listener (MCP is stdio-only).

**Cost profile:** AST is free. Semantic extraction costs tokens — roughly one batch of Claude API calls per 20–25 doc/paper/image files on first run. Subsequent runs use a SHA256 cache and only re-process changed files. Small corpora (< 6 files) see no compression benefit; value is structural clarity. Medium (~10–50 files) sees modest benefit. Large mixed corpora (50+ files) see 5–70× token-reduction on downstream queries vs reading raw files.

**Install shape (important).** There is no `graphify <path>` CLI command. The full pipeline is a **Claude Code skill** invoked as `/graphify .` inside a Claude Code session. The `graphify` CLI only exposes maintenance subcommands: `update`, `query`, `path`, `explain`, `cluster-only`, `watch`, `add`, `hook`, `install`, `benchmark`, plus per-platform installers. To run the full pipeline you install the skill into Claude Code (`graphify claude install`) and then call it from a Claude Code session on that project.

---

## 2. Mental model — where graphify fits in your stack

Before you start wiring graphify into projects, it helps to know **which layer of your setup it belongs to**. Think of your environment as five layers:

```
Layer 1  Sources                    Per-project repos — your actual code, docs, PDFs
         CosmicExplorer/Sources/*.swift · AuthTools/packages/*/src/*.ts · ...

Layer 2  Per-project graphs         Derived from Layer 1 by graphify, lives with the source
         <project>/graphify-out/    graph.json · GRAPH_REPORT.md · graph.html
                                    (gitignored — every machine regenerates locally)

Layer 3  Cross-project tooling      Patterns that apply across multiple projects
         ~/Projects/claude-workflow/  commands, personas, templates — and THIS playbook

Layer 4  Personal knowledge         Hand-crafted notes, journal, ideas
         ~/Projects/obsidian-wiki/  (your Obsidian vault — written by you, not generated)

Layer 5  Ephemeral / audit          Evaluation work, specs, session memory
         this clone · .claude/memory/ · docs/specs/*  (throwaway once the output migrates up)
```

**Key rules that follow from the layers:**

1. **graphify primarily produces Layer 2.** Each project gets its own `graphify-out/` directory. That's the normal case — don't fight it. Keep graphs local to their project.

2. **The playbook is Layer 3.** After migration (§10), this doc lives in `claude-workflow` with the rest of your cross-project tooling (pipeline commands, personas, templates). That's the right neighborhood for "how do I do X across all my projects."

3. **Obsidian (Layer 4) is for your thinking, not auto-generated graphs.** graphify *can* export to Obsidian vault format (`--obsidian` flag), but that's only the right move when graphify's *input* is itself personal knowledge — a `/raw` folder of papers, notes, research. Don't auto-flow code-project graphs into your Obsidian vault; it'll clutter Layer 4 with Layer 2 content.

4. **This graphify clone is Layer 5 — throwaway.** Once the playbook migrates to `claude-workflow`, this `~/Projects/graphify/` directory has no durable role. Archive or delete when convenient. Nothing you need long-term should live here.

**When to use graphify's `--obsidian` export:**

| Corpus type | Use `--obsidian`? |
|---|---|
| Code-heavy project (CosmicExplorer Swift, Concierge TS) | **No** — `graph.html` is better for code exploration; don't pollute your vault |
| Doc-heavy project where the docs *are* code artifacts (API docs, design docs for a codebase) | **No** — stays with the project |
| Personal research folder / papers / notes you'd read in Obsidian anyway | **Yes** — this is the original Karpathy `/raw` use case graphify was built for |
| Your existing Obsidian vault itself | **Separate question** — you could graph the vault to find cross-note patterns, but that's a different spec later |

**Mental model, one sentence each:**
- **Projects own their graphs.** (Layer 2, gitignored, per-project.)
- **claude-workflow owns the patterns.** (Layer 3 — how to use graphify across projects.)
- **Obsidian owns your thinking.** (Layer 4 — never auto-populated from code.)
- **Memory + specs own the audit trail.** (Layer 5 — ephemeral.)

When you're deciding where something should live, ask which layer it belongs to. If a file could plausibly go in two layers, it probably belongs in the more durable one.

---

## 3. Validation findings (CosmicExplorer, 2026-04-17)

Validated against `~/Projects/Mobile/Games/CosmicExplorer` — 155 Swift files,
AST-only, library-direct (bypassed the skill to avoid the noisy doc/image/audio
corpus).

| Metric | Value |
|---|---|
| Nodes | 2,087 |
| Edges | 4,560 |
| Communities (Leiden) | 34 |
| Extraction | 64% EXTRACTED / 36% INFERRED / 0% AMBIGUOUS |
| Wall-clock | < 2s end-to-end |
| Cost | $0 (AST only) |

**Swift extraction is strong.** Edge relations included `calls` (2,310), `method` (1,310), `inherits` (356), `case_of` (334 — Swift enum cases, correctly captured), `contains` (285), `imports` (225). The call-graph INFERRED second pass produced 1,641 edges at avg confidence 0.8.

**God nodes surfaced were real architecture** — `GameViewModel`, `CosmicScene3D`, `CartoonIcon`, `PlayerProfile`, `SkyViewerScene`. Five surprising cross-community bridges identified (e.g. `SkyViewerView.makeUIView() → JulianDate` — the SwiftUI/UIKit bridge calls astronomy math). Graphify flagged 332 weakly-connected nodes ("Knowledge Gaps" — honest report, not hidden).

**Three gotchas uncovered** (each lands in a per-project recipe below):
1. `detect()` misclassifies `.m4a` sound effects as "video" — would trigger 487 Whisper runs on CosmicExplorer's game sounds if run unguarded. Every project needs a `.graphifyignore` before first run.
2. Communities render as `Community 0`, `Community 1`, … without the skill's Step 5 LLM labeling pass. Library-direct usage gets structural signal but not semantic labels.
3. `cluster()` returns `{community_id: [node_ids]}` — undocumented shape. Minor, matters only for direct Python integration.

Full finding details in `validation-output/FINDINGS.md`. Snapshot artifacts in `validation-output/`.

---

## 4. Per-project fit matrix

| Project | Shape | Decision | Rationale | Key risks |
|---|---|---|---|---|
| **CosmicExplorer** | 155 Swift files + 49 docs, iOS game | **ADOPT** | Validated. Swift AST strong. Real architectural signal surfaced. | Needs `.graphifyignore` to skip `.m4a` sounds and backup PNGs before first run. |
| **Concierge** (the `AuthTools/` repo — `concierge-monorepo`) | 156 TypeScript files across `core/` + `google-workspace/` packages, +19 docs | **ADOPT** | TypeScript is graphify's best-tested language. Monorepo shape (`core` + `google-workspace`) will make cluster boundaries natural. Active development → graph stays current via post-commit hook. | None major. Standard `.graphifyignore` for `node_modules/`, `dist/`, `build/`. |
| **Claude-Workflow** | 64 markdown files (commands, personas, templates, docs), 1 Python, 3 shell | **ADOPT** | Doc-heavy; graphify's multimodal / semantic extraction is the main pitch. Community detection over personas + commands + templates will surface patterns you can't grep for. | Costs Claude API tokens on first run (64 docs × semantic pass ≈ 3–4 subagent batches). Budget ~$1–2 for first extraction. |
| **Career** | 8 files (6 md, 1 pdf, 1 docx) under `outreach/`, `profiles/`, `resume/` | **DEFER** | Corpus too small for structural value (graphify's own `worked/httpx/` shows ~1× benefit below 10 files). Also mixes privacy-sensitive content (recruiter names, personal emails) with low-sensitivity drafts. Revisit when corpus grows. | Privacy: `outreach/` contains recruiter names + personal email addresses. Sending those through Claude API needs an explicit decision before adoption. |

**Verdict: 3-of-4 adopt, 1 defer.** CosmicExplorer and Concierge are the highest-value — active codebases where "what calls what" questions are common. Claude-Workflow benefits from graphify's doc-clustering. Career defers until it has more content *and* a privacy call on the outreach/ folder.

### Future-project decision template

When a 5th project arrives, route it through these questions:

1. **Substantive content?** < 10 files → defer; 10–50 → adopt with small-corpus expectations (structural clarity, not token compression); 50+ → full value available.
2. **Bulk non-source assets** (game sounds, vendored PDFs, image backups)? → Write `.graphifyignore` **before** first run. Don't let `detect()` walk uncontrolled.
3. **Privacy-sensitive content** (client PII, recruiter names, personal emails, client code under NDA)? → Scope corpus to a safe subtree OR use AST-only mode (code only, no semantic pass) OR don't adopt.
4. **Primary language in graphify's supported set?** (Python, JS, TS, Go, Rust, Java, C, C++, Ruby, C#, Kotlin, Scala, PHP, Swift, Lua, Zig, PowerShell, Elixir, Objective-C, Julia, Verilog, Vue, Svelte, Dart) → yes = full pipeline; no = AST won't help, rely on doc-only extraction.
5. **Install:** `pip install "graphifyy[mcp]" && graphify claude install` → `.graphifyignore` → `/graphify .` from Claude Code → append CLAUDE.md pointer.

---

## 5. Install recipes

All three adopted projects use the same install pattern — differences are the `.graphifyignore` (§6) and the corpus scoping for the first run.

### 4a. CosmicExplorer

```bash
cd ~/Projects/Mobile/Games/CosmicExplorer
python3 -m venv .venv
.venv/bin/pip install "graphifyy[mcp]"
.venv/bin/graphify claude install       # writes CLAUDE.md section + PreToolUse hook
# Copy .graphifyignore template from §6a into repo root
# Optionally: graphify hook install   — post-commit graph rebuild
```
Then open Claude Code in this project and type `/graphify .`.

### 4b. Concierge (`~/Projects/AuthTools`)

```bash
cd ~/Projects/AuthTools
python3 -m venv .venv
.venv/bin/pip install "graphifyy[mcp]"
.venv/bin/graphify claude install
# Copy .graphifyignore template from §6b
# Recommended: graphify hook install   — active codebase benefits from post-commit refresh
```
Then `/graphify .` from Claude Code.

### 4c. Claude-Workflow

```bash
cd ~/Projects/claude-workflow
python3 -m venv .venv
.venv/bin/pip install "graphifyy[mcp]"
.venv/bin/graphify claude install
# Copy .graphifyignore template from §6c
```
Then `/graphify .` from Claude Code. First run does semantic extraction on 64 .md files — budget ~$1–2 in Claude API tokens. Subsequent runs hit the SHA256 cache.

### Note on package naming

PyPI package is `graphifyy` (**double-y**). CLI and skill name are `graphify` (single-y). `pip install graphify` silently installs an unrelated package — don't do it. Always `pip install graphifyy`.

---

## 6. `.graphifyignore` templates

`.graphifyignore` uses gitignore syntax. One at repo root applies even when graphify runs on a subfolder.

### 5a. CosmicExplorer (iOS / Xcode)

```
# Xcode / Swift build artifacts
.build/
DerivedData/
Pods/
*.xcworkspace/xcuserdata/
*.xcodeproj/xcuserdata/

# Game sounds — graphify misclassifies .m4a as "video" and would
# trigger Whisper transcription on every sound effect (hours, useless)
Sources/Resources/Sounds/

# Backup / archived images (not source content)
docs/backupimages/

# Graphify's own output
graphify-out/
.venv/
```

### 5b. Concierge (TypeScript monorepo)

```
# Node / pnpm
node_modules/
dist/
build/
*.tsbuildinfo

# Test output
coverage/

# Built MCP bundles (binary, not source)
*.mcpb

# Standard
graphify-out/
.venv/
.DS_Store
```

### 5c. Claude-Workflow (docs-heavy)

```
# Standard
graphify-out/
.venv/
__pycache__/
*.pyc

# Personal config (already gitignored per the repo's own rules)
personal/
```

---

## 7. CLAUDE.md 1-liner pointer

Append to each adopted project's `CLAUDE.md`:

```markdown
## Knowledge graph
This project uses graphify. See `~/Projects/claude-workflow/docs/graphify-usage.md`.
- Build / refresh: `/graphify .` from Claude Code (or `graphify update .` for code-only re-extract).
- Report: `graphify-out/GRAPH_REPORT.md`
- Graph data: `graphify-out/graph.json` (consumable by `graphify query`, MCP, or direct Python).
```

Keep it short. The full usage doc lives in claude-workflow (single source of truth).

---

## 8. Consumption convention (leverage inside the 8-command pipeline)

**The convention:** if `graphify-out/GRAPH_REPORT.md` exists in a project's root, any pipeline command's Phase 0 context-exploration step SHOULD read it alongside the constitution, CLAUDE.md, and relevant specs.

**The enforcement** is not a pipeline edit. It's graphify's own **PreToolUse hook**, installed automatically by `graphify claude install`. The hook fires before every Glob and Grep invocation in Claude Code — if a graph exists, Claude sees:

> *"graphify: Knowledge graph exists. Read GRAPH_REPORT.md for god nodes and community structure before searching raw files."*

This means once you install graphify in a project, your existing `/spec`, `/plan`, `/check`, `/build` commands automatically benefit from the graph without any changes to the pipeline command files. The leverage is in the hook, not the command.

**What you don't need to do:** edit any file in `~/Projects/claude-workflow/commands/`. The pipeline's Phase 0 steps already include "read available context" — the graph just becomes part of that context when present.

**What you might later do** (deferred, not required): if you find you're asking `/plan` or `/check` specific graph-traversal questions, a future spec in claude-workflow could add a dedicated "graph-aware designer" persona. Not now.

---

## 9. Refresh triggers

Refresh this playbook when any of these fire — not on a calendar. The doc goes stale when graphify's shape changes, not when time passes.

1. **A project picks up a new language graphify now supports.** Re-check the language list in the README and update §4's fit matrix.
2. **graphify adds a feature relevant to our work.** Examples to watch: improved Swift extraction, cross-language call graph, MCP server changes, a `.graphifyignore` default for common asset types.
3. **A new project joins the roster** (5th project beyond CosmicExplorer / Concierge / Claude-Workflow / Career). Route it through §4's future-project template; append a row to the matrix.
4. **Drift check** — a minor version bump has gone by without review. We validated on 0.4.20; when 0.5.x ships, re-read §§1 and 3 against the new README + CHANGELOG.
5. **Concierge's decision re-evaluates anything.** It's live TypeScript — if extraction quality is weaker on TS than Swift was, that's a headline finding to capture.
6. **Career's corpus grows past 15–20 files** OR Justin decides the outreach/ privacy question. Either one is a re-open trigger on its "defer" verdict.

---

## 10. Migration to claude-workflow

Playbook migrates to its durable home in two manual steps:

1. **Copy this file**: `cp docs/specs/graphify-adoption/playbook.md ~/Projects/claude-workflow/docs/graphify-usage.md` (create `docs/` in claude-workflow if missing).
2. **Per-project CLAUDE.md additions**: for CosmicExplorer, Concierge (AuthTools), and Claude-Workflow, append §7's 1-liner pointer to that project's `CLAUDE.md`. Commit to each project separately.

Post-migration, update this file's header:
- `> This playbook lives at ~/Projects/claude-workflow/docs/graphify-usage.md.`
- Keep "Last reviewed against graphify version: 0.4.20" until a refresh trigger fires.

No automation. One-time step. The graphify clone at `~/Projects/graphify/` can then be archived or re-cloned as needed — playbook is no longer load-bearing on it.

---

## 11. Learning path — what to do next (time-bound; prune when fluent)

> This section is **scaffolding for learning graphify**, not durable reference.
> Once graphify feels routine, delete this section (and remove the §11 pointer
> from the reading guide at the top). The rest of the playbook stands on its own.

### Stage A — Install and first-run on one project (30 min)

Start with **Concierge** (`~/Projects/AuthTools`) or **Claude-Workflow** — both are lower-stakes than CosmicExplorer's 155 Swift files, and they'll teach you the install pattern without edge cases.

1. Follow §5's install recipe for that project.
2. Drop the `.graphifyignore` template from §6.
3. Open Claude Code in the project. Type `/graphify .`.
4. When it finishes, open `graphify-out/GRAPH_REPORT.md` and skim: god nodes, surprising connections, suggested questions.
5. Open `graphify-out/graph.html` in a browser. Click around. Zoom to a community. Click a node.

**What to pay attention to:** do the god nodes match what you'd say are the core abstractions? Do any surprising connections teach you something? Would you keep any of the suggested questions?

### Stage B — The four ways you consume a graph (~15 min each, on the same project)

You've now got one graph. There are four distinct ways to use it — learning each one makes graphify stick.

1. **Always-on (the default).** Just use Claude Code normally on the project. The PreToolUse hook (installed by `graphify claude install`) fires before Grep/Glob. Claude reads `GRAPH_REPORT.md` before answering codebase questions. You don't do anything — but notice that the answers get more structural.

2. **Targeted query from the terminal.** Drop out of Claude Code and try:
   ```bash
   .venv/bin/graphify query "how does auth work?"
   .venv/bin/graphify path "AuthModule" "Database"
   .venv/bin/graphify explain "PlayerProfile"
   ```
   These traverse `graph.json` and return subgraphs with confidence tags. Good for specific answers.

3. **Interactive exploration.** Open `graph.html` in a browser. Search, filter by community, drag nodes around. This is where the graph shows patterns your eye catches faster than grep.

4. **MCP server (advanced, skip first pass).** `python3 -m graphify.serve graphify-out/graph.json` exposes the graph as an MCP server — other agents or Claude Desktop can query it live. Come back to this after the first three feel natural.

### Stage C — Incremental and maintenance (15 min)

Once you've got one graph, learn how it stays fresh.

1. `graphify update .` — re-extract only code files that changed since last run. AST-only, free, fast. Use this after any code push.
2. `graphify hook install` — installs a post-commit git hook that auto-runs `update` after every commit. Set-and-forget.
3. `graphify cluster-only .` — re-runs Leiden clustering on the existing graph. Use when the graph feels "wrong" or the community boundaries drifted.
4. `graphify --watch .` (inside Claude Code as `/graphify . --watch`) — background watcher that rebuilds on save. Probably overkill for most projects; git-hook is the default.

### Stage D — Second project (30 min)

Now adopt a second project. Notice what's **same** and what's **different**:
- Same: the install commands (§5), the CLAUDE.md pointer (§7), the PreToolUse hook.
- Different: the `.graphifyignore` template (§6) — each project type needs its own exclusions. CosmicExplorer's `Sources/Resources/Sounds/` isn't in Concierge.

### Stage E — Fluency check (when)

You're fluent when you can answer these without looking:
1. "If I start a new project, what are the three commands to get graphify set up?"
2. "If a project has bulk binary assets, what do I do before first run?"
3. "If the graph is out of date, how do I refresh it without re-running the full LLM pipeline?"
4. "Where does each layer of my setup live — source, graph, tooling, personal knowledge?"
5. "When would I export to Obsidian? When wouldn't I?"

When all five feel easy, delete this §11. You're done with the learning scaffolding.

### Ongoing check-ins

For the next few graphify-related sessions, I'll default to **teaching mode**: explaining concepts alongside decisions, offering the "why" before the "what," and checking understanding before moving on. Signal me when you want to dial that back — either explicitly ("stop explaining, just do it") or implicitly (by making confident decisions without asking).

This section prunes itself when fluency arrives.

