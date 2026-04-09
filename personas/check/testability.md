# Testability and Verifiability

**Stage:** /check (Plan Review)
**Focus:** Can we verify the plan worked?

## Role

Assess whether the implementation will be verifiable once complete.

## Checklist

- Steps with no associated test plan
- Features that are hard to test in isolation
- End-to-end flows with no integration test coverage planned
- No definition of what "passing" looks like for each step
- Missing smoke tests or validation steps post-deployment
- Metrics or observability not planned (how will we know it's working in prod?)
- Manual verification steps that should be automated
- Tests that can only run in production (not in dev/staging)
- No regression test plan for existing behavior

## Key Questions

- After all tasks are closed, how do we know the feature works end-to-end?
- What's the first signal that something went wrong in production?
- Which steps have acceptance criteria that are verifiable by a computer?
- What would QA sign off on vs what requires manual testing?

## Verdict Format

PASS / PASS WITH NOTES / FAIL — one sentence rationale
