# MonsterFlow Dashboard

Local-first dashboard with **two modes** — toggle in the top-right of the page:

- **Graphify** — benefit tracking across all `~/Projects/` codebases indexed by graphify (nodes, edges, communities, token reduction, sessions per week).
- **Judge** — what the Judge persona is doing across `/spec-review`, `/plan`, and `/check` gates: verdicts, raw → cluster compression, persona contribution, agent disagreements resolved, blocker findings.

## View

```bash
open ~/Projects/MonsterFlow/dashboard/index.html
```

Works from `file://` with no local server — both bundles (`data-bundle.js` + `judge-bundle.js`) load via `<script>` tags, which bypass the CORS block that hits `fetch()` on `file://`.

If a mode reports its bundle is missing, regenerate it:

```bash
bash ~/Projects/MonsterFlow/scripts/dashboard-bundle.sh        # graphify mode
bash ~/Projects/MonsterFlow/scripts/judge-dashboard-bundle.sh  # judge mode
```

`dashboard-append.sh` rebuilds **both** bundles on every append, so once `/wrap`, the weekly launchd jobs, or a fresh bootstrap have run, both stay current on their own.

## Graphify mode — data

`data/<project-slug>.jsonl` — append-only. One JSON object per line. Events:

- `bootstrap` — initial baseline written by `scripts/bootstrap-graphify.sh --apply`.
- `wrap` — written at `/wrap` Phase 1 tail.
- `benchmark-weekly` — written by launchd agent `com.jstottlemyer.graphify-benchmarks.weekly`.
- `wiki-graph-weekly` — written by launchd agent `com.jstottlemyer.wiki-graph.weekly`.

Schema: see `~/Projects/MonsterFlow/docs/graphify-usage.md` §13.

## Publish (deferred)

Dashboard is static HTML + JSONL. To put it on GitHub Pages:

```bash
cd ~/Projects/MonsterFlow
git subtree push --prefix dashboard origin gh-pages
```

No secrets in `data/*.jsonl` — only node/edge counts, token ratios, commit counts, god-node *names*. If a project name itself is sensitive (e.g. `career`), exclude it before push:

```bash
rm dashboard/data/career.jsonl  # will be re-seeded on next /wrap; never push career data
```

## Manual event append (debugging)

```bash
~/Projects/MonsterFlow/scripts/dashboard-append.sh \
  --event wrap --project MonsterFlow --cwd "$PWD"
```

## Judge mode — data

The Judge bundle walks **every project under `~/Projects/`** and reads, per feature, per stage:

| File                                          | Used for                                                |
|-----------------------------------------------|---------------------------------------------------------|
| `docs/specs/<feat>/<stage>/findings.jsonl`    | Final post-Judge clusters, severities, persona attribution |
| `docs/specs/<feat>/<stage>/participation.jsonl` | Per-persona findings emitted (status / model)         |
| `docs/specs/<feat>/<stage>/run.json`          | Run id, prompt version, artifact hash, timestamp        |
| `docs/specs/<feat>/<stage>/survival.jsonl`    | (`/check` only) which prior findings survived           |
| `docs/specs/<feat>/<stage>/raw/*.md`          | Pre-Judge per-agent outputs (counted, not parsed)       |
| `docs/specs/<feat>/<stage>.md`                | Synthesized verdict + "Agent Disagreements Resolved" count |

Each card on the Judge view has a **"Reads:"** footer pointing at the path it pulls from — the dashboard documents itself.

Test fixtures (any path containing `/tests/fixtures/`) are skipped.

### When does the bundle refresh?

- Automatically: every time `dashboard-append.sh` runs (so on every `/wrap`, every weekly launchd job, every `bootstrap-graphify.sh --apply`).
- On demand: `bash ~/Projects/MonsterFlow/scripts/judge-dashboard-bundle.sh`.

### Empty?

If the Judge view shows "No judge data found yet", you haven't run a multi-agent gate yet. Run `/spec-review`, `/plan`, or `/check` on a feature in `docs/specs/<feature>/`, then refresh the page.
