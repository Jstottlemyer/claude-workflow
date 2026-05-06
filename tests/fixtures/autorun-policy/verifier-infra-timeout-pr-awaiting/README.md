# Fixture (b) — verifier-infra-timeout-pr-awaiting

Synthesis emits clean GO + valid `check-verdict` fence, but verifier exits with infrastructure timeout (exit 124). With overnight-default `verify_infra_policy=warn`, this routes through `policy_act` to `policy_warn` → sticky `RUN_DEGRADED=1` → auto-merge gate trips → PR is still created and awaits human review.

**Expected `final_state`:** `pr-awaiting-review`
**Spec AC coverage:** AC#9 (final_state="pr-awaiting-review"), AC#18 (verifier infra timeout fixture), spec line 392 (only infra errors are warn-eligible).
