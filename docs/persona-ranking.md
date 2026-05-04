# Persona Ranking — adopter guide

You cloned MonsterFlow, ran a few `/spec-review` or `/plan` gates, and
now the **Persona Insights** dashboard tab (or the `/wrap-insights`
text section) is showing you a wall of personas with retention,
survival, and uniqueness numbers next to each one. This page tells you
how to read those numbers without misinterpreting them.

For the canonical spec, see
[`docs/specs/token-economics/spec.md`](specs/token-economics/spec.md).

## Two-window cost vs value — read this first

Cost and value are **measured in different windows**. They cannot be
combined into a single "tokens per finding" without misleading
rounding. v1 gives you both numbers separately and lets you eyeball the
tradeoff yourself.

- **Value window**: most recent 45 (persona, gate) **artifact directories**
  (each `docs/specs/<feature>/<gate>/` counts as one).
- **Cost window**: most recent 45 **Agent dispatches** per (persona, gate)
  (each Claude Code Agent `tool_use` counts as one).

These windows usually contain different counts. The dashboard shows
`value-window: N directories; cost-window: M dispatches` as a tooltip
on `runs_in_window` so you don't accidentally divide cost by value-N.

### Worked example

`scope-discipline @ spec-review` might look like this:

| field                       | value         | window |
| --------------------------- | ------------- | ------ |
| `runs_in_window`            | 18            | value  |
| `cost_runs_in_window`       | 22            | cost   |
| `total_tokens`              | 274,500       | cost   |
| `judge_retention_ratio`     | 0.659         | value  |
| `avg_tokens_per_invocation` | ~12,500       | cost   |

Interpretation: 18 spec-review directories had this persona; 22
distinct Agent dispatches loaded the persona (some produced no findings
or were reruns); ~66% of raw bullets survived Judge clustering across
the 18 directories.

When you compare personas:

- **Value side**: `judge_retention_ratio`, `downstream_survival_rate`,
  `uniqueness_rate`.
- **Cost side**: `avg_tokens_per_invocation`.

**Never divide `total_tokens` by `runs_in_window`** — they're different
denominators. v1.1 will add per-dispatch capture so the windows can be
aligned.

## The three rates explained

Three columns measure different things. Reading them as a stack
ranking without context will mislead.

### Retention (`judge_retention_ratio`)

Post-Judge findings ÷ raw bullets emitted by the persona. This is a
**compression ratio**, not a survival rate. Judge can:

- Merge multiple raw bullets into one finding (low ratio doesn't mean
  low quality).
- Split one bullet into multiple findings (high ratio doesn't mean
  high quality).

It captures how dense the persona's output is relative to Judge's
clustering, not whether the thoughts survived.

### Survival (`downstream_survival_rate`)

Of this persona's findings that survived Judge clustering, the
fraction that got picked up in the next pipeline artifact (e.g.,
addressed in `plan.md`, or fixed in code).

**Empty cells often mean "not yet evaluated"** because the downstream
gate hasn't run — not that the finding was rejected.

### Uniqueness (`uniqueness_rate`)

Findings where this persona was the **sole contributor** (no overlap
with other personas in the cluster). High uniqueness means the persona
surfaces things others don't.

### Reading the three together

A persona with **low retention + high survival + high uniqueness** is
doing exactly what we want: Judge clusters their bullets aggressively
because they're saying things others said too, but the things they
*uniquely* surfaced land downstream.

## Silent vs (never run) — two badges, two meanings

These look similar but mean different things:

- **silent**: persona ran successfully (`status: ok` in
  `participation.jsonl`) but raised zero findings. Signal: low-noise,
  possibly auto-pruneable candidate when v1.1 ships roster-scaling.
- **(never run)**: persona is in `personas/{review,plan,check}/*.md`
  but has no record of ever running in the data window. Signal: new
  persona, or hasn't been activated yet. Day-one expected on a fresh
  install.

If your favorite persona suddenly shows as **silent**, don't
immediately delete it — silent can mean "ran on a feature where there
was nothing wrong to find."

