---
description: Snapshot the current project's graphify graph, open it in the browser, and surface deltas since last review
allowed-tools: Bash, Read
---

You are the graphify inspector. Show the user a quick, accurate snapshot of the code graph for the **current working directory**, then open the interactive view. Arguments: `$ARGUMENTS`

## Phase 1: Pre-flight

```bash
test -f graphify-out/graph.json
```

If the file does not exist, print this and stop:

```
No graph yet for this project.
Run the workspace bootstrap (one-time):
  bash ~/Projects/MonsterFlow/scripts/bootstrap-graphify.sh --dry-run

Or index just this project:
  graphify .
```

## Phase 2: Freshness check

```bash
git log -5 --oneline 2>/dev/null | wc -l
stat -f %m graphify-out/graph.json 2>/dev/null || stat -c %Y graphify-out/graph.json
```

If HEAD has commits after `graph.json`'s mtime and the count is >5, print a one-line nudge:
`Graph is N commits behind HEAD — the post-commit hook should keep this fresh; run `graphify update .` if you've been rebasing or squashing.`

Don't block on this — keep going.

## Phase 3: Snapshot

Read `graphify-out/graph.json` and `graphify-out/GRAPH_REPORT.md`. Parse with Python (inline `python3 -c`) to produce:

```
=== Graph snapshot ===
Project: <basename of cwd>
Nodes: <N>       (delta since last /graph: +X / -Y)
Edges: <M>       (delta: +X / -Y)
Communities: <C> (delta: +X / -Y)

Top god nodes (by degree):
  1. <label>  — <degree> neighbors
  2. ...
  (up to 10)

Last benchmark: <reduction_ratio>x reduction (tokens per query), <age> ago
```

**Delta computation:** state file at `./.graphify-last-seen.json` (cwd-local, gitignored). Read previous snapshot if it exists; diff node IDs and community IDs. After rendering, overwrite `.graphify-last-seen.json` with the current snapshot so the next `/graph` run can diff.

Ensure `.graphify-last-seen.json` is in `.gitignore`:

```bash
grep -q "^\.graphify-last-seen\.json$" .gitignore 2>/dev/null || \
  echo ".graphify-last-seen.json" >> .gitignore
```

## Phase 4: Open visual

```bash
open graphify-out/graph.html
```

Only on darwin. If `$OSTYPE` isn't darwin, print the absolute path instead:
`Visual graph at: $PWD/graphify-out/graph.html`

## Phase 5: Weekly-review nudge

If `.graphify-last-seen.json` existed before Phase 3 AND the previous `ts` is ≥7 days old, append:

```
Weekly graph review — anything surprising?
  /wrap to promote observations to the wiki.
```

Otherwise skip silently.

## `--benchmark` flag

If `$ARGUMENTS` contains `--benchmark`, before Phase 3:

```bash
~/.local/venvs/graphify/bin/python3 -c 'import json; from graphify.benchmark import run_benchmark; print(json.dumps(run_benchmark("graphify-out/graph.json")))' > graphify-out/last-benchmark.json
```

(The graphify CLI's `benchmark` subcommand only prints human-readable text — the Python API is how we get machine-readable JSON.)

Report the fresh numbers as part of the Phase 3 output ("Last benchmark" line shows "just now").

## Output discipline

- No commentary beyond the snapshot and nudges.
- Use fenced code blocks sparingly — the snapshot above is the main output.
- Don't speculate about what god nodes mean; the user will look at the graph if they want more.
