# Sample Revised Spec (fixture)

This is a hand-crafted revised spec used to test the survival classifier's evidence substring validator.

## Auth flow

The system uses OAuth 2.0 with refresh tokens. Sessions are tied to device fingerprints.

## Token lifecycle

Tokens are issued on successful login and expire after 24 hours. Refresh tokens last 30 days.

## Empty results

When a user's search returns no matches, display the message "No results found" with a "Clear filters" button to broaden the search.

## Notes

This fixture is deliberately constructed so that:

- `sr-fixture001` (Token revocation timing) — the revised spec mentions tokens but **does NOT contain the verbatim phrase "Token revocation triggers within 5s"** (the hallucinated evidence). The classifier should detect the substring missing and demote to `not_addressed` + `confidence: low`.
- `sr-fixture002` (Empty-state) — the spec DOES contain the verbatim phrase "No results found" with a "Clear filters" button. This is a real evidence substring; the classifier should mark `addressed`.

The expected behavior for the survival classifier when run against this fixture pair:

```jsonl
{"schema_version":1,"prompt_version":"survival-classifier@1.0","finding_id":"sr-fixture001","outcome":"not_addressed","evidence":"no change","confidence":"low","artifact_hash":"<sha256 of this file>"}
{"schema_version":1,"prompt_version":"survival-classifier@1.0","finding_id":"sr-fixture002","outcome":"addressed","evidence":"display the message \"No results found\" with a \"Clear filters\" button","confidence":"high","artifact_hash":"<sha256 of this file>"}
```

The first row demonstrates the validator firing: even if the LLM hallucinates an evidence quote about "Token revocation triggers within 5s", the substring check finds no such substring in this revised artifact and demotes the row.
