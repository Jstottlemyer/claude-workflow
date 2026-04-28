# Synthetic feature fixtures

Three feature directories (`a`, `b`, `c`) with hand-crafted `findings.jsonl`, `participation.jsonl`, and `survival.jsonl` for `/spec-review`. Used by T22 to verify `/wrap-insights` rollup math without running real pipeline iterations.

## Stage roster (assumed for fixture)

`/spec-review` reviewers (6 personas + Codex when applicable): `requirements`, `gaps`, `ambiguity`, `feasibility`, `scope`, `stakeholders`, `codex-adversary`.

## Expected rollup over the 3-feature window

For each persona, hand-computed values that `/wrap-insights` (with `personas` arg, full table) should match within 0.01:

| persona | participated | runs | findings_total | unique_count | survived_count | unique_and_survived | uniqueness_rate | survival_rate | load_bearing_rate | silent_rate |
|---|---|---|---|---|---|---|---|---|---|---|
| security | 3 | 2 | 3 | 2 | 3 | 2 | 0.667 | 1.000 | 0.667 | 0.333 |
| ux | 3 | 2 | 2 | 2 | 2 | 2 | 1.000 | 1.000 | 1.000 | 0.333 |
| gaps | 3 | 2 | 2 | 0 | 1 | 0 | 0.000 | 0.500 | 0.000 | 0.333 |
| feasibility | 3 | 1 | 1 | 1 | 0 | 0 | 1.000 | 0.000 | 0.000 | 0.667 |
| scope | 3 | 1 | 2 | 1 | 1 | 1 | 0.500 | 0.500 | 0.500 | 0.667 |
| requirements | 3 | 0 | 0 | 0 | 0 | 0 | n/a | n/a | n/a | 1.000 |
| ambiguity | 3 | 0 | 0 | 0 | 0 | 0 | n/a | n/a | n/a | 1.000 |
| stakeholders | 3 | 0 | 0 | 0 | 0 | 0 | n/a | n/a | n/a | 1.000 |

**Cold-start expectations:**
- 3 features < 10-feature rolling window → all personas should render with `(insufficient data — N runs)` markers in the *diff* render (which compares vs prior 10).
- The full table (`/wrap-insights personas`) shows the rates above regardless of window size.

## Cluster definitions

**Feature `a`:**
- `sr-a-0001` `[security]` — addressed
- `sr-a-0002` `[ux]` — addressed
- `sr-a-0003` `[security, gaps]` — addressed (security & gaps shared)

**Feature `b`:**
- `sr-b-0001` `[ux]` — addressed
- `sr-b-0002` `[feasibility]` — not_addressed

**Feature `c`:**
- `sr-c-0001` `[security]` — addressed
- `sr-c-0002` `[scope]` — addressed
- `sr-c-0003` `[gaps, scope]` — not_addressed (shared)

## Directory layout

```
tests/fixtures/synthetic-features/
  a/
    spec-review/
      findings.jsonl
      participation.jsonl
      survival.jsonl
  b/
    spec-review/
      findings.jsonl
      participation.jsonl
      survival.jsonl
  c/
    spec-review/
      findings.jsonl
      participation.jsonl
      survival.jsonl
```

`/wrap-insights` running with `docs/specs/` pointed at this fixture root (or via a `--features-root tests/fixtures/synthetic-features/` flag if added) should produce the expected rollup table.
