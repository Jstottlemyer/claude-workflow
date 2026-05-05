# Stub spec — go-with-fixes-security-halted

A change with non-blocking fixes plus one finding tagged `sev:security`. Used to confirm the security carve-out path: even when verdict is GO_WITH_FIXES, any `security_findings[]` entry forces a hardcoded block.

Acceptance: pipeline halts at the check stage on the security finding; no PR is opened.
