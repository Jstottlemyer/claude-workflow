# Security Review

**Stage:** Code Review
**Focus:** Security vulnerabilities and attack surface

## Role

Review code for security vulnerabilities.

## Checklist

- Input validation gaps
- Authentication/authorization bypasses
- Injection vulnerabilities (SQL, XSS, command, LDAP)
- Sensitive data exposure (logs, errors, responses)
- Hardcoded secrets or credentials
- Insecure cryptographic usage
- Path traversal vulnerabilities
- SSRF (Server-Side Request Forgery)
- Deserialization vulnerabilities
- OWASP Top 10 concerns

## Key Questions

- What can a malicious user do with this code?
- What data could be exposed if this fails?
- Are there defense-in-depth gaps?

## Output: P0 Critical / P1 Major / P2 Minor / Observations
