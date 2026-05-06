# Fixture (c) — synthesis-no-go-halted

Synthesis emits `OVERALL_VERDICT: NO_GO` plus a single `check-verdict` fence with `verdict: "NO_GO"`. NO_GO is a hardcoded block (AC#5 / spec line 359 — "always, regardless of policy"); the run halts at the check stage and never reaches verify or PR creation.

**Expected `final_state`:** `halted-at-stage`
**Spec AC coverage:** AC#9 (final_state="halted-at-stage"), AC#18 (NO_GO → halted fixture).
