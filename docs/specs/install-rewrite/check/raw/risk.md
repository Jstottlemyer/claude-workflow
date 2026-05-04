# Risk Review — install-rewrite plan

**Stage:** /check · **Persona:** risk
**Subject:** Stress-test the 10-row Risk register in plan.md vs Security's 12 threats and unaccounted edges. Where would I bet against this plan succeeding?

## Verdict

**PASS WITH NOTES** — the plan's risk register is *concretely* mitigated where it overlaps with Security's 12 threats (R5↔T9, R6↔T6, R4↔T9-class, R2↔T12 all cleanly traced), and the wave-sequencing invariants (Linux guard between lines 2-4; SIGINT trap before first `.tmp` write; migration detect before symlink mutation) are real risk reducers. But there are **6 unaccounted-for risks** the register doesn't name, **2 Security threats not converted into a plan risk row** (T1 supply-chain, T2 brew-cask transitive), and **1 ship-criterion that lacks a pass threshold** (the `autorun-shell-reviewer` subagent gate on W2 — what's the High-finding count that blocks merge?). None are existential. Three are blockers in the sense that resolving them at /check is materially cheaper than at /build. The rest are "Should Fix" or "Observations."

## Must Fix Before Building

### MF1 — `autorun-shell-reviewer` subagent gate has no pass threshold
**Location:** plan.md W2 ship criterion (line 161): "before merging W2, dispatch `autorun-shell-reviewer` against the cumulative diff."

The plan calls the subagent gate but doesn't define what constitutes a pass. Per CLAUDE.md the subagent returns High/Medium/Low findings and "treat its High findings as blocking." Apply the same explicit contract to W2:

- **Block merge:** any High finding.
- **Document & defer:** Medium findings get a 1-line acknowledgment in the commit body (`subagent-medium: <1-line summary> — accepting because <reason>`).
- **Ignore:** Low findings.

If 3+ High findings come back, that's a signal the wave was too big — split into 2.6 (install + decline) and 2.8 (theme) sub-PRs and re-run. Pin this in the plan so /build doesn't have to re-litigate at gate time.

### MF2 — T1 (supply-chain) has no plan-level row
**Location:** Security threat T1 (compromised MonsterFlow repo / fork / `.zshrc` source line as persistence anchor) vs Risk register R1-R10.

The plan addresses *parts* of T1 implicitly (D6 quotes the `.zshrc` source path, D7 scopes the SIGINT trap, the test config-content grep gate is mentioned in security.md L196-203) — but no Risk-register row names the threat, so /build has no checklist item for it. The closest row is R5 (`.zshrc` path with spaces) but that's the wrong axis: T1 is "compromised repo ships hostile theme content," not "valid theme content can't tolerate spaces in path."

**Fix:** add **R11 — Compromised repo content lands in shell-init trust chain (T1)**. Mitigation already designed by Security (L195-203): ship `tests/test-config-content.sh` that greps `config/*.zsh|*.conf|*.json` for `curl|wget|nc |bash <\(|eval |source <\(` and fails the build. This is a 10-line test file; add it to W4 task list or split as new W4.7. Also add a one-line CI gate in `tests/run-tests.sh`. Without an R-row pointing at it, the test will get cut "for time."

### MF3 — T2 (brew cask transitive trust) has no user-visible mitigation
**Location:** Security T2 + Recommendation L218-227 (show resolved install set via `brew bundle list` before confirm).

Security recommended showing the user the resolved install set via `brew bundle list --file=Brewfile | sed 's/^/  - /'` BEFORE the brew confirm prompt. Plan task 2.6 (D8) just shows the `if ! brew bundle install` catch — no preview step. Spec UX section (L142-148) shows the user a hand-curated 4-line list (`gh / shellcheck / jq / cmux`) but that's a hardcoded display, not derived from the actual Brewfile. If a future Brewfile commit adds a tool, the displayed list silently lies.

**Fix:** add explicit preview step to W2 task 2.6: parse Brewfile (`awk '/^(brew|cask)/ {print $2}' Brewfile`) and display the actual resolved set before `read -rp "Proceed? [Y/n]: "`. Also resolves Security Open Q5 ("does `brew bundle list` faithfully print the install set BEFORE resolution?" — by parsing the Brewfile directly we sidestep the question). Without this, a Brewfile-add-a-tool commit can land without the install prompt being honest about what runs.

## Should Fix

### SF1 — Backward-compat: v0.4.x adopter who has a real-file `~/.tmux.conf` from a prior non-MonsterFlow install
**Location:** R4 mitigation references `link_file()` BACKUP→.bak and Acceptance case 6d.

