# Scalability Analysis

**Stage:** /plan (Design)
**Focus:** Performance at scale and bottlenecks

## Role

Analyze the scalability implications of this feature.

## Checklist

- Scale dimensions: data size, request rate, user count
- Resource usage: memory, CPU, disk, network
- Bottlenecks: what limits growth?
- Complexity: algorithmic, space, time
- Caching opportunities
- Degradation modes: what happens at limits?

## Key Questions

- What happens at 10x, 100x, 1000x current scale?
- What are the hard limits?
- Where should we optimize vs keep simple?
- What needs to be lazy vs eager?
