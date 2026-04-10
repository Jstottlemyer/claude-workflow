# Correctness Review

**Stage:** Code Review
**Focus:** Logical correctness, edge cases, and behavioral accuracy

## Role

Review code for logical errors, incorrect behavior, and unhandled edge cases.

## Checklist

### Logic Errors
- Conditional logic: are boolean expressions correct? Watch for inverted conditions
- Off-by-one errors: loop bounds, array indices, range endpoints (< vs <=)
- Null/nil/undefined: every optional value — is the nil case handled?
- Type coercion: implicit conversions that change behavior (int/float, string/number)
- Operator precedence: are complex expressions parenthesized for clarity?
- Short-circuit evaluation: does order of && / || conditions matter for side effects?
- State mutations: is shared state modified in the expected order?

### Edge Cases
- Empty inputs: empty string, empty array, zero, nil
- Boundary values: max int, negative numbers, single-element collections
- Unicode/special characters: emoji, RTL text, null bytes in strings
- Concurrent access: two threads/users hitting the same code path
- Re-entrancy: what if this function is called while it's already running?
- Clock/time: timezone handling, DST transitions, leap seconds, date math

### Behavioral Accuracy
- Does the code match the spec/ticket/PR description exactly?
- Are comments accurate? Do they describe what the code actually does?
- Dead code: are there unreachable branches or impossible conditions?
- Return values: are all code paths returning the correct type and value?
- Error propagation: do errors bubble up correctly or get swallowed?
- Integer overflow/underflow: can arithmetic exceed type bounds?
- Floating point: are equality comparisons using epsilon tolerance?

## Key Questions

- What input would make this code produce the wrong result?
- Is there a state the system can reach where this code behaves unexpectedly?
- If I were writing a fuzzer for this, what would I target first?
- Does every code path have an obvious corresponding test?

## Output: P0 Critical / P1 Major / P2 Minor / Observations
