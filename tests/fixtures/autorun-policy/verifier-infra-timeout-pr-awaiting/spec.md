# Stub spec — verifier-infra-timeout-pr-awaiting

Trivial change identical to clean-merged, except the verifier stub exits 124 (timeout) — exercises the infra-error classifier path.

Acceptance: pipeline produces a PR even though the verifier failed an infra check, because `verify_infra_policy=warn` is the overnight default.
