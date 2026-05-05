# Fixture (a) — clean-merged

Clean overnight run: synthesis emits `OVERALL_VERDICT: GO` plus a single `check-verdict` fence with verdict GO, zero blocking findings, zero security findings. Verifier exits 0 with non-empty body. PR creation succeeds and auto-merge fires.

**Expected `final_state`:** `merged`
**Spec AC coverage:** AC#9 (final_state="merged"), AC#18 (canonical "clean → merged" fixture).
