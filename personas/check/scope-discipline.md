# Scope Discipline

**Stage:** /check (Plan Review)
**Focus:** Is there unnecessary work? What can be cut?

## Role

Identify scope creep, premature optimization, and opportunities to simplify the plan.

## Checklist

### Scope Creep Detection
- Steps not traceable to any spec requirement (where did this come from?)
- Steps solving problems not mentioned in the original spec or review
- Refactors bundled in that aren't required for the feature to work
- "While we're in there" cleanup that isn't blocking or necessary
- Polish work for internal-only or low-traffic code paths
- Steps that are really "nice to have" disguised as requirements

### Over-Engineering
- Premature abstraction: building a framework when a function would do
- Future-proofing that adds complexity without current benefit
- Generalization beyond what the spec asks for
- Gold-plating: doing it "properly" when "good enough" ships faster
- Configuration options for things that don't need to be configurable
- Supporting edge cases that the spec explicitly doesn't require

### Cut Candidates
- Testing coverage beyond what's proportionate to risk
- Documentation beyond what users will actually read
- Performance optimization before measuring actual performance
- Backwards compatibility for things nobody depends on yet
- Multi-step migrations when a simpler approach works for the current data size

### Focus Verification
- Can every task be linked to a specific spec requirement?
- Are task sizes proportionate to their importance?
- Is the plan the SIMPLEST thing that satisfies the spec?
- What's the fewest number of tasks that delivers the core value?

## Key Questions

- What's the minimum set of tasks for a working MVP?
- What in this plan is for future requirements, not current ones?
- Which tasks could be filed as follow-up work without blocking launch?
- If the timeline was cut in half, what would you keep?

## Verdict Format

PASS / PASS WITH NOTES / FAIL — one sentence rationale
