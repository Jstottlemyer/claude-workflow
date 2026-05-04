# Completeness Review — install-rewrite plan

## Verdict
PASS WITH NOTES — every spec acceptance case maps to a Wave 4 task and every review-finding cluster is addressed by a Wave 1-5 task, but four small gaps need closing before /build: explicit Codex `--codex` opt-in surfacing in onboard.sh isn't a task (only echoed in D12 prose); the spec's "shellcheck-clean" non-test acceptance bar has no dedicated task or ship gate that runs `shellcheck` against `tests/test-install.sh`; the spec's "Linux guard verified manually — document in PR description" non-test bar is unowned; and a few edge cases (box-drawing terminal degradation, `--no-theme` when theme already installed, `--install-theme + --no-theme` precedence) are referenced inside design decisions but lack explicit task IDs anyone can mark "done."

## Coverage Walk — Acceptance Cases (spec §Acceptance Criteria)

| Case | Spec requirement | Plan task(s) | Covered? |
|------|------------------|--------------|----------|
| 1 | Idempotency state-based: no dup symlinks, ≤1 sentinel block, key messages present, exit 0 both runs | 4.2 | YES |
| 2 | Fast no-op fully-installed system, <3s, "everything already in place" | 4.2 | YES |
| 3 | Fresh-Mac REQUIRED hard-stop, brew install command in output, exit 1 | 4.2 | YES |
| 3a | Fresh-Mac happy path: brew bundle invoked (stub records argv), symlinks created, theme prompt declined, panel printed, exit 0 | 4.2 | YES |
| 4 | Re-install after `brew uninstall jq`: install stage runs, brew bundle invoked with `--file=Brewfile`, post-install detection true, symlink diff empty | 4.2 | YES |
| 5 | `--no-install` bypasses ALL: REQUIRED missing → no hard-stop, symlinks created, exit 0 | 4.3 | YES |
| 6a | Owner no-prompt theme symlinks created | 4.3 + 2.5 + 2.8 | YES |
| 6b | Adopter prompt-default-N declined → no theme symlink | 4.3 + 2.8 | YES |
| 6c | Adopter `--install-theme` no prompt, theme symlink created | 4.3 + 2.8 | YES |
| 6d | Existing real `~/.tmux.conf` backed up to `.bak`, theme path becomes symlink | 4.3 + 2.8 (link_file reuse) | YES |
| 7a | TTY → onboard offers graphify prompt | 4.4 + 3.3 + 3.4 | YES |
| 7b | `--non-interactive` → onboard runs but no graphify prompt (silent) | 4.4 + 3.4 | YES |
| 8 | Migration messaging: prior-install symlink detected, upgrade-diff with ≥5 bullets | 4.4 + 2.3 | YES |
| 9a | TTY-absent (`</dev/null`): no `read -rp` prompts, theme not installed, panel suppressed unless `--force-onboard` | 4.4 + 2.9 + 3.4 | YES |
| 9b | `--non-interactive` flag with TTY: same as 9a | 4.4 + 2.9 | YES |
| 9c | `--non-interactive --force-onboard`: panel runs, sub-prompts silent | 4.4 + 3.4 | YES |

All 16 acceptance assertions land in W4 tests; W4.1 (skeleton + brew-stub + has_cmd shadow) backs every case. **No missing acceptance coverage.**

## Coverage Walk — Non-test Acceptance Bar (spec §Acceptance Criteria, plus-list)

| Bar | Plan task | Covered? |
|-----|-----------|----------|
| `shellcheck install.sh scripts/onboard.sh tests/test-install.sh` returns 0 with no warnings | W2 ship criterion (shellcheck install.sh), W3 ship criterion (shellcheck onboard.sh), W4 has NO shellcheck gate | **PARTIAL** — `tests/test-install.sh` is created in W4 but no ship criterion runs shellcheck on it |
| Linux guard verified manually (no automated test) — document in PR description | none | **MISSING** — no task owns the "document in PR description" deliverable |
| README.md install one-liner still works | 5.1 | YES |
| QUICKSTART.md updated with flag surface + migration messaging | 5.2 | YES |
| CHANGELOG.md created/updated with v0.5.0 entry | 5.3 | YES |
| Onboard panel substring assertions (`/flow`, `/spec`, `dashboard/index.html`) | D12 + 4.4 (case 7) | YES — D12 pins panel content; case 7 implicitly covers via panel print |

