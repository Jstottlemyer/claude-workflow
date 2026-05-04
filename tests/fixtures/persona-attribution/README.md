# persona-attribution fixtures

Redacted real-data excerpts (and one deliberate-failure fixture) used by the
token-economics build to exercise:

- A0 — Phase 0 spike artifact check (`tests/test-phase-0-artifact.sh`)
- A10 — allowlist enforcement (`tests/test-allowlist.sh` + `tests/test-allowlist-inverted.sh`)

This directory is **committed** but every row in every `.jsonl` here must
validate against `schemas/persona-rankings.allowlist.json` (Agent B's deliverable
in Wave 0). The lone exception is `leakage-fail.jsonl` — see below.

## Filename convention

`gate-<gate>-persona-<persona>-<seq>.jsonl`

- `<gate>` ∈ `{spec-review, plan, check}` — matches the regex enforced on
  `persona_path` (`^personas/(spec-review|plan|check)/[a-z0-9-]+\.md$`)
- `<persona>` — bare persona slug (no `.md`, lowercase, hyphenated)
- `<seq>` — three-digit sequence number, **NOT a UUID**. UUIDs in filenames
  leak project context; sequence numbers do not.

Examples present today:

- `gate-spec-review-persona-scope-001.jsonl`
- `gate-plan-persona-data-model-001.jsonl`
- `gate-check-persona-risk-001.jsonl`

## Allowlisted fields (per spec §Privacy)

Top-level (all required unless noted):

- `type` — string, currently `"agent_dispatch"`
- `agentId` — 16-hex-char subagent linkage id
- `tool_use_id` — parent tool_use id (`toolu_…`)
- `parent_session_uuid` — UUID of parent CC session
- `model` — model id string (e.g. `claude-opus-4-7`)
- `usage` — object containing **only** `input_tokens`, `output_tokens`,
  `cache_read_input_tokens`, `cache_creation_input_tokens` (all integers)
- `duration_ms` — integer milliseconds
- `tool_uses` — integer count
- `total_tokens` — integer (parent-annotation total per Phase 0 spike Q1)
- `persona_path` — must match `^personas/(spec-review|plan|check)/[a-z0-9-]+\.md$`
- `gate` — string, must be one of `spec-review`, `plan`, `check`
- `timestamp` — **hour-truncated** ISO 8601 (`...:00:00Z`). Δ2 — sub-hour
  precision is forbidden because it acts as a session fingerprint.

The full machine-readable allowlist lives at
`schemas/persona-rankings.allowlist.json` (created by Wave 0 Agent B). If
the schema and this README disagree, the schema wins.

## Forbidden fields (non-exhaustive — schema is authoritative)

- finding titles, finding bodies, prompt text, message content
- file paths beyond `persona_path`
- project names, repo names, branch names
- full ISO timestamps with seconds resolution
- any field not enumerated above

## `leakage-fail.jsonl`

Contains exactly **one** otherwise-valid row with a single forbidden field
added (`finding_title: "test_canary_leakage_xyz"`). It is the M8
inverted-assertion test target — `tests/test-allowlist-inverted.sh` runs
the validator against it and asserts BOTH non-zero exit AND a stderr
violation message naming the offending field. It is the only file in this
directory permitted to fail allowlist validation, and `tests/run-tests.sh`
must invoke it via inverted-exit-code shape (`! ./tests/test-allowlist-inverted.sh`).

## Adding a new fixture

1. Capture a real `Agent` tool_result + linked `subagents/agent-<id>.jsonl`
   from your local `~/.claude/projects/<…>/`.
2. Either run `scripts/redact-persona-attribution-fixture.py` (Wave 0
   Agent B's deliverable) or hand-redact down to the allowlisted fields.
3. Hour-truncate `timestamp`. Anonymize `parent_session_uuid` (the
   sequence-zero pattern used here — `00000000-0000-0000-0000-00000000000N` —
   is fine).
4. Run `tests/test-allowlist.sh` — must pass.
5. Choose a sequence number that doesn't collide with existing files in
   the same `gate-<gate>-persona-<persona>-` prefix.

## Provenance

The `agentId`, `total_tokens`, `usage`, `duration_ms`, and `tool_uses` values
in `gate-spec-review-persona-scope-001.jsonl` row 1 are the unmodified probe
fixture from Phase 0 spike Q1 — see
`docs/specs/token-economics/plan/raw/spike-q1-result.md`. All other rows are
derived/synthetic but use real subagent IDs from the same source session
(`~/.claude/projects/-Users-jstottlemyer-Projects-RedRabbit/42dcaafa-1fbb-4d52-9344-1899381a205c/subagents/`)
to keep the linkage shape realistic.
