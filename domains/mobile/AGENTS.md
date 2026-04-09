# AGENTS.md

Universal agent roster for the Mobile workspace. These agents apply to all iOS projects (apps and games).

For game-specific agents, see `Games/.claude/AGENTS.md`.

---

## Agent Roster

### swift-mentor
- **Domain:** Swift language patterns, concurrency idioms, general code review, architectural decisions
- **Trigger:** Code uses incorrect Swift idioms, concurrency questions, general "review my code" requests
- **Do NOT use for:** Performance profiling (-> performance-advisor)

### beta-feedback-triage
- **Domain:** TestFlight crash log analysis, beta tester feedback triage, QA structured reports, suggesting regression tests
- **Trigger:** Crash log pasted, TestFlight feedback to triage, "what test would have caught this?"
- **Do NOT use for:** General test writing for new features (-> test-writer)

### test-writer
- **Domain:** Writing XCTest unit tests and XCUITest UI tests for new features
- **Trigger:** Feature implemented and needs test coverage, "write tests for X"
- **Do NOT use for:** Triaging existing crashes (-> beta-feedback-triage)

### feature-flag-manager
- **Domain:** Feature flag setup, management, and rollout strategy
- **Trigger:** Adding or managing feature flags

### release-notes-writer
- **Domain:** App Store release notes and changelog generation
- **Trigger:** Preparing a release, "write release notes for this version"

### performance-advisor
- **Domain:** Profiling, frame rate optimization, memory issues, Instruments-driven analysis
- **Trigger:** Active performance profiling, frame drops, memory warnings, "optimize this"
- **Do NOT use for:** General code review outside a perf investigation context

---

## Overlap Rules

| Overlap Area | Use This Agent | When |
|---|---|---|
| Performance during code review | `swift-mentor` | Incidental perf note while reviewing code |
| Performance during profiling | `performance-advisor` | Actively investigating a perf regression with data |
| Regression tests after a crash | `beta-feedback-triage` | Test suggested as part of crash root-cause analysis |
| Tests for new features | `test-writer` | Writing test coverage for new code |

---

## Agent Selection Decision Tree

```
What do you need?
|
+- Crash log or TestFlight feedback -> beta-feedback-triage
+- Release notes -> release-notes-writer
+- Feature flags -> feature-flag-manager
+- Tests for new code -> test-writer
|
+- Code review / architecture question -> swift-mentor
|
+- Performance
    +- Actively profiling / have Instruments data -> performance-advisor
    +- Incidental perf concern in code review -> swift-mentor
```

**Game-specific agents** (game-state-reviewer, swiftui-scene-builder, accessibility-guardian) are defined in `Games/.claude/AGENTS.md` and available when working inside `Games/`.

---

## Agent Memory Responsibilities

Each agent writes to its own memory directory under `.claude/agent-memory/<agent-name>/`:

| Agent | What to Record |
|---|---|
| `swift-mentor` | Swift idiom corrections, project-specific patterns, concurrency pitfalls |
| `beta-feedback-triage` | Recurring crash patterns, known flaky tests, device/OS failure patterns |
| `performance-advisor` | Profiling baselines, known bottlenecks, optimization wins |
| `test-writer` | Project test conventions, naming patterns, coverage gaps |

---

## Workflow Integration

Agents are invoked at specific stages of the canonical workflow:

```
/brainstorm -> writing-plans -> execution -> [agents during impl] -> [gate agents] -> PR -> /wrap
```

- **During implementation:** swift-mentor, test-writer, feature-flag-manager
- **Pre-ship gates (recommended):** performance-advisor, beta-feedback-triage (if beta data exists)
- **Post-ship:** beta-feedback-triage, release-notes-writer
