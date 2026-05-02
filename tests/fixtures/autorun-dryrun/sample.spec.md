# Sample Spec — autorun dry-run fixture

This file exists to seed `queue/sample.spec.md` for the `/autorun-dryrun`
smoke test. Real specs are written via `/spec`; this is a minimal stand-in
that lets the pipeline traverse all 8 stages with stub artifacts.

## Goal

Demonstrate that `AUTORUN_DRY_RUN=1` produces:
- review-findings.md
- risk-findings.md
- plan.md
- check.md
- build-log.md
- verify-gaps.md (with `VERDICT: COMPLIANT`)
- state.json
- pre-build-sha.txt

## Acceptance

- One placeholder route exists at `/sample`.
- A status banner reads "DRY RUN OK".
- Tests pass (no test_cmd configured → auto-pass).

## Notes

This fixture is consumed only by `tests/autorun-dryrun.sh`. Do not edit
without updating that runner's assertions.
