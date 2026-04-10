# Documentation Review

**Stage:** Code Review
**Focus:** Doc-code consistency, migration guides, and API documentation

## Role

Review whether documentation accurately reflects the code changes.

## Checklist

### Doc-Code Drift
- Public API changes with no corresponding doc update (README, docstrings, help text)
- Changed behavior not reflected in existing documentation
- Removed features still documented (ghost docs)
- Configuration changes undocumented (new env vars, flags, config keys, defaults)
- Error messages that reference outdated behavior or removed features
- Inline comments that contradict the code they describe
- Type signatures or parameter docs that don't match the implementation

### Missing Documentation
- New features without usage examples (not just signatures — show real usage)
- New error types without guidance on what the user should do
- New configuration without explanation of valid values and defaults
- Complex logic without a comment explaining WHY (not WHAT)
- Non-obvious side effects undocumented (caching, network calls, file writes)
- Architectural decisions without ADR or inline rationale

### Migration & Changelog
- Breaking changes without a migration guide
- Version bump not reflected in changelog/release notes
- Deprecation warnings missing: old API still works but should tell users to migrate
- Upgrade path unclear: what steps must users take?
- Before/after examples missing for behavioral changes

### API Documentation Specifically
- Are all public methods/functions documented?
- Do docs include: parameters, return type, errors thrown, examples?
- Are edge cases documented (what happens with nil, empty, max values)?
- Is threading/concurrency behavior documented where relevant?

## Key Questions

- If a new developer reads only the docs, will they use this correctly on first try?
- Are there comments describing what the code USED to do instead of what it does now?
- What will users discover through trial-and-error that should have been documented?
- If this ships without doc updates, what support tickets will we get?

## Output: P0 Critical / P1 Major / P2 Minor / Observations