## Coverage Walk — Review Finding Clusters (review.md)

### Blockers (10)

| # | Cluster | Plan task | Covered? |
|---|---------|-----------|----------|
| 1 | Drop wiki-export from onboard (MVP cut) | Spec §Out of Scope explicitly excludes; plan W3 has no wiki task | YES (deferred-out) |
| 2 | Theme symlinks must reuse `link_file()` backup, not raw `ln -sf` | 2.8 (explicitly says "link_file() reuse") + R4 mitigation | YES |
| 3 | `--no-install` bypasses ALL enforcement | 2.7 (tier-split decline) + 4.3 (case 5 verifies) + D2 exit matrix | YES |
| 4 | Acceptance case 1 byte-identical → state-based | Spec §Acceptance case 1 already rewritten state-based; 4.2 implements | YES |
| 5 | Add fresh-Mac happy-path case | Spec §Acceptance case 3a added; 4.2 implements | YES |
| 6 | Test harness PATH manipulation false-pass → use function-shadow + `export -f` | D11 + 4.1 | YES |
| 7 | Scope creep — wiki dropped (theme + cmux retained per Justin's owner-favored extras) | Spec §Out of Scope drops wiki; theme stays in scope; 1.1-1.4 + 2.8 implement theme | YES (cut accepted; theme intentionally retained) |
| 8 | v0.4.x → v0.5.0 migration messaging | 2.3 + D10 + 4.4 case 8 | YES |
| 9 | Non-interactive mode | D1 + D3 + 2.9 + 4.4 case 9 | YES |
| 10 | `set -euo pipefail` + brew bundle catch pattern | D8 + 2.6 | YES |

### Important (8)

| # | Cluster | Plan task | Covered? |
|---|---------|-----------|----------|
| 11 | "Loud notice" format pinned (glyph, stream, repeat, exit code) | Spec §Data&State pins it; 2.7 implements | YES |
| 12 | Owner detection hardened (realpath + git toplevel + env override) | D4 + 2.5 | YES |
| 13 | Theme prompt — owner no-prompt, adopter prompt-default-N | 2.8 + 4.3 case 6a/6b | YES |
| 14 | Linux guard | 2.1 + spec §Edge Cases | YES |
| 15 | SIGINT trap | 2.2 + D7 (security-hardened to mktemp -d) | YES |
| 16 | Plan should diagram new vs old flow (additive surgery understatement) | Architecture Summary lists 3 invariants + line-numbered task locations + "single deletion" callout | YES (diagram exists in prose form) |
| 17 | Onboard panel acceptance assertions | D12 + 4.4 case 7 | YES |
| 18 | Flag precedence for `--install-theme` + `--no-theme`; add `--no-onboard` | D1 lists 7 flags incl. precedence; spec §Edge Cases pins precedence | YES |

### Minor (2)

| # | Cluster | Plan task | Covered? |
|---|---------|-----------|----------|
| 19 | `pip3` migration explicitly out-of-scope | Spec §Out of Scope + §Integration explicit; plan 1.6 sources helper but doesn't migrate sister scripts | YES |
| 20 | cmux is cask not formula | 1.1 (Brewfile uses `cask "cmux"`) | YES |

**All 20 review findings addressed.**

## Coverage Walk — Out-of-Scope Items (spec §Out of Scope)

| Item | Plan accidentally include? |
|------|---------------------------|
| Linux support | NO — 2.1 is exit-fast guard only, no functional path |
| Auto-bootstrap brew via curl | NO — REQUIRED panel just prints URL |
| Migrate autorun off tmux | NO — tracked in spec Open Q1; no plan task |
| Per-tool install prompts | NO — single bulk confirm in 2.6 |
| Refactor 354 lines into helpers | NO — additive surgery; R8 explicitly accepts ~530-line target |
| Wiki-export indexing | NO — onboard.sh tasks 3.1-3.5 contain no wiki call |
| Adopt `python_pip` in sister scripts | NO — 1.6 only sources in install.sh |
| Theme uninstall script | NO — no plan task |
| Custom theme color overrides | NO — D5 pins fixed palette |
| Per-tool RECOMMENDED opt-in | NO — bulk in 2.6 |

**Plan respects every out-of-scope boundary.**

## Coverage Walk — Edge Cases (spec §Edge Cases)

| Edge case | Plan task | Covered? |
|-----------|-----------|----------|
| Linux user (uname guard, exit 1) | 2.1 + 4.5 (negative case N2) | YES |
| Tier-split decline (5-row table) | 2.7 | YES |
| `set -euo pipefail` + brew bundle catch | D8 + 2.6 + 4.5 (N3 brew-fail) | YES |
| SIGINT mid-install | 2.2 + D7 (mktemp -d) | YES |
| v0.4.x → v0.5.0 migration | 2.3 + D10 + 4.4 case 8 | YES |
| Theme symlink with existing real file (link_file reuse) | 2.8 + 4.3 case 6d | YES |
| Re-run on fully-installed system (<3s) | 4.2 case 2 | YES |
| `--no-theme` on system with theme already installed | NONE — D1 mentions precedence; spec §Edge says "deliberately does not remove" | **GAP** — no test case proves `--no-theme` on already-themed system is a no-op (not a regression-revert) |
| Network failure mid-`brew bundle` | D8 + 4.5 N3 | YES |
| Box-drawing terminal degradation | D12 (UX content-survives-degrade discipline) + R10 (deferred ASCII fallback) | PARTIAL — no test, but deferred-by-design |
| `--install-theme` + `--no-theme` together | D1 (precedence pinned) | PARTIAL — no test case verifies precedence at runtime |

## Coverage Walk — Open Questions (spec §Open Questions)

| OQ | Spec status | Plan resolution |
|----|-------------|-----------------|
| 1. Tmux in autorun | Tracked, not blocking | Not in plan scope (correct — separate spec) — DEFERRED CLEANLY |
| 2. `config/` file contents | "/plan resolves this" | D5 pins all three files (cmux.json 3-key, tmux.conf Ctrl-a + cyan/grey, zsh-prompt-colors.zsh 5 vars) — RESOLVED |
| 3. Versioning (one commit vs several; hardcoded "v0.5.0") | "Confirm at /plan time" | D10 resolves: pull from `VERSION` file at runtime (no hardcode); commit-count question NOT explicitly resolved | **PARTIAL** — D10 fixes the version-string-in-message problem but plan doesn't say whether W2's 10 tasks land as 10 commits, 5, or 1 squash |

## Coverage Walk — User Decisions at /spec-review Refine (8)

| # | Decision | Reflected in plan? |
|---|----------|-------------------|
| 1b | Cut wiki only (theme + cmux retained) | YES — spec §Out of Scope drops wiki; 1.1-1.4 + 2.8 retain theme + cmux |
| 2a | `--no-install` bypass-ALL semantics | YES — 2.7 + D2 + 4.3 case 5 |
| 3a | Owner no-prompt theme | YES — 2.8 + 4.3 case 6a |
| 4a | State assertions for idempotency | YES — Spec §Acceptance case 1 rewritten; 4.2 implements |
| 5b | Function-shadow `has_cmd` mock | YES — D11 + 4.1 (`export -f has_cmd`) |
| 6c | Hybrid owner-detect (realpath + git toplevel + env override) | YES — D4 + 2.5 |
| 7c | Hybrid non-interactive (auto-detect + explicit flag) | YES — D1 + D3 + 2.9 |
| 8b | Version-aware migration | YES — 2.3 + D10 + 4.4 case 8 |

**All 8 refine decisions reflected.**

## Must Fix Before Building

None. Every blocker review finding, every acceptance case, and every refine decision has a plan task. The gaps below are SHOULD-fix, not blocker.

## Should Fix

- **shellcheck on tests/test-install.sh** — Spec §Acceptance non-test bar: "shellcheck install.sh scripts/onboard.sh tests/test-install.sh returns 0." W2 + W3 ship criteria run shellcheck on install.sh and onboard.sh respectively, but W4's ship criterion is "all 9 + 3 cases green; runtime < 30s local." Add `shellcheck tests/test-install.sh` to W4.6 ship criterion (or W4.1 done-criteria).
- **Linux-guard manual-verification artifact** — Spec §Acceptance non-test bar: "Linux guard verified manually — document the manual check in PR description." No task owns drafting the PR description content. Either add a one-line W5 task (e.g., 5.5 "PR description includes Linux-guard manual-verification note") or fold into 5.3 (CHANGELOG mentions "macOS-only Linux guard added; verified manually on a Linux container — see PR #N").
- **Codex opt-in surfacing in onboard.sh** — Spec §Scope: "onboard.sh surfaces codex opt-in as a single line ('Want adversarial review? Run `/codex:setup`')." Plan task 3.5 covers it. Verified — actually present, not a gap. (Removing this bullet on second pass.)
- **`--no-theme` on already-themed system test** — Spec §Edge Cases explicitly says "`--no-theme` only governs the current run, doesn't reverse a prior install." No test case verifies this behavior (case 6 matrix doesn't include it). Add a 6e to W4.3: pre-stage system with theme symlinks present, run with `--no-theme`, assert symlinks UNTOUCHED. Cheap — same fixture setup as 6a.
- **`--install-theme` + `--no-theme` precedence test** — Spec §Edge Cases pins "`--no-theme` wins"; D1 documents the precedence. No test case asserts it. Add to W4.3 or W4.5 negative cases.
- **Commit-count for W2** — Spec Open Q3 asked "one commit or several?" Plan §Convergence Notes says "Strict sequential commit ordering 2.1→2.10" (R1 mitigation) — implies 10 commits. Make this explicit in W2 ship criterion or call it out under Open Questions/Risks so /build doesn't squash.

## Observations

- Plan adds 3 useful items NOT in spec: `MONSTERFLOW_INSTALL_TEST` env (D3 — recursion-guard), exit code 2 for unknown flags (D2 — distinguishes user-error from REQUIRED-missing), `gh auth status` 5s timeout (D9 — corporate-proxy <3s budget). All defensive, none contradict spec.
- Plan adds 5 plan-time Open Questions of its own (`MONSTERFLOW_OWNER=0`, migration under non-interactive, stage-14 `||` masking, config pre-review, bootstrap-graphify defensive edit). All five carry a "Recommend" answer; none block /build, but Justin should signal accept/decline before W3 + W5 land.
- The `wave-sequencer` is named in the agent list (7 design agents) but plan doesn't expose its raw output path — minor doc-trail gap, not a coverage gap.
- `autorun-shell-reviewer` subagent gate is correctly invoked at W2 merge (per CLAUDE.md discipline). Good catch — install.sh isn't under `scripts/autorun/` but the size + complexity justify the same review bar.
- Net delta `+180/−8` and final `~530 lines` are explicit; R8 acknowledges proximity to "extract into helpers" threshold (~600 lines) and accepts it as v1 cost. Honest sizing.
- W3 is explicitly parallel-safe with W2 once W1 closes. The "low-medium risk" framing tracks the test surface (3.4 prompt-gating is the only easy-to-break piece).
- Three-Gate Mapping (data → UI → tests) at the end of the plan is a nice consistency check that every wave produces something the next wave consumes — no orphan artifacts.
