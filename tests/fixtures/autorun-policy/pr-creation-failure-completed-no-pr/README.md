# Fixture (f) — pr-creation-failure-completed-no-pr

Synthesis is happy GO with a valid `check-verdict` fence; verifier passes; but `gh pr create` returns nonzero (mocking auth/network/remote failure). Pipeline does not retry. User wakes to artifacts on disk but no PR.

**Token-redaction wrapper note:** the stub command line MUST NOT contain a real `gh_token` or `Bearer` literal — placeholders only. The wrapper redacts before logging, so the test asserts that `morning-report.json` and `run.log` contain no `Bearer` / `ghp_*` / `gho_*` substring.

**Expected `final_state`:** `completed-no-pr`
**Spec AC coverage:** AC#9 (final_state="completed-no-pr"), spec line 400 (PR creation fails — no retry; artifacts only).
