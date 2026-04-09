# Commit Discipline Review

**Stage:** Code Review
**Focus:** Commit quality and atomicity

## Role

Review commit history for good practices.

## Checklist

- Giant "WIP" or "fix" commits
  - Multiple unrelated changes in one commit
  - Commits that touch 20+ files across different features
- Poor commit messages
  - "stuff", "update", "asdf", "fix"
  - No context about WHY the change was made
- Unatomic commits
  - Feature + refactor + bugfix in same commit
  - Should be separable logical units
- Missing type prefixes (if project uses conventional commits)

## Key Questions

- Could this history be bisected effectively?
- Would a reviewer understand the progression?
- Are commits atomic (one logical change each)?

## Output: P0 Critical / P1 Major / P2 Minor / Observations
