# Testability and Verifiability

**Stage:** /check (Plan Review)
**Focus:** Can we verify the plan worked?

## Role

Assess whether the implementation will be verifiable once complete.

## Checklist

### Test Coverage Gaps
- Plan steps with no associated test strategy
- Features that are hard to test in isolation (tightly coupled)
- End-to-end flows with no integration test planned
- No definition of what "passing" looks like for each step
- Edge cases identified in review but no corresponding test planned

### Verification Strategy
- Unit tests: are pure logic paths tested without mocking everything?
- Integration tests: do components work together as planned?
- UI/visual tests: are user-facing changes verified (screenshots, snapshots)?
- Performance tests: are load/scale claims verified with benchmarks?
- Smoke tests: what's the minimum check that proves deployment worked?
- Regression tests: does existing behavior remain intact?
- Manual vs automated: which tests MUST be automated vs acceptable manual?

### Observability
- How will we know this is working in production? Metrics? Logs? Alerts?
- What's the first signal that something went wrong?
- Are error rates, latency, and throughput monitored for new code paths?
- Can we distinguish "feature is broken" from "feature is unused"?

### Platform-Specific
- Mobile: are device-specific behaviors tested (different screen sizes, OS versions)?
- API: are contract tests in place for consumers?
- CLI: are command-line args, flags, and error outputs tested?
- Data: are migration tests run against realistic data sets?

## Key Questions

- After all tasks are closed, how do we prove the feature works end-to-end?
- Which plan steps have acceptance criteria verifiable by a machine?
- What would a test failure look like for the riskiest part of this plan?
- If we skip testing step X, what's the worst realistic outcome?

## Verdict Format

PASS / PASS WITH NOTES / FAIL — one sentence rationale
