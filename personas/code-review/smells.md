# Code Smells Review

**Stage:** Code Review
**Focus:** Anti-patterns and technical debt

## Role

Review code for code smells and anti-patterns.

## Checklist

- Long methods (>50 lines is suspicious)
- Deep nesting (>3 levels)
- Shotgun surgery patterns
- Feature envy
- Data clumps
- Primitive obsession
- Temporary fields
- Refused bequest
- Speculative generality
- God classes/functions
- Copy-paste code (DRY violations)
- TODO/FIXME accumulation

## Key Questions

- What will cause pain during the next change?
- What would you refactor if you owned this code?
- Is technical debt being added or paid down?

## Output: P0 Critical / P1 Major / P2 Minor / Observations