R4's mitigation says "Acceptance case 6d" handles backup-on-existing-real-file. Re-checked the spec: case 6d (spec.md L523) pre-stages `~/.tmux.conf` as a real file with known content and asserts the `.bak` backup is created. Good. But the **specific upgrade path** Risk-prompt called out is **v0.4.x → v0.5.0 where the prior MonsterFlow install pre-dates the theme stage** — the adopter may have a `~/.tmux.conf` that they wrote themselves (no MonsterFlow involvement) and then the v0.5.0 theme stage runs. Case 6d does test this; the gap is that case 8 (migration messaging) doesn't combine with case 6d (theme backup). An adopter on v0.4.2 who has a real `~/.tmux.conf` and re-runs at v0.5.0 hits BOTH the migration banner AND the theme-prompt — and the migration message doesn't warn them that proceeding will back up their tmux.conf.

**Fix:** in W2 task 2.3 (migration detect), the upgrade banner should add one line if the theme stage will run: `"⚠ This upgrade will offer to install the MonsterFlow shell theme. Existing ~/.tmux.conf and ~/.config/cmux/cmux.json will be backed up to .bak files before symlinking."` Adds 1 line to `print_upgrade_message`; gives the adopter informed consent at the migration gate, not just the theme prompt.

### SF2 — Test harness: bash 3.2 (macOS default) vs bash 5.x for `export -f`
**Location:** D11 + Security T12 mitigation pin "`export -f has_cmd` to inherit into install.sh's bash child."

`export -f` works on bash 3.2 (macOS default `/bin/bash`) AND bash 5.x (homebrew `/opt/homebrew/bin/bash`). However, the *child* bash matters: `bash "$REPO_DIR/install.sh"` invokes whichever `bash` is first in PATH. On a fresh adopter machine running tests, that's `/bin/bash` (3.2); on Justin's dogfood machine it's `/opt/homebrew/bin/bash` (5.x). Two tested-in-practice gotchas with `export -f` between versions:

1. **`set -u` interaction:** in bash 3.2, an exported function reading an unset variable under `set -u` errors differently than in 5.x. install.sh uses `set -euo pipefail`; the mocked `has_cmd() { return 1; }` is trivial so this is unlikely to bite, but the *real* `has_cmd` (with PATH-augmenting logic) might behave subtly differently if a test ever shadows a more complex helper.
2. **`BASH_FUNC_<name>%%` env-var encoding** changed between 4.x and 5.x. Functions exported in 3.2 are encoded as `BASH_FUNC_has_cmd()` in env; 5.x uses `BASH_FUNC_has_cmd%%`. Both work *within the same major version*, but if the test harness runs in 3.2 and the install.sh subshell happens to find a different bash on PATH (e.g., adopter has homebrew bash earlier), the exported function may not survive the encoding boundary.

**Fix:** add to W4 task 4.1 (test harness skeleton): explicitly invoke install.sh with `/bin/bash "$REPO_DIR/install.sh"` (pin the bash interpreter) so the function-shadow inheritance is consistent across machines. Also document at the top of `tests/test-install.sh`: `# Tests assume /bin/bash (macOS default 3.2). Do not change without re-validating export -f inheritance.` This costs 1 path change + 1 comment; saves a future "tests pass on Justin's machine, fail in CI" debugging session.

### SF3 — `cmux` cask removal from homebrew-cask
**Location:** R-register has no row for "cask vendor disappears."

`cask "cmux"` in Brewfile is a hard dependency on the homebrew-cask repo continuing to ship cmux. If cmux's author yanks the cask in 6 months (cask-author dispute, app discontinued, transferred ownership) — `brew bundle install` returns non-zero, D8's catch fires, install.sh exits 1, and *every* fresh-Mac adopter hits a hard-stop until someone removes cmux from Brewfile.

This is structurally the same risk as any third-party dep. The plan's brew-bundle catch (D8) handles the *immediate* failure mode (clean exit, message, re-run instruction). But the *recovery* path is undefined: adopter has no way to "skip just cmux" without editing Brewfile.

**Fix:** add **R12 — Third-party cask/formula availability** with mitigation: D8's catch message should distinguish RECOMMENDED-tier failures (continue with loud notice) from REQUIRED-tier failures (hard-stop). Since cmux is RECOMMENDED, a cmux cask vanish should NOT block install. Implementation: parse `brew bundle install` output for which entries failed; if all failures are RECOMMENDED-tier, emit loud-notice and continue (exit 0); only hard-stop if a REQUIRED-tier (`git`, `python@3.11`) failed. ~15 lines in install.sh. Without this, RECOMMENDED-tier brittleness becomes a hard-stop, contradicting the spec's tier-split decline contract.

