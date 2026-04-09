# AGENTS.md — Games

Game-specific agent roster. These agents are available when working inside the `Games/` directory and its projects.

Universal agents (swift-mentor, performance-advisor, test-writer, beta-feedback-triage, feature-flag-manager, release-notes-writer) are defined at `Mobile/.claude/AGENTS.md` and also available here.

---

## Agent Roster

### game-state-reviewer
- **Domain:** Game logic architecture, `@Observable` ViewModel patterns in game context, state machines, phase transitions, scoring/level progression, save/load logic
- **Trigger:** "Review my GameViewModel", state machine correctness, game phase logic
- **Do NOT use for:** General Swift language review, performance profiling

### swiftui-scene-builder
- **Domain:** Scaffolding new SwiftUI screens, game scenes, HUDs, menus, overlays from scratch
- **Trigger:** "Create a new screen/scene/menu/HUD"
- **Do NOT use for:** Reviewing or modifying existing views

### accessibility-guardian
- **Domain:** Evaluating SwiftUI views/screens/components against children's accessibility checklist
- **Trigger:** SwiftUI code pasted + accessibility check requested; pre-ship review for child-facing UI
- **Do NOT use for:** General Swift review, non-interactive components
- **Required:** Before every TestFlight and App Store build

---

## Overlap Rules

| Overlap Area | Use This Agent | When |
|---|---|---|
| `@Observable` / state patterns | `game-state-reviewer` | Question is about game logic or state machine correctness |
| `@Observable` / state patterns | `swift-mentor` (universal) | Question is about Swift idioms or language correctness |
| New game screen scaffolding | `swiftui-scene-builder` | Building from scratch |
| Reviewing existing game views | `swift-mentor` (universal) | Reviewing/modifying existing code |

---

## Agent Selection Decision Tree

```
What do you need? (game-specific)
|
+- New screen/scene/HUD/menu -> swiftui-scene-builder
+- Accessibility check (children's UI) -> accessibility-guardian
|
+- Code review / architecture question
    +- Is the question about game state, state machines, or game phase logic?
    |   +- YES -> game-state-reviewer
    +- NO (Swift idioms, concurrency, general patterns) -> swift-mentor (universal)
```

---

## Agent Memory Responsibilities

| Agent | What to Record |
|---|---|
| `game-state-reviewer` | Recurring state machine bugs, working ViewModel structures, save/load pitfalls |
| `accessibility-guardian` | Recurring accessibility failures, child UX patterns that passed/failed |
| `swiftui-scene-builder` | Scene scaffolding patterns, reusable component conventions |

---

## Workflow Integration (Games)

```
/brainstorm -> writing-plans -> execution -> [agents during impl] -> [gate agents] -> PR -> /wrap
```

- **During implementation:** swiftui-scene-builder, game-state-reviewer
- **Pre-ship gates (required):** accessibility-guardian
- **Pre-ship gates (recommended):** game-state-reviewer, performance-advisor (universal)
