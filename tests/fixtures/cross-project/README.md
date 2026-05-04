# cross-project — synthetic fixtures for `--scan-projects-root`

These fixtures exist for the **token-economics** spec (Wave 0 task 0.4 → Wave 3 A3
acceptance criterion). They simulate two adjacent MonsterFlow-shaped projects sitting
under a common scan root, so `compute-persona-value.py --scan-projects-root <fixture-A>
--scan-projects-root <fixture-B>` can be exercised end-to-end without depending on real
adopter projects.

## Layout

```
cross-project/
├── project-alpha/
│   └── docs/specs/
│       ├── feature-x/{spec-review,plan}/...
│       └── feature-y/{spec-review,plan}/...
└── project-beta/
    └── docs/specs/
        └── feature-z/{spec-review,plan}/...
```

Five fixture artifact directories total: project-alpha contributes 2 features × 2 gates
= 4 dirs; project-beta contributes 1 feature × 2 gates = 2 dirs (so 6 dirs total — the
"5 fixture dirs" framing in the plan was an early count; current shape has 6 to keep
both A6 branches and the silent-persona row reachable).

Each gate directory mirrors the real `/spec-review` and `/plan` artifact graph:

- `findings.jsonl` — one JSON object per line; matches `schemas/findings.schema.json`.
  Includes `personas[]`, `unique_to_persona`, `model_per_persona`,
  `normalized_signature` (uses the schema-allowed `fixture-*` form), and the
  `(sr|pl|ck)-<10-hex>` `finding_id` shape.
- `participation.jsonl` — one row per persona that ran. At least one row per project
  has `status: ok` and `findings_emitted: 0` to exercise M4 silent-persona handling.
- `survival.jsonl` (spec-review only — survival rows are emitted by the next stage's
  Phase 0 and conventionally written into the prior gate's directory in this fixture).
  Outcomes cover `addressed`, `not_addressed`, and `rejected_intentionally`.
- `run.json` — single JSON object with `created_at` and the rest of the run manifest
  fields required by `schemas/run.schema.json`.
- `source.spec.md` — small synthetic snapshot of the source spec.md.
- `raw/<persona>.md` — per-persona reviewer markdown with `## Critical Gaps`,
  `## Important Considerations`, `## Observations` headings and a closing
  `## Verdict:` section that should NOT be counted as bullets.

## Constraints these fixtures are designed to satisfy

The Wave 1 value walk is expected to aggregate findings across BOTH projects. The
fixture data is sized so:

1. **A6 "top 3" branch fires** — at least one (persona, gate) pair has ≥3 qualifying
   rows aggregated across both projects:
   - `scope-discipline` @ spec-review: 3 rows in alpha/feature-x + 1 row in
     alpha/feature-y + 2 rows in beta/feature-z = **6 qualifying rows**.
   - `edge-cases` @ spec-review: 2 rows in alpha/feature-x + 2 rows in
     beta/feature-z = **4 qualifying rows**.
2. **A6 "(only N qualifying)" branch fires** — at least one (persona, gate) pair has
   exactly 1 qualifying row:
   - `ux-flow` @ spec-review: **1 qualifying row** (alpha/feature-x only).
   - `ambiguity` @ spec-review: **1 qualifying row** (beta/feature-z only).
3. **M4 silent-persona signal** — at least one `participation.jsonl` row has
   `status: ok` AND `findings_emitted: 0`:
   - `gaps` @ alpha/feature-x/plan, `feasibility` @ alpha/feature-x/plan,
     `cost-and-quotas` @ alpha/feature-x/spec-review, `ux-flow` and `edge-cases` @
     alpha/feature-y/spec-review, `stakeholders` @ beta/feature-z/spec-review,
     `gaps` @ alpha/feature-y/plan + beta/feature-z/plan.
4. **Uniqueness signal (M2)** — at least one row has `unique_to_persona` set to a
   single persona name (drives the M2 "unique-to-persona" rate). Most spec-review
   rows in these fixtures are intentionally unique to one persona.
5. **Survival numerator** — at least one `survival.jsonl` row has
   `outcome: addressed` so the downstream-survival metric has a positive
   numerator. `not_addressed` and `rejected_intentionally` rows are also present.

## Cross-project signal

Personas chosen so the cross-project aggregation has visible signal:

- `scope-discipline` and `edge-cases` appear in BOTH projects (so excluding either
  project drops their count visibly).
- `ux-flow`, `stakeholders`, `ambiguity` appear in only ONE project each (so the
  scan root selection materially affects which personas surface).
- `requirements` and `feasibility` appear in BOTH projects' /plan dirs.

## Synthetic disclaimer

All persona prose, finding bodies, and feature names are synthetic. Hashes use the
schema-allowed `fixture-*` / `sha256:fixture-*` prefixes; nothing in this directory
came from a real project review.
