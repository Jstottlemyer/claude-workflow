# Screenshot Style Review

Review simulator screenshots against CosmicExplorer's visual style rules. This is the standard workflow for auditing UI before committing visual changes.

## Steps

1. **Start the review server** (if not already running):
   ```bash
   lsof -ti:8425 | xargs kill 2>/dev/null
   python3.11 scripts/screenshot-review.py &
   ```
   Server runs at http://localhost:8425

2. **Capture screenshots** — take simulator screenshots (Cmd+S in Simulator saves to Desktop).

3. **Screenshots auto-import** — on startup, the tool auto-imports all `Simulator Screenshot*.png` files from `~/Desktop` and loads them into the review grid. You can also drag-and-drop, paste (Cmd+V), or use the file picker for additional screenshots.

4. **Cleanup** — clicking "Remove" on a screenshot deletes it from the review tool AND removes the Desktop original. "Clear All" does the same for all screenshots at once.

5. **Audit each screenshot** against the checklist. Rules are loaded from `scripts/screenshot-rules.json` and include:
   - **CartoonIcon only** — no `Image(systemName:)` anywhere
   - **CosmicFont everywhere** — no `.system(.rounded)` for visible text
   - **60pt touch targets** — all interactive elements sized for children
   - **20pt+ fonts** — all child-facing text legible
   - **No text truncation** — no ellipsis or clipping
   - **High contrast** — sufficient contrast, no color-only state
   - **VoiceOver labels** — all interactives labeled
   - **Reduce motion** — animations gated on `accessibilityReduceMotion`
   - **Transparent backgrounds** — all icons/images transparent
   - **Theme colors** — using `theme.primaryAccent`, mode accents hardcoded
   - **Gear icon top-right** — consistent position, 20pt icon, 44pt target
   - **Button labels** — no icon-only without accessibility label
   - **Consistent art style** — generated avatars/icons match cartoon style
   - **Avatar image quality** — correct features, no artifacts, transparent bg
   - **Edge spacing efficiency** — no excessive padding wasting screen space

6. **For each flagged violation**, the UI requires structured details:
   - **Element** (required) — which specific element is affected (e.g., "astronaut1 avatar", "Done button")
   - **Source file** — file and approximate line (e.g., "AvatarView.swift:30")
   - **What's wrong & how to fix** (required) — describe exactly what you see and what it should look like

   The export will warn if any flagged violations are missing required details.

7. **Add new rules** — click "+ Add Rule" in the header to create custom rules on the fly. New rules are saved to `scripts/screenshot-rules.json` and persist across sessions. Use this when you discover new patterns during review.

8. **Export plan items** — click "Export Plan Items" to generate a markdown summary with structured columns (View, Rule, Element, Source, Fix). Copy to clipboard and paste into the plan document.

## Rules File

Rules live in `scripts/screenshot-rules.json`. You can:
- **Add rules from the UI** — "+ Add Rule" button, saved automatically
- **Edit rules in the JSON** — manually edit `scripts/screenshot-rules.json`
- **Share rules** — the JSON file is committed to the repo

## When to Use

- After any visual change (polish pass, new view, theme change, image regeneration)
- Before committing UI code
- During the pre-ship accessibility gate
- When playtesting reveals visual inconsistencies
- **After generating/regenerating avatar or icon images** — always review for art quality

## Port

8425 (kill before restarting: `lsof -ti:8425 | xargs kill`)