### SF4 — macOS minimum-version pin
**Location:** No row; spec L391-393 has Linux guard but not macOS-version guard.

cmux requires macOS ≥14 per `brew info cmux` output. An adopter on macOS 13 (still supported by Apple as of 2026; many enterprise machines) clones MonsterFlow, runs `./install.sh`, hits brew confirm, says Y, brew tries to install cmux cask, cask install fails with cryptic version error. D8's catch fires but the error message ("brew bundle failed for some formulas") doesn't name the actual problem (macOS too old for cmux).

**Fix:** add **R13 — macOS version range** with mitigation. Two options:
1. **Pre-flight check:** at top of install.sh after Linux guard: `[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ] || { echo "MonsterFlow requires macOS 14 (Sonoma) or later for cmux cask. Detected: $(sw_vers -productVersion). Either upgrade macOS or remove cmux from Brewfile manually." >&2; exit 1; }` — clean signpost.
2. **Brewfile gate:** wrap `cask "cmux"` in a Ruby conditional in Brewfile (`cask "cmux" if ENV['MACOS_MAJOR'].to_i >= 14`) and have install.sh export `MACOS_MAJOR` before invoking brew bundle.

Recommend option 1 (pre-flight) — it gives the adopter the actual error message instead of a brew-bundle stack trace. Add it to W2 task 2.1 alongside the Linux guard (same stage, same `uname`-class check). Also future-proofs: any future RECOMMENDED tool with a macOS-version requirement gets noted in the same check.

### SF5 — `--non-interactive` + `read -rp` behavior under cmux/CC tabs (no TTY)
**Location:** R-register no row for the *interaction* between `[ -t 0 ]` auto-detect and the test harness pipeline.

When `tests/test-install.sh` invokes install.sh via `bash install.sh </dev/null`, `[ -t 0 ]` returns false → install.sh sets `NON_INTERACTIVE=1` → all `read -rp` calls are bypassed. Good. But the *test cases that explicitly pipe answers* (like 3a piping `Y\n`) rely on stdin being a pipe AND `read -rp` actually executing. If the test sets `NON_INTERACTIVE=1` because stdin-is-a-pipe-not-a-TTY, the answer never gets consumed and `read` is skipped — the test passes for the wrong reason (no prompt fires because non-interactive, not because Y was answered).

**Fix:** in W4 task 4.1, the test harness must distinguish "no stdin" (true non-interactive) from "piped stdin" (semi-interactive — prompts should fire and consume the pipe). Easiest contract: test cases that pipe answers must `unset MONSTERFLOW_NON_INTERACTIVE` AND override the `[ -t 0 ]` auto-detect by exporting `MONSTERFLOW_FORCE_INTERACTIVE=1` (new env var, mirrors `MONSTERFLOW_FORCE_ONBOARD`). Alternatively, never auto-detect non-interactive — require the explicit `--non-interactive` flag. Auto-detect is convenient but creates this kind of test ambiguity.

Recommend: **add `MONSTERFLOW_FORCE_INTERACTIVE=1` env var** to D3's contract; tests piping answers set it. ~3 lines in install.sh; explicit and testable.

## Observations

### O1 — Sudo / `/Applications` write for cmux cask
The Risk prompt called out that `cask "cmux"` puts an `.app` in `/Applications` which "DOES need privileges." Verified: homebrew casks default to `/Applications` for `.app` artifacts; brew handles this via the calling user's `sudo` if needed, prompting for password mid-install. **Plan implication:** the brew-bundle confirm prompt is *not* the last consent gate — sudo password prompt fires *during* brew bundle execution. Worth one line in plan or UX docs: "brew bundle may prompt for your macOS password to install cmux to /Applications. This is normal." Otherwise an adopter sees a surprise password prompt and may abort thinking it's a phishing attempt.

Not worth a new R-row; just a UX note. Add to spec.md UX section or the brew-confirm prompt copy itself: `"Proceed? [Y/n]: (brew may prompt for your macOS password to install /Applications targets)"`.

### O2 — Test runtime variance budget (13s CI vs <30s local target, 60s CI cap)
Plan W4 ship criterion: "runtime < 30s local, < 60s CI target." Scalability said 13s CI estimate. So the variance budget is **30s − 13s = 17s headroom local, 60s − 13s = 47s headroom CI**. That's healthy. **But** `bash tests/run-tests.sh` runs the *full* test suite (`tests/run-tests.sh` already invokes other tests; install-rewrite tests are added "last position, slowest" per task 4.6). The 60s budget is for `test-install.sh` alone, not the full suite. If `test-install.sh` itself goes from 13s → 30s under CI flake (concurrent brew, slow `mktemp`, file-system sync), the *full* `run-tests.sh` budget gets stressed in ways the plan doesn't model.

