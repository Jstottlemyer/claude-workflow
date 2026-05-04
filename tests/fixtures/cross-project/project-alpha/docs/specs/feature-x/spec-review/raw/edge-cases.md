# edge-cases — Feature X spec review

## Critical Gaps

- Concurrent edits from two browser tabs will silently overwrite; no policy stated.
- Bulk import partial-failure semantics undefined; unclear whether the whole batch rolls back or rows are imported individually.

## Important Considerations

- Behavior under network drop mid-edit not described.

## Observations

- Spec correctly notes max payload size for the synchronous endpoint.

## Verdict: REQUEST CHANGES
