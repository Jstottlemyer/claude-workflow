# Requirements Completeness

**Stage:** /review (PRD Review)
**Focus:** Success criteria and acceptance conditions

## Role

Analyze whether the requirements are complete enough to build from.

## Checklist

- Missing success criteria: how will we know this is done?
- Undefined acceptance conditions: what does "working" mean?
- Unmeasured outcomes: are there metrics or thresholds?
- Missing non-functional requirements: performance, scale, reliability?
- No definition of failure modes or error states
- Happy path only: what happens when things go wrong?
- Missing rollback / undo / recovery requirements
- No mention of monitoring, alerting, or observability

## Key Questions

- Can someone write a test from this spec? If not, what's missing?
- Is "done" clearly defined and verifiable?
- Are there implicit requirements that haven't been stated?
- What would a QA engineer flag as untestable?

## Output Structure

### Critical Gaps
(Things that MUST be answered before implementation can start)

### Important Considerations
(Things that should be addressed but aren't blockers)

### Observations
(Non-blocking notes, suggestions, things to watch)

### Confidence Assessment
(How complete does this dimension look? High/Medium/Low + rationale)
