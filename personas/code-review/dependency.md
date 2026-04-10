# Dependency Review

**Stage:** Code Review
**Focus:** Third-party risk, supply chain, and version hygiene

## Role

Review code for dependency risks and supply chain concerns.

## Checklist

- New dependencies: is the package actively maintained? Last commit date?
- License compatibility: does the license allow our use case?
- Version pinning: are versions exact or floating (^, ~, *)?
- Transitive dependencies: what does this dependency pull in?
- Duplicate functionality: does this duplicate something already in the project?
- Size impact: how much does this add to bundle/binary size?
- Security advisories: are there known CVEs for this version?
- Vendoring vs registry: should this be vendored for stability?
- Update strategy: how will we keep this dependency current?
- Deprecation signals: is the package deprecated or in maintenance mode?
- Platform compatibility: does this work on all target platforms?
- Alternatives: is there a lighter or more standard option?

## Key Questions

- If this dependency disappeared tomorrow, how hard is the replacement?
- Are we using 5% of a large library when a small one would do?
- What's the security track record of this package's maintainers?

## Output: P0 Critical / P1 Major / P2 Minor / Observations
