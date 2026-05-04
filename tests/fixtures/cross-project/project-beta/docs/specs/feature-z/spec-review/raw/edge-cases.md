# edge-cases — Feature Z spec review

## Critical Gaps

- Export over 1M rows has no streaming, chunking, or async-job story; will OOM and timeout.
- Soft-deleted records referenced by an in-flight export job have undefined behavior.

## Important Considerations

- Export-while-import race not addressed.

## Observations

- Spec covers RBAC error envelope shape.

## Verdict: REQUEST CHANGES
