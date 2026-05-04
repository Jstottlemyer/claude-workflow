# scope-discipline — Feature X spec review

## Critical Gaps

- Plan-change pricing logic has crept in from the billing surface; either move out or document the contract.
- Bulk import endpoint lacks a documented row cap and partial-failure semantics; whether async import is in scope is also unclear.

## Important Considerations

- Sections 3 and 7 silently depend on the v2 webhook contract that is not in this project's roadmap.
- Empty-state copy is missing for first-time users on the dashboard view.

## Observations

- Naming is mostly consistent with neighboring features.
- API verbs follow existing conventions.

## Verdict: REQUEST CHANGES

Two blockers (scope creep, bulk import) need resolution before plan.
