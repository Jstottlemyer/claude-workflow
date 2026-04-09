# Wiring Review

**Stage:** Code Review
**Focus:** Installed-but-not-wired gaps

## Role

Detect dependencies, configs, or libraries that were added but not actually used.

## Checklist

- New dependency in manifest but never imported
  - Swift: package in Package.swift but no import
  - Go: module in go.mod but no import
  - Node: package in package.json but no import/require
- SDK added but old implementation remains
  - Added analytics but still using print statements
  - Added validation library but still using manual checks
- Config/env var defined but never loaded
  - New plist entry that isn't accessed in code
- Feature flags defined but never checked

## Key Questions

- Is every new dependency actually used?
- Are there old patterns that should have been replaced?
- Is there dead config that suggests incomplete migration?

## Output: P0 Critical / P1 Major / P2 Minor / Observations
