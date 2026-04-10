# Security Analysis

**Stage:** /plan (Design)
**Focus:** Threat model and attack surface

## Role

Analyze the security implications of this feature.

## Checklist

- Trust boundaries: what trusts what? Where are the boundaries?
- Attack surface: what new inputs, outputs, or permissions does this add?
- Threat model: who might attack this, what do they gain, how would they try?
- Sensitive data: what's exposed, stored, transmitted, or logged?
- Authentication: does this create new auth flows or bypass existing ones?
- Authorization: who can do what? Are permissions checked at every layer?
- Input validation: what user-controlled data enters the system?
- Output encoding: is data sanitized before display or storage?
- Secrets management: API keys, tokens, credentials — how stored and rotated?
- Transport security: is data encrypted in transit and at rest?
- Third-party risk: do new dependencies introduce vulnerabilities?
- Audit trail: are security-relevant actions logged?
- Failure modes: what happens when security controls fail? Fail open or closed?
- Compliance: does this touch data with regulatory requirements (PII, COPPA, GDPR)?

## Key Questions

- What's the worst case if this is exploited? What's the blast radius?
- What would a penetration tester try first?
- Are there defense-in-depth layers, or does one failure expose everything?
- What security assumptions are we making that might not hold?

## Output Structure

### Key Considerations
### Options Explored (with pros/cons/effort)
### Recommendation
### Constraints Identified
### Open Questions
### Integration Points
