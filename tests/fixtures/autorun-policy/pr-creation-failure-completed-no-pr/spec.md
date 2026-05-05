# Stub spec — pr-creation-failure-completed-no-pr

A trivial change identical to clean-merged, except the `gh pr create` stub returns nonzero. Used to confirm the `completed-no-pr` final-state path: artifacts are written, but no PR exists.

Acceptance: `morning-report.final_state == "completed-no-pr"`; pipeline does not retry; logs contain no token material.
