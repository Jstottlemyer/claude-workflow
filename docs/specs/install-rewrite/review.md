# `install-rewrite` Spec Review

**Reviewed:** 2026-05-04
**Spec:** `docs/specs/install-rewrite/spec.md` (sha256 `1f36e2e9…`)
**Reviewers:** 6 PRD personas (requirements, gaps, ambiguity, feasibility, scope, stakeholders) + Codex adversarial
**Findings:** 20 (10 blocker · 8 important · 2 minor)

## Overall Health: **Significant Gaps**

5 of 6 reviewers returned PASS WITH NOTES; **scope returned FAIL**. The spec is well-structured and the additive-surgery pivot is sound — but it has accumulated meaningful scope creep beyond what BACKLOG.md asked for, three internal contradictions, two implementation-correctness bugs that would surface during /build, and a structural feasibility gap (wiki-export is a Claude Code skill, not a shell command — `scripts/onboard.sh` cannot invoke it from bash).

The good news: most blockers are localized. A scope cut + targeted clarifications get this to PASS. No reviewer recommended a full rewrite; the additive-surgery approach is the right risk posture.

## Before You Build (10 blocker items)

1. **`wiki-export` skill cannot be invoked from `scripts/onboard.sh`.** Skills run inside the Claude Code agent loop; bash cannot call them. Three options: (a) drop wiki indexing from onboard; (b) factor wiki logic into a callable `scripts/wiki-export.sh` that the skill also wraps; (c) write a sentinel file the next Claude Code session picks up. **(a) is the MVP cut** — the wiki indexing serves only the owner anyway (gates on `~/.obsidian-wiki/config`).

2. **Theme symlinks may clobber existing user files (`~/.tmux.conf`, `~/.config/cmux/cmux.json`) without backup.** The current `link_file()` (install.sh:91-100) already implements `mv $dst → ${dst}.bak` for non-symlinked existing files — the new theme stage must reuse that pattern, not raw `ln -sf`. With owner-default-YES, owner debug runs could mutate Justin's customized configs.

3. **`--no-install` + REQUIRED-missing: direct contradiction.** Scope says symlinks still run. Edge Cases agrees. Acceptance case 5 says "exit 1 if REQUIRED missing." If REQUIRED enforcement still fires under `--no-install`, the flag is useless for CI/restricted envs (its declared purpose). **Pick:** `--no-install` bypasses ALL enforcement (CI escape hatch) OR only skips brew execution. Recommend the former.

4. **Acceptance case 1 "byte-identical (modulo timestamps)" is undefined and too strict.** No normalization regex. Brew/doctor/plugin output varies. Replace with: assert stable disk state (no duplicate symlinks via `find … | sort | uniq -d`), assert key messages present (`grep`), assert exit code 0.

5. **Acceptance case 3 "Fresh-Mac happy path" tests the REQUIRED hard-stop, not the happy path.** Add a separate case: pre-stage brew + claude present, RECOMMENDED missing, simulate Y to install prompt, assert `brew bundle install` invoked, symlinks created, panel printed, exit 0. Without this, no test proves end-to-end success.

6. **Test harness PATH manipulation will false-pass.** `has_cmd()` (install.sh:21-25) hardcodes `/opt/homebrew/bin/$1` and `/usr/local/bin/$1` checks — tools "missing" via PATH will still be found on the dev machine. Need an explicit override: refactor `has_cmd` to honor `MONSTERFLOW_PATH_OVERRIDE`, or shadow the function in tests via `export -f`.

7. **Scope creep: theme baseline + cmux + wiki indexing exceed BACKLOG.md.** BACKLOG.md:46-68 names detect/install/verify/onboard, brew bundle, `--no-install`, doctor.sh call, panel, optional graphify bootstrap, optional gh auth login, codex one-liner. It does NOT name cmux, theme baseline, `--install-theme`/`--no-theme`, `.zshrc` sentinel, wiki indexing. **MVP cut:** drop stage 7 (theme) + wiki half of stage 12. Spec halves; test count 7→5 aligns with BACKLOG.md's 4 idempotency cases + `--no-install`.

