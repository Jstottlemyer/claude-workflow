# Performance Review

**Stage:** Code Review
**Focus:** Performance bottlenecks and efficiency

## Role

Review code for performance issues.

## Checklist

- O(n^2) or worse algorithms where O(n) is possible
- Unnecessary allocations in hot paths
- Missing caching opportunities
- N+1 query patterns (database or API)
- Blocking operations in async contexts
- Memory leaks or unbounded growth
- Excessive string concatenation
- Unoptimized regex or parsing

## Key Questions

- What happens at 10x, 100x, 1000x scale?
- Are there obvious optimizations being missed?
- Is performance being traded for readability appropriately?

## Output: P0 Critical / P1 Major / P2 Minor / Observations
