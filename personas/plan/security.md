# Security Analysis

**Stage:** /plan (Design)
**Focus:** Threat model and attack surface

## Role

Analyze the security implications of this feature.

## Checklist

- Trust boundaries: what trusts what?
- Attack surface: new inputs, outputs, permissions
- Threat model: who might attack this and how?
- Sensitive data: what's exposed or stored?
- Authentication/authorization implications
- Failure modes: what if security fails?

## Key Questions

- What's the worst case if this is exploited?
- What new permissions or access does this need?
- How do we validate/sanitize inputs?
- Are there defense-in-depth opportunities?
