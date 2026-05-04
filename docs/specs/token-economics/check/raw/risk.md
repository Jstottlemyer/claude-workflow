# Risk Check — Token Economics (v4.1 + plan.md)

**Persona:** risk (check stage)
**Verdict:** **PASS WITH NOTES** — Risk Register is solid for the engineering surface, but three public-release-week failure modes (interactive-confirm UX on first-try, salt-file mid-run corruption, content-hash best-effort wrong-attribution scope) deserve named entries before code lands.

## Must Fix

None. No blocker-class unknown that would invalidate the plan or the spec's correctness invariants.

## Should Fix

### S1 — Interactive scan-confirmation flow has no Risk Register entry, and it's the most-likely-to-fail-on-first-try Δ

The plan's mitigation for "adopter `--scan-projects-root` includes client repos" cites decision #13 (interactive flow) + `.monsterflow-no-scan` + counts-only telemetry + A10 allowlist. But the **interactive flow itself** is novel code with several first-try failure modes:

- **TTY detection on macOS Terminal vs iTerm vs tmux vs cmux vs `script(1)` wrapper:** `sys.stdin.isatty()` returns False under tmux pipe-pane (which `dev-session.sh` uses for session logging — see user CLAUDE.md). If the adopter is running `compute-persona-value.py --scan-projects-root ~/Projects` inside a tmux window that pipes stdout to a logfile, `isatty()` may return False and the script will refuse — silently skipping with "scan-roots not confirmed." Adopter sees no data, can't tell why.
- **`/wrap-insights` Phase 1c calls the script unconditionally and non-interactively** — the ONLY way an adopter ever gets cross-project data is if they run `compute-persona-value.py --scan-projects-root <dir>` manually first to populate `scan-roots.confirmed`. If the docs in `docs/persona-ranking.md` (Wave 3 task 3.7) don't make this OOBE crystal-clear, the feature ships dead-on-arrival for the Pro-friend's actual use case.
- **`scan-roots.confirmed` append race** — two concurrent `--scan-projects-root` invocations (rare but possible if adopter scripts it) can interleave appends. File is single-line-per-root so corruption is unlikely, but worth a flock or `os.O_APPEND` note.

**Add to Risk Register:**

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Interactive scan-confirmation refuses under tmux/cmux/log-piped stdin → adopter sees empty cross-project data with no signal | **Medium-High** for tmux users (Justin, default-roster adopters) | Medium (silent feature dead-on-arrival) | Document tmux gotcha in `docs/persona-ranking.md` 3.7 explicitly; add `--confirm-scan-roots` non-interactive flag for scripted bootstrapping; emit explicit `[persona-value] non-tty stdin; run \`compute-persona-value.py --confirm-scan-roots <dir>\` once interactively from a real terminal` message instead of the current counts-only line so the adopter can self-diagnose |

### S2 — Salt file mid-run corruption / partial-write is unspecified

Δ3 says: "salt at `~/.config/monsterflow/finding-id-salt` (chmod 600, generated on first run)." Plan task 1.6 implements it. **What happens if the file exists but is zero bytes, truncated mid-write, or contains non-hex garbage** — e.g., the adopter ran `>` against it from a typo, or a previous interrupted run wrote 16 bytes of a 32-byte salt?

