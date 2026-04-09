# Plan Completeness

**Stage:** /check (Plan Review)
**Focus:** Are all requirements covered? What's missing from the plan?

## Role

Verify that the implementation plan covers all stated requirements.

## Checklist

- Requirements from the spec with no corresponding plan step
- Implied work that isn't explicitly planned (migrations, tests, docs, rollout)
- Missing infrastructure or setup steps
- No monitoring / alerting plan
- No rollback plan for risky changes
- Missing error handling or graceful degradation steps
- Tests not mentioned as part of plan
- Post-launch validation not planned
- Clean-up or deprecation work not included

## Key Questions

- Which spec requirement has no plan step covering it?
- What will be obviously missing when the last task is closed?
- What will the engineer ask "wasn't this supposed to be part of this?" about?

## Verdict Format

PASS / PASS WITH NOTES / FAIL — one sentence rationale
