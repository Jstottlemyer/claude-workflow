---
description: Show the session workflow reference card
allowed-tools: ""
---

Display this workflow reference card to the user:

```
╔══════════════════════════════════════════════════════════════╗
║                    SESSION WORKFLOW                         ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║  PROJECT SETUP (once per project)                            ║
║  /kickoff  →  constitution + agent roster                    ║
║                                                              ║
║  FEATURE (full pipeline)                                     ║
║  /brainstorm  →  /review  →  /plan  →  /check  →  /build    ║
║     define       6 PRD       6 design   5 plan     execute   ║
║     (Q&A)        agents      agents     agents     (parallel)║
║  + firecrawl (research) · context7 (API docs)                ║
║                                                              ║
║  WORK-SIZE SCALING                                           ║
║  Bug fix:      describe it → fix it → verify                 ║
║  Small change: /brainstorm (quick) → /build                  ║
║  Feature:      full pipeline above                           ║
║  V2/Rework:    revise existing spec → full pipeline          ║
║                                                              ║
║  PARALLEL WORK                                               ║
║  "work on X, Y, and Z in parallel"                           ║
║    → Each dispatched to a subagent                           ║
║                                                              ║
║  IN-SESSION DISCIPLINE                      [Superpowers]    ║
║  → systematic-debugging · verification-before-done           ║
║  → requesting-code-review · ralph-loop (micro-iteration)     ║
║                                                              ║
║  CODE REVIEW                                                 ║
║  Quick:  superpowers requesting-code-review                  ║
║  PR:     /code-review plugin                                 ║
║  Full:   10 parallel code-review personas                    ║
║                                                              ║
║  ARTIFACTS                                                   ║
║  docs/specs/constitution.md     (project principles)         ║
║  docs/specs/<feature>/spec.md   (living spec)                ║
║  docs/specs/<feature>/review.md (PRD review findings)        ║
║  docs/specs/<feature>/plan.md   (implementation plan)        ║
║  docs/specs/<feature>/check.md  (gap checkpoint)             ║
║                                                              ║
║  SESSION END                                                 ║
║  /wrap → summary, learning triage, git loose ends            ║
║                                                              ║
╠══════════════════════════════════════════════════════════════╣
║  AGENTS: review(6) plan(6) check(5) code-review(8)          ║
║  + judge · synthesis · domain agents                         ║
║                                                              ║
║  PLUGINS                                                     ║
║  Always-on:  superpowers · context7                          ║
║  On-demand:  firecrawl · code-review · ralph-loop            ║
║              playwright                                      ║
║  Periodic:   claude-md-management · skill-creator            ║
║              claude-code-setup                               ║
║                                                              ║
║  Superpowers: in-session execution discipline                ║
║  Plugins: specialized capabilities                           ║
║  You say WHAT. Claude handles HOW.                           ║
╚══════════════════════════════════════════════════════════════╝
```

Do NOT add any commentary. Just display the card.
