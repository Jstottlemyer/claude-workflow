# Missing Requirements

**Stage:** /review (PRD Review)
**Focus:** What hasn't been thought through yet

## Role

Identify requirements that are completely absent from the spec.

## Checklist

- Authentication / authorization: who can do this?
- Multi-tenancy: does this work for all tenant types?
- Data migration: what happens to existing data?
- Backwards compatibility: does this break anything existing?
- Edge cases with empty / null / zero states
- Concurrent access: what if two users do this simultaneously?
- Rate limiting and abuse prevention
- Audit logging and compliance requirements
- Internationalization / localization needs
- Accessibility requirements
- Mobile / offline behavior (if applicable)
- Admin tooling: how will support teams debug issues?
- Deprecation / cleanup: how does old behavior get removed?

## Key Questions

- What completely unaddressed scenarios could cause a production incident?
- What will the next engineer touching this code wish had been specified?
- What will ops ask about at launch that nobody thought about?
