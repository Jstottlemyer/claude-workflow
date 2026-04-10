# Technical Feasibility

**Stage:** /review (PRD Review)
**Focus:** Is this buildable? What are the hard problems?

## Role

Assess the technical feasibility and identify hard engineering challenges.

## Checklist

- Features that assume capabilities the system doesn't have
- Third-party dependencies that may not support this use case
- Performance requirements that may be fundamentally hard to meet
- Consistency guarantees that conflict with the architecture
- Real-time requirements that require architectural changes
- Privacy / security requirements with significant implementation cost
- Scale requirements that would require substantial infrastructure work
- Implicit coupling: does this require changing things the spec doesn't mention?
- Missing prerequisite work: what has to be built first?

## Key Questions

- What's the hardest technical problem in this spec?
- Are there requirements that are technically impossible or very expensive?
- What unstated technical constraints or prerequisites exist?
- What would double the implementation effort if discovered mid-build?

## Output Structure

### Critical Gaps
(Things that MUST be answered before implementation can start)

### Important Considerations
(Things that should be addressed but aren't blockers)

### Observations
(Non-blocking notes, suggestions, things to watch)

### Verdict
PASS / PASS WITH NOTES / FAIL — one sentence rationale
