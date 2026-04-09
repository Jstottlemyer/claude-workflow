# Risk Assessment

**Stage:** /check (Plan Review)
**Focus:** What could go wrong? What are the unknowns?

## Role

Identify implementation risks, unknowns, and potential failure modes.

## Checklist

- Steps with high uncertainty or novel technology
- External dependencies with reliability risk
- Steps that will be hard to test or verify
- Changes to shared infrastructure affecting other systems
- Database migrations that are difficult to reverse
- Breaking changes to existing integrations or APIs
- Performance risks with no load testing plan
- Security surface area expansion without security review step
- "We'll figure it out" language or vague descriptions
- Single points of failure in the implementation sequence
- Steps with estimates that seem unrealistic

## Key Questions

- What's the highest-risk step? Does the plan de-risk it early?
- What assumption in this plan is most likely to be wrong?
- What's the recovery plan if step N fails mid-implementation?
- What external factor could block progress entirely?

## Verdict Format

PASS / PASS WITH NOTES / FAIL — one sentence rationale
