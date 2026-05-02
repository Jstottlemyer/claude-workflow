# Example Feature: CLI `--version` Flag

**Created:** 2026-04-12
**Constitution:** (example — would reference the project's constitution version here)
**Confidence:** 0.94

> **This is a reference example** showing the shape of a spec produced by the upgraded `/spec` command. It is illustrative — the feature itself is intentionally tiny so the artifact stays readable. Use this as a template, not a requirement.

## Summary

Add a `--version` flag to the `MonsterFlow` install script so users can verify which version they installed without inspecting internals. Outputs the version string and exits 0.

## Scope

### In Scope
- `install.sh --version` prints the version (from a `VERSION` file at the repo root) and exits.
- `VERSION` file added at repo root, hand-edited on release (semantic versioning: MAJOR.MINOR.PATCH).
- Help text (`install.sh --help`) mentions `--version`.

### Out of Scope
- Auto-bumping `VERSION` on commit or tag.
- Version-checking against a remote (e.g., "you're X versions behind").
- Publishing to a package manager.

## Approach

**Chosen: file-based version** — single `VERSION` file at repo root, read by `install.sh`. Rationale: simplest possible, no build step, trivial to inspect or bump by hand.

**Alternatives considered (and rejected):**
- *Embed version as a constant in `install.sh`* — requires editing the script on every release, easy to forget. Rejected.
- *Derive from `git describe`* — elegant when git is present, but fails when users install from a tarball with no `.git/`. Rejected.

## UX / User Flow

1. User runs `./install.sh --version`
2. Script reads `VERSION` file from its own directory
3. Prints version string (e.g., `MonsterFlow 0.3.1`) to stdout
4. Exits 0

If `VERSION` is missing: print `MonsterFlow (version unknown)` to stderr, exit 1.

## Data & State

- New file: `VERSION` at repo root. Contents: a single line, MAJOR.MINOR.PATCH (e.g., `0.3.1`).
- No runtime state. `install.sh` reads the file synchronously on each invocation.

## Integration

- Touches: `install.sh` (add flag parsing), `VERSION` (new), `README.md` (add install verification note).
- No dependencies on other commands.
- Does not affect the pipeline commands (`/kickoff`, `/spec`, etc.) — purely an install-script concern.

## Edge Cases

- **`VERSION` file missing**: stderr warning, exit 1. Distinguishes from "version is X" vs. "we don't know."
- **`VERSION` file empty**: treat as missing.
- **`VERSION` file has extra whitespace / comments**: read first non-empty, non-comment line; trim.
- **Both `--version` and another flag**: `--version` wins and exits before other flags are processed.

## Acceptance Criteria

1. `./install.sh --version` prints `MonsterFlow <version>` matching `VERSION` contents, exits 0.
2. With `VERSION` removed, `./install.sh --version` prints `MonsterFlow (version unknown)` to stderr, exits 1.
3. `./install.sh --help` output includes a line documenting `--version`.
4. README has a "Verifying your install" section referencing `--version`.

## Open Questions

None — spec closed clean.
