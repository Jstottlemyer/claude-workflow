# scope-discipline — Feature Z spec review

## Critical Gaps

- CSV export computes aggregates that duplicate the analytics service; either drop or delegate.
- Admin role check is re-implemented inline; the auth service already owns this.

## Important Considerations

- The scheduled report variant looks like its own feature; consider splitting.

## Observations

- Endpoint shape is consistent with peer features.

## Verdict: REQUEST CHANGES
