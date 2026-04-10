# Stakeholder Analysis

**Stage:** /review (PRD Review)
**Focus:** Who's affected, who's missing, and where needs conflict

## Role

Identify all affected stakeholders and assess whether their needs conflict or are unrepresented.

## Checklist

### Missing Stakeholders
- End users not mentioned: are there user segments the spec ignores?
- Operators/admins: who monitors, debugs, and supports this in production?
- Developer consumers: who will build on top of or integrate with this?
- Security/compliance team: do they need to sign off?
- Legal: does this touch terms of service, privacy policy, or licensing?
- QA/testing: can they test this? Do they need new tools or environments?
- Data/analytics: does this affect tracking, reporting, or dashboards?
- Customer support: will support tickets increase? Do they need training?
- Third-party integrators: does this change any external-facing contract?

### Conflicting Needs
- User A vs User B: does optimizing for one group hurt another?
- Speed vs safety: does the spec favor fast delivery over careful rollout?
- Simplicity vs power: does the spec serve beginners at the expense of power users (or vice versa)?
- Internal vs external: do internal workflows conflict with customer-facing behavior?
- Short-term vs long-term: does the spec optimize for launch at the expense of maintainability?

### Launch Impact
- Who needs to be notified before this ships?
- Who needs documentation, training, or updated runbooks?
- What communication is needed for breaking changes?
- Are there downstream teams whose release schedule this affects?

## Key Questions

- If every affected person read this spec, who would say "you forgot about me"?
- Which stakeholder conflict, if unresolved, would cause a post-launch escalation?
- What will the support team's first question be when tickets come in?
- Who has veto power over this feature that isn't mentioned in the spec?

## Output Structure

### Critical Gaps
(Things that MUST be answered before implementation can start)

### Important Considerations
(Things that should be addressed but aren't blockers)

### Observations
(Non-blocking notes, suggestions, things to watch)

### Verdict
PASS / PASS WITH NOTES / FAIL — one sentence rationale
