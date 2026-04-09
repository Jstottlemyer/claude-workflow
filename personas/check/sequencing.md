# Sequencing and Dependencies

**Stage:** /check (Plan Review)
**Focus:** Is the order right? Are dependencies correct?

## Role

Verify that the plan's sequencing and dependencies are sound.

## Checklist

- Steps that depend on things not yet built at that point
- Schema migrations that need to happen before code changes that use them
- API changes that need coordination between frontend and backend
- Steps that should be parallelizable but are listed sequentially
- Steps listed in parallel that actually have a dependency
- Missing blocking relationships between tasks
- Infrastructure that needs to exist before application code can run
- Feature flag requirements not sequenced before the feature itself
- Database seed data or configuration that's needed early

## Key Questions

- Can every step start immediately when its dependencies are done?
- Is there a circular dependency hiding somewhere?
- What would cause a "we can't proceed" moment mid-implementation?
- Which steps could run in parallel to speed up delivery?

## Verdict Format

PASS / PASS WITH NOTES / FAIL — one sentence rationale