## Persona contributor lifecycle — don't self-reject from low rates

If you contribute a persona to MonsterFlow and the dashboard shows
20% retention after 5 runs, **don't self-reject the PR**. The window
stabilizes at 45 invocations. Five runs is statistical noise.

The dashboard renders `insufficient_sample` rows with reduced opacity
specifically to discourage early conclusions.

Rule of thumb:

- `runs_in_window >= 3` — okay to draw soft conclusions.
- `runs_in_window >= 15` — okay to draw strong ones.

## Project Discovery cascade

The engine walks three sources for value-side data, in this order:

1. **cwd** — always on if `docs/specs/` exists in the current working
   directory.
2. **Explicit config** — at
   `${XDG_CONFIG_HOME:-$HOME/.config}/monsterflow/projects`. One
   absolute path per line. Missing-path entries are logged (counts
   only) and skipped.
3. **CLI scan flag (opt-in)** — `--scan-projects-root <dir>` walks
   `<dir>/*/docs/specs/` for additional roots.

For tier 3 there is privacy enforcement:

- Adding a directory under tier 3 requires confirmation. Interactive
  runs prompt y/N. Non-interactive runs (tmux pipe-pane, `/autorun`,
  `dashboard-append.sh`) **must** use `--confirm-scan-roots <dir>`
  once from a real terminal. After that, regular `--scan-projects-root`
  works from any context.
- **Per-project opt-out**: drop a zero-byte `.monsterflow-no-scan`
  file in any project root and the cascade silently excludes it. Use
  this for client-confidential repos under your `--scan-projects-root`
  tree.

### Examples

```bash
# Bootstrap: confirm a scan root once from a real terminal
python3 scripts/compute-persona-value.py --confirm-scan-roots ~/Projects

# After bootstrap, normal operation can include the scan root
# (this is what /wrap-insights does automatically — non-interactive)
python3 scripts/compute-persona-value.py --scan-projects-root ~/Projects --best-effort

# Opt out a private project
touch ~/Projects/client-acme/.monsterflow-no-scan
```

The `--best-effort` flag downgrades A1.5 disagreement
(parent-annotation vs subagent-sum) from a hard exit to a warning —
appropriate for adopter machines where occasional drift is expected.

## `MONSTERFLOW_DEBUG_PATHS` env var

Stderr is **counts-only by default** — paths never leak in steady
state. If you need paths for debugging ("why isn't this project in the
output?"), set the env var before invocation:

```bash
MONSTERFLOW_DEBUG_PATHS=1 python3 scripts/compute-persona-value.py
```

Paths get logged to `~/.cache/monsterflow/debug.log` (machine-local,
never committed).

## Pre-commit hook (opt-in)

Optional defense-in-depth: install a pre-commit hook that runs the
allowlist test whenever fixtures or generated data are staged.

```bash
bash scripts/install-precommit-hooks.sh
```

Idempotent — safe to re-run. Composes safely with existing pre-commit
hooks via a sentinel-bracketed block. Re-run after `git pull` if you
ever re-clone.

## Privacy summary

The output JSONL records **only** counts, sha256-derived IDs
(per-machine salted so they can't be rainbow-tabled), and persona/gate
names — **never** finding titles, bodies, prompts, or paths. Every
emitted row passes a strict allowlist schema
(`additionalProperties: false`) before write. Committed test fixtures
use the same allowlist. Generated data is gitignored by default.

If you ever screenshot the dashboard or copy `/wrap-insights` output
to share publicly: persona names + numbers are the leak surface.
Review the warning banner in the dashboard before sharing.

## When in doubt

- Run `python3 scripts/compute-persona-value.py --help` to see the
  current flag surface.
- Run `python3 scripts/compute-persona-value.py --explain
  <persona>:<gate>` to dump a per-row breakdown to stderr for one
  persona.
- File issues against MonsterFlow if a number looks wrong — the v1
  windows are deliberately narrow and the engine assumes good faith
  reads of the dashboard rather than gaming the rates.
