# Fixture (d) — go-with-fixes-security-halted

Synthesis emits `OVERALL_VERDICT: GO_WITH_FIXES` plus a `check-verdict` fence with `verdict: "GO_WITH_FIXES"` AND a non-empty `security_findings[]` (one entry tagged `sev:security`). Per spec line 359, security findings are a hardcoded block (always fires regardless of `verdict_policy`). Pipeline halts at the check stage.

**Expected `final_state`:** `halted-at-stage`
**Spec AC coverage:** AC#4 (security carve-out — hardcoded block), AC#9 (final_state="halted-at-stage"), AC#18 (GO_WITH_FIXES + security finding fixture).
