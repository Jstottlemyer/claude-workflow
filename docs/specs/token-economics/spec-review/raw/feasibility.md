# Technical Feasibility — Round 3 Review

**Round-2 critical retired?** Yes. A1 ±5% is gone; v3 uses **exact equality on subagent rows** (A1) plus a **parent-annotation cross-check** (A1.5). Both are buildable from the JSONL layout I probed in round 2 — `subagents/agent-<id>.jsonl` files exist (verified at `~/.claude/projects/.../<session-uuid>/subagents/`), each contains per-row `usage`, and the parent's `Agent` tool_result trailing text carries the `agentId` linkage. Exact equality holds because both sides sum the same underlying token counts.

**Phase 0 spike persistence accurate?** Yes. The new "Phase 0 Spike Result (preliminary)" section faithfully records what I found: linkage via `agentId` in tool_result trailing text, persona name regex-extracted from `Agent.input.prompt`, no `parent_tool_use_id` top-level key, subagent transcripts under `subagents/agent-<id>.jsonl`. The two open questions (canonical token source, worktree placement) are correctly flagged for `/plan`.

## Critical Gaps

**None.** The round-2 critical (A1 ±5%) is genuinely fixed, and no new round-3 critical issue rises to "blocks `/plan`."

## Important Considerations

1. **Hybrid roster discovery in JS is not straightforward — it requires a server-side bundle step the spec does not name.** The spec says (line 49, line 101, A5) the dashboard renders "(never run)" rows by merging the JSONL with current `personas/{review,plan,check}/*.md` files "at render time." But `dashboard/index.html` is loaded via `file://` and deliberately avoids `fetch()` (see `index.html:79` comment and the existing `data-bundle.js` script-tag pattern from `scripts/dashboard-bundle.sh`). The JS layer **cannot enumerate the filesystem** at render time. Two viable fixes for `/plan`:
   - (a) Have `compute-persona-value.py` walk `personas/{review,plan,check}/*.md` itself and write a sibling `dashboard/data/persona-roster.js` (or embed the roster list as a top-level `meta` row in `persona-rankings.jsonl`). The "(never run)" merge then happens in Python, not JS.
   - (b) Extend `scripts/dashboard-bundle.sh` (or add a parallel bundler) to emit `persona-roster.js` alongside `data-bundle.js`.
   Either works; pick one in `/plan`. The current spec phrasing implies a JS-side capability that doesn't exist on this dashboard.

2. **`survival.jsonl` outcome enum mismatch.** Spec §Scope (line 44) and §Survival semantics (line 177) say the downstream filter is `outcome ∈ {addressed, kept}`. **`schemas/survival.schema.json` has only `addressed`, `not_addressed`, `rejected_intentionally`, `classifier_error` — there is no `kept` value.** The filter as written reduces to `outcome == "addressed"`. Either:
   - drop `kept` from the spec (the cheap fix; `addressed` already captures the intent per the schema description), or
   - extend the schema to add `kept` (heavier — needs a survival-classifier prompt revision, schema_version logic, and back-compat for existing rows).
   This is not a critical gap because the cheap fix is one-line and the metric still works, but **the spec must reconcile this before `/plan` writes pseudocode against a non-existent enum value.**

3. **`contributing_finding_ids[]` has no length cap.** A persona that runs through the full 45-window with ~5 surviving findings per run yields ~225 IDs per row, each ~13 chars (`sr-9a4b1c2d8e`), so ~3KB/row × ~150 (persona, gate) rows ≈ **450KB JSONL**. Tolerable but worth a soft cap (e.g., last 50 IDs + `truncated_count: N`) for the public-release case where someone has many projects. Not a blocker; flag for `/plan` to decide.

4. **Float idempotency via `round(x, 6)` works** — verified `python3 -c "json.dumps({'r': round(0.6590000000001, 6)})"` returns `{"r": 0.659}` and roundtrips byte-identically. **However**, A8's "byte-for-byte identical excluding `last_seen`" depends on the `contributing_finding_ids[]` sort order (spec already specifies sorted, good) AND on the JSON key order. Python's `json.dumps` preserves insertion order; if dict construction varies across runs (e.g., walking files in `glob` order), keys may shuffle. Add `sort_keys=True` to the dump call — one line, makes A8 actually verifiable.

5. **`~/.config/monsterflow/projects` follows XDG correctly** (`$XDG_CONFIG_HOME` defaults to `~/.config`, MonsterFlow as the app namespace). Good. Worth noting in spec: respect `$XDG_CONFIG_HOME` when set rather than hardcoding `~/.config`. One-line tweak; otherwise adopters who relocate XDG (rare on macOS, common on Linux even though spec says macOS-only) get a silently-ignored config file.

## Observations

- **Open Q2 (worktree placement) is empirically resolvable in 30 seconds and could be closed in this round.** I verified `~/.claude/projects/-Users-jstottlemyer-Projects-Mobile-CosmicExplorer--claude-worktrees-journal-constellation-overhaul/1649c88b-.../subagents/` exists — i.e., **worktree sessions get their own top-level `~/.claude/projects/<sanitized-worktree-path>/` entry, not a nested folder under the parent project.** Project Discovery does NOT need to follow worktree symlinks; it just needs to walk the flat `~/.claude/projects/*/` set and trust that worktrees show up as separate top-level project keys. `/plan` can mark Open Q2 closed with this one observation.
- A1.5 cross-check is a free side benefit: even after the canonical source is chosen, running the cross-check periodically catches drift if Anthropic changes the tool_result annotation format. Worth keeping as a permanent test, not just a one-shot resolution helper.
- `personas/judge.md` and `personas/synthesis.md` sit at the top level of `personas/` (not under `review/`, `plan/`, or `check/`). The hybrid roster-discovery glob `personas/{review,plan,check}/*.md` correctly excludes these, but the spec should confirm in `/plan` that judge/synthesis are intentionally excluded from the dashboard "(never run)" rendering (they're orchestration personas, not gate reviewers — yes, exclude).
- `scripts/session-cost.py` extension is mechanically straightforward — the existing `parse_entries`, `dedup_iter`, and `entry_cost` plumbing all carry over; the new path adds `walk_subagents()` and a regex extractor. No architectural changes needed.

## Verdict

**PASS WITH NOTES.** Round-2's critical (A1 ±5%) is genuinely retired by exact-equality A1 + cross-check A1.5, both buildable. The five round-3 considerations are all resolvable in `/plan` without further `/spec` revisions: (1) name the JS-roster bundling path, (2) drop `kept` from the survival filter (or extend the schema if there's a real reason), (3) decide on a `contributing_finding_ids[]` cap, (4) add `sort_keys=True` for A8, (5) honor `$XDG_CONFIG_HOME`. Open Q2 (worktree placement) is empirically closed by my probe — flat top-level entries, no symlink-following needed.
