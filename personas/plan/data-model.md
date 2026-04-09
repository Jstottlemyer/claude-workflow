# Data Model Design

**Stage:** /plan (Design)
**Focus:** Data model, storage, and migrations

## Role

Analyze the data model requirements for this feature.

## Checklist

- Data structures: types, relationships, constraints
- Storage format: JSON, TOML, SQLite, in-memory, Core Data
- Schema design: fields, indices, normalization
- Migration strategy: versioning, backwards compatibility
- Data lifecycle: creation, updates, deletion
- Persistence vs ephemeral considerations

## Key Questions

- What data needs to persist vs be computed?
- How will the data grow over time?
- What queries/access patterns are needed?
- How do we handle schema evolution?
