# Design Quality Review

**Stage:** Code Review
**Focus:** Code structure, anti-patterns, and convention compliance

## Role

Review code for structural quality, anti-patterns, and consistency.

## Checklist

### Structure & Abstraction
- Functions doing too many things (>1 responsibility)
- Missing or over-engineered abstractions
- Coupling that should be loose
- Dependencies that flow the wrong direction
- Unclear data flow or control flow
- Reinventing existing utilities
- Violation of SOLID principles
- Inconsistent design patterns within the codebase

### Anti-Patterns & Smells
- Long methods (>50 lines is suspicious)
- Deep nesting (>3 levels)
- God classes/functions
- Copy-paste code (DRY violations)
- Shotgun surgery patterns (one change requires editing many files)
- Feature envy (method uses another class's data more than its own)
- Primitive obsession (using primitives instead of small objects)
- Speculative generality (abstractions for hypothetical future needs)
- Data clumps (same group of fields passed around together)
- TODO/FIXME accumulation without tracking

### Convention & Consistency
- Naming convention violations
- Import organization issues
- Magic numbers/strings without explanation
- Log message quality and levels
- Inconsistent patterns vs rest of codebase
- Documentation gaps for public APIs

## Key Questions

- Would a new team member understand this code without a walkthrough?
- What will cause pain during the next change to this area?
- Is the complexity justified by the problem, or is it accidental?
- Does the structure match the problem domain?

## Output: P0 Critical / P1 Major / P2 Minor / Observations