**Fix or Observation:** if `tests/run-tests.sh` has a wall-clock budget anywhere, plan should pin install-test's contribution. If not (current state), this is just an observation — add a `time` wrapper in CI logs so future drift is visible. No code change needed at /check time.

### O3 — `--no-install` interacts with R7 (migration banner) in an unaudited way
`--no-install` bypasses ALL enforcement (spec contract). `--non-interactive` auto-proceeds the migration banner per plan Open Question 2. Combined: `./install.sh --no-install --non-interactive` on a v0.4.x system → migration banner prints to stderr → no enforcement → symlinks proceed regardless of whether tools needed by v0.5.0 features (e.g., `gh` for `/autorun` PR ops if onboard mentions it) are present. Ends in a state where the upgrade *succeeded* per exit code but the user is missing tools they don't know they need. Acceptable for CI escape but worth documenting.

Not a Must-Fix; just a documentation note in CHANGELOG.md v0.5.0 entry: "`--no-install --non-interactive` upgrades silently; re-run without flags for tier-aware install."

### O4 — Risk register convergence with Security threats (mapping table)
For audit clarity, here's the Threat→Risk traceability:

| Threat | Risk-row | Status |
|--------|----------|--------|
| T1 supply-chain | (none) | **MF2 — add R11** |
| T2 brew transitive | (none) | **MF3 — add preview to 2.6, optionally R12** |
| T3 malicious env vars | (partial via D4 + Security recommendation) | covered by hardened detect_owner; logging-the-override recommendation from Security L150 not visibly adopted in plan — would be SF6 if I had room |
| T4 TOCTOU in link_file | (none) | low-impact (single-user macOS), Security itself rated as "narrow"; accept |
| T5 symlink target swap (repo-location trust) | (none) | Security recommended `/tmp` warning L155-167; plan doesn't adopt. Probably SF-tier but Justin's clones go to `~/Projects`; observation only |
| T6 SIGINT trap glob | R6 | covered (D7) |
| T7 version downgrade | R7 | covered (D10) |
| T8 read -rp | (implicit) | new code uses `-r`; pinned in security.md L43-46 |
| T9 .zshrc PEM-class | R5 + D6 | covered |
| T10 gh auth log leak | R3 (partially) | R3 is about hang/timeout, not log leak; Security recommendation L207-209 (`[ -t 1 ]` gate) not visibly added to D9. Plan should explicitly require `[ -t 1 ] && [ -t 0 ]` in onboard.sh task 3.2 |
| T11 eval/heredoc | (implicit + CI gate Security L213) | covered if MF2's grep gate is adopted |
| T12 test-harness leakage | R2 | covered (D11 + Security L97-107 pattern) |

**Net:** 8 of 12 cleanly mitigated, 2 partially (T3, T10), 2 unmitigated (T1, T2). MF2 + MF3 + adding `[ -t 1 ]` to D9 closes the gaps to 11/12 (T4 acceptable per Security's own rating).

### O5 — Where I'd bet against this plan
Per the persona's "If you had to bet against this plan, where would you place the bet?" question:

- **First bet (60% confidence):** the test harness will pass on Justin's machine and silently fail or false-pass on a fresh adopter machine due to bash version + `export -f` + `[ -t 0 ]` interaction (SF2 + SF5). This is the kind of bug that hides until an adopter actually tries. Mitigation: SF2 + SF5 above.
- **Second bet (30% confidence):** the `autorun-shell-reviewer` subagent gate (W2 ship criterion) returns 2-3 High findings on the cumulative diff — install.sh grew by 180 lines touching set-euo pipefail, traps, prompts, env vars; that's exactly the surface area the subagent's 13-pitfall checklist targets. Mitigation: MF1 (define the threshold; expect to split W2 if needed).
- **Third bet (15% confidence):** cmux cask issue (vendor change, macOS-13 adopter, missing /Applications privilege flow). Mitigation: SF3 + SF4 + O1.

If all 6 Must-Fix and Should-Fix items are addressed, I'd revise the bets to: 30% / 15% / 5%.

---

**Recommended next action:** address MF1, MF2, MF3 in plan.md before /build (each is 1-3 lines of plan text + 1 task added to a wave). SF1-SF5 can be addressed at /build time with explicit acknowledgment in commit messages. Observations are notes for the synthesizer — no code change required.
