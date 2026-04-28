# Persona Metrics — Snapshot Directive

**Used by:** `commands/spec-review.md`, `commands/check.md` (Phase 1 step 0)
**Prompt version:** `snapshot@1.0`
**When to bump:** if the snapshot procedure, refusal conditions, or filename rules change. Update the version string here AND any caller that records `prompt_version` from this directive.

## Purpose

Before reviewer agents dispatch at `/spec-review` (or `/check`), capture an immutable snapshot of the artifact under review. The survival classifier later compares this snapshot against the revised artifact to judge what changed.

This directive does NOT apply to `/plan` — `plan.md` is synthesized fresh at `/plan` time, so there is no pre-state to snapshot.

## Source-artifact tracking vs. metrics-artifact gitignore

These are **two distinct privacy concerns**, often confused:

- **Source-artifact tracking** (this directive): the artifact under review (`spec.md` at `/spec-review`, `plan.md` at `/check`) MUST be git-tracked. We refuse to snapshot an untracked source — without it, the metric is not reproducible. This is non-negotiable.
- **Metrics-artifact gitignore** (separate, per-adopter choice): whether the adopter commits the resulting `findings.jsonl` / `survival.jsonl` / etc. to their repo. Controlled by `PERSONA_METRICS_GITIGNORE` env var; default is opt-in-to-commit for adopter projects.

Keep these two concerns mentally separate. This file enforces the former; `install.sh` handles the latter.

## Procedure

Given:
- `feature` — the spec slug (e.g. `persona-metrics`); validated against `^[a-z0-9][a-z0-9-]{0,63}$`
- `stage` — `spec-review` or `check`
- `artifact` — `spec.md` or `plan.md`

Execute these steps in order:

1. **Validate slug.** Reject if `feature` does not match `^[a-z0-9][a-z0-9-]{0,63}$`. Path-traversal characters (`/`, `\`, `..`, `:`) and absolute-path forms must be refused. On rejection: write `run.json` with `status: "failed"` and `warnings: ["invalid-slug"]`; do not snapshot.
2. **Verify source is git-tracked.** Run `git ls-files --error-unmatch docs/specs/<feature>/<artifact>` from the repo root. If exit code ≠ 0, the source is untracked or absent. On failure: write `run.json` with `status: "failed"` and `warnings: ["source-not-git-tracked"]`; do not snapshot. Surface a one-line error to the user: `[persona-metrics] cannot snapshot — docs/specs/<feature>/<artifact> is not git-tracked. Commit the artifact (or stage it) and re-run.`
3. **Ensure target directory exists.** `mkdir -p docs/specs/<feature>/<stage>/raw/`. The `raw/` subdir is for per-persona raw outputs persisted later in the same phase.
4. **Atomic copy via tmp + rename.** Copy the source to `docs/specs/<feature>/<stage>/source.<artifact>` using a tmp file:
   - Read the source artifact into memory.
   - Write to `docs/specs/<feature>/<stage>/source.<artifact>.tmp`.
   - `os.replace` (Python) or `mv -f` (POSIX shell with rename semantics) the tmp file to `source.<artifact>`. **Use `os.replace`, not `os.rename`**, for cross-platform atomic semantics (Windows `os.rename` fails when destination exists; `os.replace` does the right thing on both POSIX and Windows since Python 3.3).
5. **Rotate prior `findings.jsonl`** if present in the same `<stage>/` directory. If `findings.jsonl` exists, rename it to `findings-<UTC-ts>.jsonl` BEFORE the synthesis emit step writes the new one. Timestamp format: `%Y-%m-%dT%H-%M-%SZ` (colon-free, UTC, cross-platform safe). On same-second collision, append `-<run_id-prefix>` (8 chars of the run's UUID).
6. **Echo one-line user feedback** to the conversation:
   ```
   [persona-metrics] snapshot spec.md → spec-review/source.spec.md (rotated 0 prior findings)
   ```
   or with rotation:
   ```
   [persona-metrics] snapshot spec.md → spec-review/source.spec.md (rotated 1 prior findings → findings-2026-04-26T18-15-22Z.jsonl)
   ```

## Failure handling

The snapshot step never blocks the stage on transient failures (network, model, etc. — none apply here since this is a pure file-copy). Hard refusals (invalid slug, source not git-tracked) DO block: the user must fix the underlying issue before reviewers run.

If the snapshot succeeds but later steps in the stage fail, the snapshot remains on disk — that's fine. It's auditable as part of the stage's `run.json` by `output_paths`.

## Schema reference

Snapshot doesn't write JSONL. The only output it produces (beyond the snapshot file itself) is the user-feedback echo and contributions to the stage's `run.json` (which the synthesis-emit step writes — this directive only adds entries to the in-progress `output_paths` list and `warnings[]`).
