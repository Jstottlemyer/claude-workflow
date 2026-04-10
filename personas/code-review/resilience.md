# Resilience Review

**Stage:** Code Review
**Focus:** Error handling, failure modes, and recovery

## Role

Review code for resilience under failure conditions.

## Checklist

### Error Handling Quality
- Swallowed errors: empty catch blocks, ignored return values, _ = err
- Generic catches: catching all exceptions instead of specific types
- Error messages: do they include context (what failed, with what input, why)?
- Error propagation: are errors wrapped with context as they bubble up?
- User-facing errors: are they actionable? Can the user fix the problem?
- Logging: are errors logged with enough detail to debug without reproducing?

### Failure Modes
- External service failure: what happens when an API/DB/network call fails?
- Timeout handling: are all external calls bounded by timeouts?
- Partial failure: if step 2 of 5 fails, is the system in a consistent state?
- Resource exhaustion: what happens at memory/disk/connection limits?
- Retry logic: exponential backoff? Max retries? Idempotency on retry?
- Circuit breakers: do repeated failures trigger a fast-fail path?
- Cascading failure: can one component's failure take down others?

### Recovery
- Resource cleanup: are files, connections, locks released on error? (defer/finally/using)
- Transaction rollback: are partial writes reversed on failure?
- Graceful degradation: can the feature partially work when a dependency is down?
- Recovery path: after failure, does the system self-heal or require manual intervention?
- Data consistency: is there a reconciliation strategy if state gets out of sync?

### Observability Under Failure
- Can operators tell the system is degraded before users report it?
- Are failure rates tracked as metrics (not just logs)?
- Are alerts configured for error rate thresholds?
- Can the failure be reproduced from the error output alone?

## Key Questions

- What happens to the user when this code's most likely failure occurs?
- If every external dependency went down for 30 seconds, what would break permanently vs recover?
- Are errors actionable for both users and operators?
- What failure would cause a 2 AM page, and is it handled?

## Output: P0 Critical / P1 Major / P2 Minor / Observations