Three concrete failure modes:
- **Zero-byte salt:** if read as empty bytes, `sha256(b"" || normalized_signature)` becomes equivalent to a public hash → drill-down IDs are guessable (defeats Δ3's threat model).
- **Truncated salt:** entropy drops silently from 256 to 64 bits without anyone noticing.
- **Race between two concurrent first-runs** (e.g., `/wrap-insights` triggered twice while the adopter is also manually running `--list-projects`): both check "file missing," both write, last-writer wins → the first run's already-emitted IDs in `persona-rankings.jsonl` are now invalid against the surviving salt → next run produces a completely disjoint ID set, breaking drill-down continuity silently.

The **worst-case wrong-attribution scenario:** the JSONL contains 45 windows of `contributing_finding_ids` salted with salt-A; salt rotates to salt-B; dashboard "Drill into finding sr-9a4b1c2d8e" returns nothing because no source finding now hashes to that ID. Adopter can't tell drill-down is broken — empty result looks indistinguishable from "no matching finding."

**Add to Risk Register:**

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Salt file zero-byte / truncated / replaced mid-window → drill-down IDs become guessable (entropy collapse) or orphaned (wrong-attribution where IDs in JSONL no longer match anything regenerable) | Low (filesystem stability) but **non-zero on first-run race / adopter typo / disk-full** | Medium | Validate salt on read: assert `len(salt) == 32 and all bytes non-zero` else regenerate AND emit `safe_log("salt_regenerated")` AND clear all `contributing_finding_ids[]` from existing rows on next compute (rather than emitting a JSONL with stale-salt IDs alongside fresh-salt IDs); write salt via `tmp + os.replace` (atomic, same pattern as the JSONL itself); document in `docs/persona-ranking.md` 3.7 that drill-down continuity resets if salt regenerates |

### S3 — "Best-effort" content-hash window reset (e2 + A4) — name the wrong-attribution scope

Spec is honest that historical attribution is approximate, but the **worst-case wrong-attribution scenario** isn't quantified anywhere. Concretely: adopter rewrites `personas/check/risk.md` from "be skeptical" to "be lenient." For up to **44 invocations** (until the new content rolls the window), the dashboard shows `risk` with retention/survival/uniqueness numbers that are the **mixed average of the old skeptical persona and the new lenient persona**. A persona-author looking at "my new lenient prompt produces 0.73 retention" is reading a number that's 90% old-prompt data.

This is what the spec calls "approximate." It's also what stakeholder-author personas would call "actively misleading for the first 6 weeks of usage." The risk isn't that the math is wrong — the risk is that the dashboard banner ("Persona scores reflect this machine's MonsterFlow runs only. Screenshots and copy-pastes share persona names + numbers — review before sharing publicly") **doesn't warn about temporal mixing across persona-content edits**.

**Add to Risk Register OR amend dashboard banner copy:**

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Persona author edits prompt, then reads dashboard rates that are 90% pre-edit data for up to 44 invocations, draws wrong conclusion about their edit | Medium (any adopter who tunes a persona) | Medium (decisions made on stale-mixed data) | Extend dashboard tooltip on `persona_content_hash` cell: "Hash recently changed — current rates may include data from prior persona content. Window stabilizes after N more invocations." Compute N as `45 - count(post-edit rows in window)` once per-dispatch hash lands in v1.1; until then, surface a generic "Hash recently changed" badge whenever current `persona_content_hash` doesn't match the hash on the oldest row in window |

### S4 — A1.5 disagreement calibration

Plan rates "Low likelihood / High impact." Q1's preliminary evidence is one probe (RedRabbit fixture, 73 dispatches). **Calibration check:**

- "Low likelihood" assumes the parent annotation format is stable across Anthropic SDK / model versions. The spec acknowledges this in A1.5 ("Permanent test catches future Anthropic format drift") — so the team already concedes drift is expected, not exceptional. That tension between "Low likelihood" in the register and "permanent test catches future drift" in A1.5 deserves resolution.
- "High impact" is right: spec re-opens, `compute-persona-value.py` switches to subagent-canonical reads (more expensive walk), but `--best-effort` exists as escape hatch.
- **What the Q1 probe might have missed:** the RedRabbit fixture is one user, one machine, one Claude Code version. If `total_tokens` annotation includes/excludes cache-read tokens differently from `usage` rows in `subagents/agent-<id>.jsonl`, agreement on the probe doesn't generalize. The **calibration is right for "format stability"** but **under-calibrated for "field semantics consistency across cache states / model versions / SDK versions."**

**Recommend:** keep "Low/High" but re-run A1.5 against fixtures from at least one additional project + one additional Claude Code version before the public-release week ships. Cheap; reduces the unknown materially.

### S5 — Two unaddressed survival classifier items: are these real gaps?

Survival shows 31/33 design recommendations addressed; 2 unaddressed (memory ceiling note + `install.sh` deferral).

- **Memory ceiling note:** Wave 1 task 1.3 says "mtime-pruned single-pass with substring pre-filter." Plan's risk register has "Heavy adopter (5 projects, 167 features) > 5s refresh — Medium/Low — mtime-prune brings 3-5s." That's runtime, not memory. **No row about memory** for adopters with, say, 5,000 session JSONLs (Q1 probe was 6427 lines; multiply by Justin's roughly 20 projects + a year of accumulation). Single-pass JSON parse with substring pre-filter is fine; what about the cumulative `parent_session_id → agentId → tokens` dict size? **Not bench-tested.** Likely fine (each entry is small) but unmeasured.
- **`install.sh` deferral:** explicit "out of band" entry in plan §Out-of-band. This is a genuine deferral — the spec writes its own `~/.config/monsterflow/README.md` lazily-or-not (§Project Discovery says "Discoverable via stderr telemetry plus a one-line README at `~/.config/monsterflow/README.md` written by `install.sh` if absent (out of scope here; opens an issue in onboarding)"). Genuine deferral, but it leaves Δ4's debug env var (`MONSTERFLOW_DEBUG_PATHS=1`) discoverable only via the spec — adopters won't find it.

**Recommend:** memory ceiling — accept as deferred (likely a non-issue; document if first heavy-adopter hits it). `install.sh` deferral — file the README issue NOW so the public-release-week adopter has the discoverability path even if the rewrite hasn't shipped.

## Observations

### O1 — Adopter-scale unknowns the plan hasn't bench-tested

- **5,000 session JSONLs** — substring pre-filter performance unmeasured at this scale; mtime prune helps but assumes consistent mtime hygiene (some adopters touch-restore files during git ops, which would invalidate the prune). Acceptable risk; document.
- **Broken parent-subagent linkage** — what if a subagent JSONL is missing entirely (Claude Code crash, user `rm`, partial sync from another machine via `~/.claude/projects/` rsync)? Pseudocode in §Cost attribution dereferences `subagent_jsonl` path but doesn't show the `FileNotFoundError` branch. Plan assumes "Q1 evidence says clean linkage." Worst case: A1.5 trips on a single missing subagent file in a 73-dispatch session and the whole compute aborts. Need explicit per-dispatch try/except with `safe_log("missing_subagent")` and skip that dispatch from cost only.
- **Windows / NTFS path quirks** — spec says "Linux support out of scope" but Windows isn't explicitly excluded. Plan task 1.1 uses `Path.resolve()` which behaves differently on case-insensitive filesystems. If any adopter is on Windows (unlikely for the Pro-friend, possible for an open-source contributor), `validate_project_root()`'s "resolved path not under `$HOME`" check breaks because `$HOME` doesn't exist as an env var on Windows. Recommend: explicit "macOS only" assertion in `compute-persona-value.py` startup with friendly bail (`sys.exit("MonsterFlow currently supports macOS only; Linux/Windows tracked in BACKLOG")`). Spec already says macOS-only out of scope; make it enforced.

### O2 — Public-release week: most likely "first 24 hours" failure modes

In likelihood order:
1. Adopter runs `--scan-projects-root` under tmux → silent skip, no data. (S1.)
2. Adopter shares dashboard screenshot → persona names leak (warning banner present but easy to miss). Persona-author-exposure carryover — covered by warning banner; still the most-likely social-leakage vector.
3. Adopter doesn't run `/wrap-insights` for 14+ days → stale-cache banner fires (e6) — graceful, not a defect.
4. Adopter on cold first-run sees 30-60s wait with no progress indicator → assumes hang, kills it. **Not in Risk Register.** Recommend stderr progress line every N projects walked.

### O3 — A1.5 escape hatch and `--best-effort` semantics interact

A1.5 disagreement aborts; `--best-effort` downgrades to warning. Plan task 1.4 says "exits non-zero unless `--best-effort`." Then `commands/wrap.md` Phase 1c invokes `compute-persona-value.py` unconditionally — **does it pass `--best-effort` or not?** If yes, `/wrap-insights` silently absorbs A1.5 disagreements and the forcing function never fires for end-users. If no, A1.5 disagreement on any production session crashes `/wrap-insights`. Plan doesn't say. **Pick one and document.** (Recommend: `/wrap-insights` does NOT pass `--best-effort`; failure is loud; adopter must explicitly run with `--best-effort` to suppress.)

### O4 — Pre-commit hook (Wave 3 task 3.6) is the right shape but adopter-installable opt-in

The pre-commit hook catches `git add -f dashboard/data/persona-rankings.jsonl` snapshot-sharing (the "Medium-likelihood / Low-impact" Risk Register entry). Right shape. But it's **opt-in and post-merge** — public-release-week adopters won't have it installed when they first try to share a snapshot. Allowlist enforcement on the file content is the actual safety net (which is correct). Minor observation: surface the install command in the dashboard's privacy banner copy ("To prevent accidental commit, run `bash scripts/install-precommit-hooks.sh`").

### O5 — Genuine strengths of the Risk Register

- A1.5 escape hatch is real and named.
- `.monsterflow-no-scan` sentinel + interactive confirmation + counts-only telemetry stack three independent privacy gates — defense in depth.
- "Salt file leaks → IDs guessable" is acknowledged; impact rated correctly (single-machine, regenerable).
- "Persona-name regex breaks under `/autorun`" is exactly the kind of integration risk that often gets missed.

The 9 entries cover the engineering surface well. The 3 additions (S1, S2, S3) close public-release-week-specific gaps; S4 + S5 + O3 are calibration / documentation tightenings, not new risks.

---

**Bet against the plan:** First production use-case will be Justin running `compute-persona-value.py --scan-projects-root ~/Projects` from his existing tmux session. `isatty()` returns False, script silently refuses, "Persona Insights" tab renders only cwd data. He'll spend 20 minutes debugging before finding the non-tty refusal log line. Fix S1 before ship.
