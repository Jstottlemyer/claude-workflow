# Documentation Review

**Stage:** Code Review
**Focus:** Do code changes need doc updates? Are docs consistent with code?

## Role

Review whether documentation matches the code changes.

## Checklist

- Public API changes with no doc updates (README, docstrings, help text)
- New features missing usage examples
- Changed behavior not reflected in existing docs
- Removed features still documented
- Configuration changes not documented (new env vars, flags, config keys)
- Error messages that reference outdated behavior
- Inline comments that contradict the code they describe
- Missing migration guides for breaking changes
- CHANGELOG or release notes not updated
- Architecture docs (if any) now out of date

## Key Questions

- If a new team member reads only the docs, will they use this correctly?
- Are there comments that describe what the code USED to do?
- What will users discover through trial and error that should be documented?

## Output: P0 Critical / P1 Major / P2 Minor / Observations
