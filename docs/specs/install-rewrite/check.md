# `install-rewrite` Plan Checkpoint

**Checked:** 2026-05-04
**Plan:** `docs/specs/install-rewrite/plan.md` (sha256 `9424fb4d…`)
**Reviewers:** 5 plan personas (completeness, sequencing, risk, scope-discipline, testability) + Codex adversarial
**Findings:** 20 (10 blocker · 7 important · 3 minor)

## Overall Verdict: **NO-GO**

Testability returned **FAIL** on the test mock strategy (validated empirically: `export -f has_cmd` is shadowed by install.sh's own line-21 redefinition on macOS bash 3.2.57). Codex adversarial pass surfaced **5 additional plan-vs-reality blockers** that escaped the 5 reviewers — most consequential: D4 owner-detect introduces a semantic regression (current `PWD == REPO_DIR` defends against accidental owner-mode; new `script_dir == git_root` would mark Justin as OWNER from any cwd because his install.sh lives at the git root).

The blockers are concrete and bounded. Plan revisions to land before re-`/check` total ~10 surgical edits. No spec revision required.

## Reviewer Verdicts

| Dimension | Verdict | Key Finding |
|---|---|---|
| Completeness | PASS WITH NOTES | 0 must-fix; 5 should-fix (shellcheck miss on tests, missing assertions for already-themed re-runs) |
| Sequencing | PASS WITH NOTES | 2 must-fix (1.6 placement comment, CHANGELOG source-of-truth direction); off-by-one on W2 commit count |
| Risk | PASS WITH NOTES | 3 must-fix (subagent gate threshold, T1 supply-chain has no R-row, brew transitive-deps preview) |
| Scope Discipline | PASS WITH NOTES | 0 must-fix; 4 cuttable items proposed (21→17 tasks possible) |
| Testability | **FAIL** | D11 mock strategy broken (empirically validated); 4 must-fix |
| Codex Adversarial | (not voted) | 12 findings; 5 NEW blockers including owner-detect regression, brew-bundle-wrap-fiction, printf %q vs zsh mismatch, flag-parse top-of-file conflict, link_file .bak overwrite |

## Must Fix Before Building (10 blockers)

### B1 — Mock strategy swap (Testability + Codex confirm)

`export -f has_cmd` is shadowed by install.sh's line-21 `has_cmd()` redefinition. Validated empirically on macOS bash 3.2.57. Whole 12-case test plan rests on this.

**Fix:** swap to PATH-stub model. Test creates `$TMPSTUBS/brew` and `$TMPSTUBS/has-target/<name>` files (executable shell stubs that echo argv to `$STUB_LOG` and return chosen exit code), prepends `$TMPSTUBS` to `PATH` before sourcing install.sh. The hardcoded `[ -x "/opt/homebrew/bin/$1" ]` checks in `has_cmd` need to become PATH-aware OR add an explicit `MONSTERFLOW_HASCMD_OVERRIDE` env var the function honors.

### B2 — D4 owner-detect introduces semantic regression (Codex)

Current `PWD == REPO_DIR` is defensive (running from outside the repo flips you to ADOPTER mode, hiding owner-only behavior). Proposed `script_dir == git_root` would mark Justin as OWNER from any cwd because his install.sh lives at the git root — including invocations from inside an adopter project's cwd. Worse than today.

**Fix:** combine BOTH conditions: `PWD == REPO_DIR AND script_dir == git_root`. Or scope `realpath` (`pwd -P`) to symlink resolution only, not relocation. Plan calls this "hardening"; it is regression for the dogfood case.

### B3 — D8 "wrap brew-bundle" is fiction — install.sh has no brew-bundle today (Codex)

Plan frames Stage 5 as "wrapping" existing behavior. install.sh has zero brew-bundle calls. /build must add the entire stage from scratch — including argv parsing for the `[Y/n]` confirm, brew-bundle stub-friendliness, post-install detection re-run to validate the install actually fixed the missing tools, and the catch-failure messaging.

**Fix:** rewrite D8/W2-2.6 task body to "ADD brew-bundle install stage from scratch" (not "wrap"). Add sub-tasks for confirm-prompt, stub-friendliness, post-install re-detection.

### B4 — D6 `printf %q` is bash escaping but `.zshrc` is sourced by zsh (Codex)

`%q` uses bash-specific syntax (`\$''` for control chars) that may not parse the same way under zsh. A path with special chars breaks the source line silently.

**Fix:** use single-quote escaping (`'` and `'\''` for embedded singles) — POSIX-portable across bash and zsh. Or write a zsh-compatible literal directly.

### B5 — D1 flag-parse-before-Linux-guard conflicts with current top-level side effects (Codex)

install.sh today computes `REPO_DIR` (line 7), `VERSION` (line 9), and prints the installer banner (lines 11-15) BEFORE any flag parse could go. `install.sh --help` will still touch repo files and print the banner unless the top is restructured more aggressively than the plan admits.

**Fix:** move banner + computed-vars below the flag-parse + Linux-guard block, OR have `--help` short-circuit before any I/O (early `exit 0` if `--help` detected via simple grep before any computation).

### B6 — `MONSTERFLOW_INSTALL_TEST` recursion guard sites unspecified (Testability)

The env var is named in D3/R2/D11 but the W2 task list doesn't say where in install.sh it short-circuits. Without guarding the line 318-326 `bash tests/run-tests.sh` invocation, tests/test-install.sh forks bash tests/run-tests.sh which forks tests/test-install.sh = fork-bomb.

**Fix:** add explicit W2 task 2.9b: "Wrap line 305-316 plugin-install AND line 318-326 test-suite-validate behind `MONSTERFLOW_INSTALL_TEST=1` short-circuit (in addition to MONSTERFLOW_NON_INTERACTIVE prompt-suppression)." Both env vars; two distinct concerns (recursion-prevention vs prompt-suppression).

### B7 — Brew-stub state lifecycle never specified (Testability)

Cases 1, 3a, 4 each need different stub states (persistent across two runs vs argv-recording vs mid-test mutation). Plan doesn't say where stub lives, how state resets, how state persists.

**Fix:** W4 task 4.1 ship criterion expanded: "Brew stub binary in `$BATS_TMPDIR/stubs/brew` with state file at `$STUB_STATE`; reset between cases via `setup_test()`; argv recorded to `$STUB_LOG`."

### B8 — Case 7a `script -q /dev/null` wrong on macOS BSD (Testability)

BSD `script` (Darwin) takes `script [-q] <file> bash -c '...'` with positional file argument. There's no `-c` flag; `/dev/null` cannot be the typescript target.

**Fix:** use `expect -c 'spawn ...'` for TTY simulation, OR drop case 7a from automation and document it as manual-only (keep case 7b for non-interactive coverage).

### B9 — autorun-shell-reviewer subagent gate threshold + invocation undefined (Risk + Codex)

Plan's W2 ship criterion calls for the subagent but doesn't define a pass threshold or who invokes it. Per CLAUDE.md root, autorun-shell-reviewer is on-demand only — Justin invokes it.

**Fix:** pin (a) threshold: High = block, Medium = document, Low = ignore; if 3+ Highs, split the wave; (b) WHO invokes: Justin manually before merging W2 — /build agent does NOT auto-invoke.

### B10 — Security T1 supply-chain has no R-row in plan's risk register (Risk)

Plan.md R1-R10 doesn't include the config/* tampering case. Security made it Threat T1.

**Fix:** add R11 "config/* supply chain — adversary commits malicious cmux.json/tmux.conf/zsh-prompt-colors.zsh" with mitigation: "tests/test-config-content.sh greps for `curl|wget|nc|bash <(|eval` against config/* and fails CI on any match." Add as W4 task 4.7.

## Should Fix (7 important)

- **S1** — brew transitive-deps preview before `[Y/n]` confirm (Risk MF3)
- **S2** — CHANGELOG source-of-truth direction inverted (Sequencing MF2)
- **S3** — W2 commit count off-by-one (10 vs 9) (Sequencing + Completeness)
- **S4** — pin `/bin/bash` (not `/opt/homebrew/bin/bash`) in test invocations for bash 3.2 fidelity (Risk + Testability)
- **S5** — cmux requires macOS ≥14: add pre-flight `sw_vers -productVersion` check (Risk SF4)
- **S6** — `[ -t 0 ]` collides with tests piping stdin: add `MONSTERFLOW_FORCE_INTERACTIVE=1` env override (Risk SF5 + Codex)
- **S7** — `link_file()` `.bak` overwrites prior backup: bump to `.bak.YYYYMMDDHHMMSS` (Codex)

## Observations (3 minor)

- **O1** — W1 task 1.6 placement comment "After SIGINT trap, before migration detect" is wave-order-misleading (SIGINT trap is W2)
- **O2** — `shellcheck tests/test-install.sh` missing from W4 ship criterion (spec mandates it)
- **O3** — Scope-discipline's C1 cut (drop MONSTERFLOW_INSTALL_TEST env) is REJECTED by check finding ch-recursionguardundefined06 — keep it; it serves the recursion-prevention concern that NON_INTERACTIVE doesn't

## Conflicts Resolved (Judge dedup)

- **Mock strategy** — Testability validated empirically; Codex confirmed via shell mechanic. Same finding, different angles. Merged into B1.
- **Owner-detect** — Codex flagged the regression; no other reviewer caught it. Single source but Codex is empirical. Per session memory ("Codex catches plan-vs-reality drift — apply inline, not as minority opinion"), promoted to B2 blocker.
- **Recursion guard** — Testability + Scope-discipline disagreed. Scope said "drop the env var (redundant)"; Testability said "site unspecified." Resolution: keep the env var (B6), reject scope cut (Observation O3).
- **Subagent gate** — Risk and Codex independently flagged. Merged into B9.

## Agent Disagreements Resolved

- Scope-discipline C1 (drop MONSTERFLOW_INSTALL_TEST) vs Testability B6 (specify where it short-circuits): **Testability wins.** Different concerns (prompt-suppression vs recursion-prevention) genuinely deserve different env vars.
- Sequencing MF2 (flip CHANGELOG dependency) vs Plan W5 5.3 (install.sh canonical): **kept as S2 should-fix** — either direction is defensible; pick at /build time.

## Path Forward

**Recommended:** address the 10 blockers via plan revision (~10 surgical edits, ~30 min Justin-time), re-run /check on the affected dimensions only (testability, risk, codex re-pass), then proceed to /build.

**Alternative:** override to GO WITH FIXES — proceed to /build with explicit instructions to address the 10 blockers as the FIRST tasks before any wave kicks off. Higher risk: the test-mock-strategy blocker (B1) could trigger /build to discover the issue mid-implementation and rework downstream tasks.

**My lean: revise + re-check.** The blockers are concrete, the fixes are bounded, and the cost of re-running /check on 5 dimensions (~3 min wall-clock) is much less than the cost of /build discovering a foundational test-strategy bug 3 hours in.

---

## v1.2 Re-Check Verdict (post-fix-now)

**Plan revised to v1.2** (sha256 `9a159413…`, 389 lines). 10 blockers + 7 should-fix from v1.0 addressed in v1.1; Codex re-pass on v1.1 surfaced 7 small pseudocode bugs which were patched inline → v1.2.

**Re-Check dispatched on testability + risk + Codex re-pass:**

| Re-Check Dimension | v1.0 Verdict | v1.2 Verdict | Resolution |
|---|---|---|---|
| Testability | **FAIL** (4 must-fix) | **PASS WITH NOTES** | All 4 RESOLVED, empirically re-validated on bash 3.2.57. 2 minor should-fix remain (NF1 stateful brew-stub body, NF2 expect script location) — both addressed in v1.2 plan W4 task 4.1 ship criterion. |
| Risk | PASS WITH NOTES (3 must-fix) | **PASS** | All 3 must-fix RESOLVED, all 5 should-fix landed. 2 new minor (SF6-v2 array idiom, SF7-v2 cmux cask deps) addressed in v1.2 D8 patch. |
| Codex (re-pass on v1.1) | (NEW) | 7 small findings | All 7 patched inline into v1.2 — D1 macOS-14 location, D1 function-defs-first note, D6 quote helper double-quoting, D8 array idiom, D8 Brewfile-derived preview, D11 N2 PATH-stub uname, D4 `pwd -P` symlink resolution. |

**Final verdict: GO.** All FAIL dimensions resolved. All must-fix items addressed. Plan is implementation-ready.

Outstanding minor items deferred to /build:
- Sequencing S2 (CHANGELOG source-of-truth direction) — pick at PR-write time
- Risk carryovers SF1 (combined migration+theme banner copy), RECOMMENDED-tier failure differentiation in D8 catch — small inline tweaks during W2-2.6 implementation
- Testability v1.0 carry-forwards SF4/SF5/SF7/O5 — small W4 tweaks during 4.1-4.5 implementation