8. **v0.4.x → v0.5.0 migration path missing.** Existing adopter on v0.4.2 re-runs at v0.5.0 and gets surprise brew install list, surprise theme prompt (if not cut per #7), no "what changed" messaging. No acceptance case covers it.

9. **No non-interactive mode beyond `--no-install`.** `gh auth login` (TUI), `brew bundle` confirm, theme prompt all hang in CI/non-TTY. Need `--non-interactive` / `--ci` flag (or auto-detect via `[ -t 0 ]`) that disables every prompt and selects safe defaults.

10. **`set -euo pipefail` will exit install.sh on `brew bundle` non-zero before the spec's "catch path" runs.** Implementation must use `if ! brew bundle …; then handle_failure; fi`, not implicit error handling. Spec should specify the guarding pattern explicitly.

## Important But Non-Blocking (8 items)

11. **"Loud notice" format unspecified.** Pin: glyph (`⚠`), stream (stderr), single emit vs repeat-at-exit, exit-code semantics.
12. **Owner detection via `PWD == REPO_DIR` is fragile** under symlinked paths, `../MonsterFlow/install.sh`, git worktrees, agent-driven runs. Add `MONSTERFLOW_OWNER=1` env override or compare `realpath` of install.sh's dirname against `git rev-parse --show-toplevel`. Theme stage amplifies cost of mis-detection.
13. **Theme prompt — Scope says owner-default-YES (implies prompt-default-Y), Acceptance case 6(a) says "without prompt".** Pick. Recommend: no-prompt for owner (frictionless dogfood); prompt-default-N for adopter.
14. **Linux user gets cryptic `command not found: brew`** instead of clean "macOS-only" signpost. Add one-line `[ "$(uname)" = Darwin ]` guard at the top.
15. **No SIGINT trap.** Ctrl-C mid-install leaves partial state (`.zshrc.tmp`, half-symlinked dirs). Add `trap cleanup_partial INT TERM`.
16. **"Additive surgery" framing understates control-flow changes** around stages 5-11. Plan should explicitly diagram new vs old flow to avoid sequencing bugs around early exits / pipeline-aware prompts.
17. **Onboard panel content has no acceptance assertions** — Stage 12 "done" is undefined. Add: assert panel contains `/flow`, `/spec`, `dashboard/index.html`.
18. **Flag precedence undefined** for `--install-theme` + `--no-theme`; missing `--no-onboard` for fully-scripted runs.

## Observations (2 minor)

19. **`pip3` migration scope contradicts itself** — Scope says "sister scripts get migrated incrementally", Open Q2 says "NOT migrated in this spec." Pick. Recommend: explicitly out-of-scope, not even incremental.
20. **cmux terminology imprecise** — "homebrew-cask formula" is wrong (cask, not formula); `cask "cmux"` is the Brewfile syntax. "Auto-updates" is a cask-author attribute, not under our control.

## Reviewer Verdicts

| Dimension | Verdict | Key Finding |
|---|---|---|
| Requirements | PASS WITH NOTES | Acceptance case 3 doesn't test happy path; "loud notice" / "byte-identical" undefined |
| Gaps | PASS WITH NOTES | Migration path missing; theme symlink data-loss risk; no SIGINT trap |
| Ambiguity | PASS WITH NOTES | 5 internal contradictions across Scope/Edge/Acceptance |
| Feasibility | PASS WITH NOTES | wiki-export is a skill (headline); `has_cmd` PATH-mock broken; `set -euo pipefail` kills before catch |
| Scope | **FAIL** | Theme + cmux + wiki indexing exceed BACKLOG.md — MVP cut available |
| Stakeholders | PASS WITH NOTES | Linux fail mode; v0.4.x migration; `gh auth login` non-TTY hang |
| Codex Adversarial | (not voted) | 12 findings; converges with reviewers on wiki-skill, file-overwrite, owner-detect, `--no-install`; adds: tmux/cmux incoherence, brew-as-REQUIRED contradiction with "fresh-Mac automation" framing |

## Conflicts Resolved (Judge dedup)

- **Wiki-skill** flagged by Feasibility (headline), Scope (owner-only dead code), Codex ("implementation fantasy") → merged into one blocker. Resolution: drop wiki from onboard for v1.
- **Theme overwrite** flagged by Gaps (data-loss) and Codex (conflict detection) → merged. Resolution: reuse `link_file()`'s backup pattern.
- **`--no-install` contradiction** flagged by Requirements, Ambiguity, Codex (3 votes) → merged. Resolution required at spec-revision time.
- **`has_cmd` PATH-mock** flagged by Feasibility (definitive) and Codex (corroborates) → merged. Resolution: refactor or use function-shadowing in tests.
- **Owner-detect fragility** flagged by Feasibility, Codex, Stakeholders (3 votes) → merged. Resolution: add `MONSTERFLOW_OWNER` env override.
- **Non-interactive mode** flagged by Stakeholders, Codex, Gaps (3 votes) → merged into one item.
- **Migration path** flagged by Gaps and Stakeholders → merged.
- **Byte-identical idempotency** flagged by Requirements, Ambiguity, Codex → merged.

## Agent Disagreements Resolved

None — Codex's "additive surgery understates changes" is a tone/framing nuance, not a contradiction with reviewer findings. All other findings stack consistently.

---

**Recommended next action:** revise the spec to (a) MVP-cut theme + cmux + wiki indexing per scope, (b) resolve the 3 contradictions per ambiguity, (c) add the missing happy-path test and fix the test-harness mock strategy per requirements/feasibility, (d) add migration story + non-interactive mode + Linux guard. Then re-run `/spec-review` for delta confirmation, or proceed to `/plan` if you accept the open items as plan-time work.

Approve to proceed to `/plan`? (approve / refine `<what to change>`)
