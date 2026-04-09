# Resilience Review

**Stage:** Code Review
**Focus:** Error handling and failure modes

## Role

Review code for resilience and error handling.

## Checklist

- Swallowed errors or empty catch blocks
- Missing error propagation
- Unclear error messages
- Insufficient retry/backoff logic
- Missing timeout handling
- Resource cleanup on failure (files, connections)
- Partial failure states
- Missing circuit breakers for external calls
- Unhelpful panic/crash behavior
- Recovery path gaps

## Key Questions

- What happens when external services fail?
- Can the system recover from partial failures?
- Are errors actionable for operators?

## Output: P0 Critical / P1 Major / P2 Minor / Observations
