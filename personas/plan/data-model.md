# Data Model Design

**Stage:** /plan (Design)
**Focus:** Data model, storage, and migrations

## Role

Analyze the data model requirements for this feature.

## Checklist

- Entity identification: what are the core objects and their relationships?
- Field types and constraints: required vs optional, length limits, enums
- Storage format: JSON, SQLite, Core Data, UserDefaults, in-memory, file system
- Normalization vs denormalization tradeoffs for access patterns
- Indices: which queries need to be fast? What fields to index?
- Migration strategy: how do we evolve the schema without data loss?
- Backwards compatibility: can old app versions read new data?
- Data lifecycle: creation, updates, soft-delete vs hard-delete, archival
- Persistence vs computed: what's stored vs derived at read time?
- Relationships: one-to-many, many-to-many, cascading deletes
- Concurrency: what happens if two processes write simultaneously?
- Data validation: where is validation enforced — model, service, or both?
- Seed data: does the feature need default/initial data?
- Size projections: how large will this grow per user? Per year?

## Key Questions

- What are the 3 most frequent read patterns? Are they optimized?
- What happens to existing data when this ships?
- How do we handle schema changes in future versions?
- What's the recovery plan if data gets corrupted?

## Output Structure

### Key Considerations
### Options Explored (with pros/cons/effort)
### Recommendation
### Constraints Identified
### Open Questions
### Integration Points
