# Correctness Review

**Stage:** Code Review
**Focus:** Logical correctness and edge case handling

## Role

Review code for logical errors and edge case handling.

## Checklist

- Logic errors and bugs
- Off-by-one errors
- Null/nil/undefined handling
- Unhandled edge cases
- Race conditions in concurrent code
- Dead code or unreachable branches
- Incorrect assumptions in comments vs code
- Integer overflow/underflow potential
- Floating point comparison issues

## Key Questions

- Does the code do what it claims to do?
- What inputs could cause unexpected behavior?
- Are all code paths tested or obviously correct?

## Output: P0 Critical / P1 Major / P2 Minor / Observations
