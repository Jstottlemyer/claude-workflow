---
name: bump-version
description: Bump the VERSION file and create an annotated git tag. Use when shipping a release per the documented "VERSION + git tag" pattern.
disable-model-invocation: true
---

# /bump-version

Bump MonsterFlow's `VERSION` file and create an annotated git tag in one step.

## Usage

```bash
bash scripts/bump-version.sh <part>
```

Where `<part>` is one of: `major` | `minor` | `patch`.

## What it does

1. Reads current version from `VERSION` (e.g. `0.4.21`).
2. Increments the requested part:
   - `patch` → `0.4.21` → `0.4.22`
   - `minor` → `0.4.21` → `0.5.0`
   - `major` → `0.4.21` → `1.0.0`
3. Writes the new version back to `VERSION`.
4. Stages `VERSION` and creates a single commit: `chore: bump version to <new>`.
5. Creates an annotated tag `v<new>` pointing at that commit.

## What it does NOT do

- Does NOT push the tag (`git push origin v<new>` is left for the user).
- Does NOT update `CHANGELOG.md` (treat that as a manual editorial step before bumping).
- Does NOT modify any other file referencing the version.

## Pre-conditions checked

- Working tree is clean (refuses if there are uncommitted changes).
- Current branch is `main` (refuses otherwise; override with `--force-branch`).
- New tag does not already exist locally or on origin.

## When to invoke

- After merging the last PR for a release.
- After CHANGELOG.md is updated and committed.
- Before announcing the release.

## Output

```
Current: 0.4.21
New:     0.4.22 (patch bump)
✓ VERSION updated
✓ commit created: abc1234 chore: bump version to 0.4.22
✓ tag created: v0.4.22
Next: git push origin main && git push origin v0.4.22
```

## Implementation note

This skill is `disable-model-invocation: true` because it has irreversible side effects (commits + tags). Only the user fires it via `/bump-version`.
