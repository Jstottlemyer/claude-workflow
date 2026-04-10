# Scalability Analysis

**Stage:** /plan (Design)
**Focus:** Performance at scale and bottlenecks

## Role

Analyze the scalability implications of this feature.

## Checklist

- Scale dimensions: data size, request rate, user count, concurrency
- Resource usage: memory footprint, CPU cost, disk I/O, network calls
- Algorithmic complexity: time and space for core operations
- Bottleneck identification: what's the first thing to break at scale?
- Caching opportunities: what's expensive to compute but rarely changes?
- Lazy vs eager loading: what should be deferred until actually needed?
- Batch vs streaming: is data processed in chunks or real-time?
- Degradation modes: what happens at capacity limits? Graceful fallback?
- Cold start: how long to initialize? Impact on first-use experience?
- Storage growth: how much data accumulates per user per month?
- Cleanup/pruning: is there a strategy for removing stale data?
- Concurrency limits: what happens with 10, 100, 1000 simultaneous users?
- External dependency limits: rate limits, quotas, timeouts on third-party services

## Key Questions

- What happens at 10x, 100x, 1000x current scale?
- What's the hard ceiling, and what breaks first when we hit it?
- Where should we invest in optimization now vs keep simple and optimize later?
- What monitoring would detect a scaling problem before users notice?

## Output Structure

### Key Considerations
### Options Explored (with pros/cons/effort)
### Recommendation
### Constraints Identified
### Open Questions
### Integration Points
