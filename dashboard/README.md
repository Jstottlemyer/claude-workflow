# Graphify Dashboard

Local-first benefit tracking across all `~/Projects/` codebases indexed by graphify.

## View

```bash
open ~/Projects/claude-workflow/dashboard/index.html
```

Works from `file://` with no local server — the dashboard loads data from `data-bundle.js` (a regular `<script>` tag, which bypasses the CORS block that hits `fetch()` on `file://`).

If you see *"No data bundle found"*, regenerate it:

```bash
bash ~/Projects/claude-workflow/scripts/dashboard-bundle.sh
```

`dashboard-append.sh` rebuilds the bundle automatically on every append, so once `/wrap`, the weekly launchd jobs, or a fresh bootstrap have run, the bundle stays current on its own.

## Data

`data/<project-slug>.jsonl` — append-only. One JSON object per line. Events:

- `bootstrap` — initial baseline written by `scripts/bootstrap-graphify.sh --apply`.
- `wrap` — written at `/wrap` Phase 1 tail.
- `benchmark-weekly` — written by launchd agent `com.jstottlemyer.graphify-benchmarks.weekly`.
- `wiki-graph-weekly` — written by launchd agent `com.jstottlemyer.wiki-graph.weekly`.

Schema: see `~/Projects/claude-workflow/docs/graphify-usage.md` §13.

## Publish (deferred)

Dashboard is static HTML + JSONL. To put it on GitHub Pages:

```bash
cd ~/Projects/claude-workflow
git subtree push --prefix dashboard origin gh-pages
```

No secrets in `data/*.jsonl` — only node/edge counts, token ratios, commit counts, god-node *names*. If a project name itself is sensitive (e.g. `career`), exclude it before push:

```bash
rm dashboard/data/career.jsonl  # will be re-seeded on next /wrap; never push career data
```

## Manual event append (debugging)

```bash
~/Projects/claude-workflow/scripts/dashboard-append.sh \
  --event wrap --project claude-workflow --cwd "$PWD"
```
