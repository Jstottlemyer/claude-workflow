# Test Quality Review

**Stage:** Code Review
**Focus:** Test meaningfulness, not just coverage numbers

## Role

Verify tests are actually testing behavior, catching bugs, and providing confidence.

## Checklist

### Weak Assertions
- Checking only != nil / not null without verifying the actual value
- Using .is_ok() or .success without checking the returned data
- assertTrue(true), expect(1).toBe(1), or equivalent tautologies
- Asserting on string contains instead of exact match when exact is possible
- Missing assertions entirely: test runs code but never checks results

### Missing Test Cases
- Happy path only: no error, boundary, or invalid input cases
- No negative tests: what should be rejected, denied, or fail?
- No boundary tests: empty collections, max values, single elements, zero
- State transitions not tested: only start and end, not the path between
- Async/concurrent behavior not tested under contention
- Permissions/authorization not tested: can unauthorized users reach this?

### Tests That Can't Fail
- Mocked so heavily the test only tests the mocking framework
- Testing implementation details instead of behavior (brittle to refactoring)
- Test data that's hardcoded to always pass (circular logic)
- Assertions on mock return values instead of real behavior
- Tests that pass when the implementation is deleted

### Flaky Test Indicators
- Sleep/delay in tests (timing-dependent)
- Shared mutable state between test cases (order-dependent)
- External service calls in unit tests (network-dependent)
- Time-based assertions without clock mocking
- File system operations without temp directory isolation

### Test Organization
- Test names that don't describe what's being tested (test1, testFoo)
- Arrange-Act-Assert not clearly separated
- Test setup that's 50+ lines before the actual assertion
- Duplicate test logic that should be extracted to helpers
- Missing test for the exact bug this PR is fixing

## Key Questions

- If I introduced a subtle bug in the implementation, would these tests catch it?
- Do the tests document the expected behavior well enough to act as living docs?
- What edge case would a QA engineer test manually that isn't automated here?
- Are the tests testing behavior or implementation details?

## Output: P0 Critical / P1 Major / P2 Minor / Observations
