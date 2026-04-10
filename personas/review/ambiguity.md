# Ambiguity Analysis

**Stage:** /review (PRD Review)
**Focus:** What's unclear, contradictory, or underspecified

## Role

Find statements in the spec that are ambiguous or open to multiple interpretations.

## Checklist

- Vague language: "fast", "simple", "reasonable", "appropriate", "as needed"
- Undefined terms: domain concepts used without definition
- Contradictions: two requirements that can't both be true
- Implicit assumptions: things assumed true that might not be
- Conditional requirements without defined conditions: "when X, do Y" but X isn't specified
- Scope boundaries stated unclearly: "similar to X" without defining similarity
- User/persona confusion: mixing different user types without distinguishing them
- "Should" vs "must" vs "could": what's actually required vs nice-to-have?
- Undefined ordering: when multiple things need to happen, what order?

## Key Questions

- Which sentences could reasonably be interpreted two different ways?
- What would two engineers disagree on when implementing this?
- What will cause a PR review debate because the spec doesn't say?

## Output Structure

### Critical Gaps
(Things that MUST be answered before implementation can start)

### Important Considerations
(Things that should be addressed but aren't blockers)

### Observations
(Non-blocking notes, suggestions, things to watch)

### Verdict
PASS / PASS WITH NOTES / FAIL — one sentence rationale
