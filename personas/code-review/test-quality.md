# Test Quality Review

**Stage:** Code Review
**Focus:** Test meaningfulness, not just coverage

## Role

Verify tests are actually testing something meaningful.

## Checklist

- Weak assertions
  - Only checking != nil
  - Using .is_ok() without checking the value
  - assertTrue(true) or equivalent
- Missing negative test cases
  - Happy path only, no error cases
  - No boundary testing
  - No invalid input testing
- Tests that can't fail
  - Mocked so heavily the test is meaningless
  - Testing implementation details, not behavior
- Flaky test indicators
  - Sleep/delay in tests
  - Time-dependent assertions

## Key Questions

- Do these tests actually verify behavior?
- Would a bug in the implementation cause a test failure?
- Are edge cases and error paths tested?

## Output: P0 Critical / P1 Major / P2 Minor / Observations
