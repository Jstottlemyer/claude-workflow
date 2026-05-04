# Ambiguity Review — install-rewrite

## Critical Gaps (must answer before building)

- **"Loud notice" format is undefined (Scope line ~38, Edge Cases table line ~298).** Scope says "RECOMMENDED-missing continues with loud notice." The Edge Cases table gives a sample string, but doesn't pin down: is it a single line, a boxed panel, prefixed with `⚠`, repeated at end of run, written to stderr or stdout? Two engineers will produce visibly different output. Define exact format (prefix glyph, color/no-color, stream, repeat-at-end behavior).

- **"Neutral opinionated defaults" — threshold undefined (Scope line 40, Data line ~213).** Scope calls `config/` files "neutral opinionated defaults"; Data section says "neutral opinionated cmux config (vertical tabs, dark theme)" and "high-contrast cyan/grey theme (matches Justin's CLAUDE.md notes)." If they match Justin's personal config, they are not neutral; if they're neutral, they don't match Justin's notes. Open Question #3 admits "doesn't pin exact contents" and defers to /plan — but neutrality is a *requirement* (security/auditability claim on line 213), not a content detail. What is the neutrality test? (No absolute paths? No machine-specific bindings? No personal aliases?)

- **"Owner-default-YES" semantics on theme prompt vs symlink (Scope line 41, UX line 134, State table line ~252).** Scope: "default behavior is owner-default-YES (when `PWD == REPO_DIR`), adopter-default-NO." UX happy-path shows adopter prompted with `[y/N]: y`. State table says owner = "symlinked" (no prompt) and adopter = "prompt-y/N." But Acceptance case 6(a) says "Run from `$REPO_DIR` with no `--no-theme` flag → theme symlinks created without prompt." Is owner *never* prompted, or prompted with default-Y? The two phrasings produce different test assertions. Pick one and propagate.

- **`--no-install` exit code under REQUIRED-missing is contradictory (Edge Cases line ~299, Acceptance case 5 line ~343).** Edge Cases says `--no-install` prints "Skipped install per --no-install. Some features may be degraded." (implying continue). Acceptance case 5 says: "exit code 0 (or 1 if REQUIRED missing, with hard-stop messaging)." So does `--no-install` skip the REQUIRED hard-stop or honor it? If REQUIRED is missing in CI, does `--no-install` mean "I know, stop nagging" (exit 0) or "still hard-stop, I just don't want auto-install" (exit 1)? Two engineers will implement opposite branches.

- **"Idempotency under repeat runs" — byte-identical claim is over-strong (Acceptance case 1 line ~339).** Test says "Diff stdout — must be byte-identical (modulo timestamps)." But the spec doesn't enumerate what counts as a timestamp vs other run-variant noise (e.g., `brew bundle check` output line counts, `gh auth status` cache state, `mktemp` temp dir paths in symlink readlinks if `$HOME` itself moved between runs). Define the canonical diff filter (sed expression) or the assertion will fail flakily.

## Important Considerations

- **"Single confirm" vs the prompt shown (UX line 124).** Scope line 39/54 says "bulk single-confirm." UX shows `Proceed? [Y/n]: <enter>`. With `<enter>` accepting default-Y, that's one confirm. But what if user types `n`? Spec doesn't show the decline branch UX — does it then drop into the RECOMMENDED loud-notice path, or hard-stop, or print a different prompt? Need decline-branch flow.

- **"Not-run-recently sentinel" — recency window undefined (Edge Cases line ~316).** "Indexing offers gate on 'not-run-recently' sentinel files (`~/.local/share/MonsterFlow/.last-graphify-run`)." What's the window — 24h? 7d? Forever-once-set? Acceptance case 7 doesn't test this gate at all (it tests presence of `~/.obsidian-wiki/config`, not last-run recency). Either define the window or drop the recency claim and gate purely on detection.

- **Onboarding panel: optional kickoff prompts in UX vs onboard.sh outline disagree (UX lines 152-156 vs Data lines 234-237).** UX panel lists "Index ~/Projects/ for the dashboard?", "Authenticate gh CLI now?", "Want adversarial review? Run /codex:setup". The onboard.sh outline gates these on detection (`[ -d "$HOME/Projects" ]`, `has_cmd gh && ! gh auth status`, `has_cmd codex || ...`). But the UX panel appears to print all three unconditionally inside the box. Does the box always print all three lines, or only the ones whose detection passes? (Wiki indexing isn't shown in the UX panel at all but is in the outline — another mismatch.)

- **`--no-theme` interaction with already-installed theme (Edge Cases line ~321).** "Spec deliberately does NOT remove the existing theme. `--no-theme` only governs default-no-prompt for the current run." But re-run with `--no-theme` after theme is installed: is the `.zshrc` sentinel block left in place? Are the `~/.tmux.conf` / `~/.config/cmux/cmux.json` symlinks preserved? "Doesn't remove" needs explicit enumeration of which artifacts survive.

- **"Adopter prompted theme [y/N]" vs onboard panel "Index ~/Projects? [y/N]" — same flow, different stages (UX line 133 vs lines 152-153).** Spec mixes install-time prompts (theme) and onboard-time prompts (indexing) without a clear stage boundary. Is the theme decision asked before symlinks (line 133 implies yes — it appears mid-install output) or in onboard.sh? If `scripts/onboard.sh` is independently re-runnable (line 217), the theme prompt cannot live there because re-running onboard would re-prompt for theme on every run.

- **`pip3` migration scope contradiction (Scope line 37 vs Open Question #2 line 355).** Scope says: "`python_pip()` helper wired into install.sh **and any sister scripts that currently hardcode `pip3`**." Open Question #2 says: "Other scripts that currently hardcode `pip3` are NOT migrated in this spec." Direct contradiction. Pick one and remove the other.

- **Brew tier promotion vs verification (Scope line 38 vs Acceptance line ~341).** Brew is REQUIRED. Acceptance case 3 mocks `has_cmd` to report all tools missing and asserts hard-stop on REQUIRED-missing. But the test mocks `has_cmd` via PATH manipulation — does that affect `has_cmd brew` correctly given install.sh's PATH-augmenting helper (which adds `/opt/homebrew/bin`)? Spec doesn't say whether the test overrides that augmentation. Implementation will diverge.

- **"Modulo timestamps" filter in test (Acceptance case 1).** Define which fields are "timestamps" — version banner has `v0.4.3` (stable across one run pair), but if banner ever embeds `date`, the diff breaks. Either spec the regex or commit "no timestamps in banner."

## Observations

- **"~80 lines" for onboard.sh (Integration line ~267).** Soft budget, not a constraint. Fine — but flag-counted as ambiguous if a reviewer asks "why is it 140?".

- **"v0.4.3" in UX banner (lines 96, 113, 164).** Spec is for the rewrite that bumps to 0.5.0 (Open Question #4). The UX examples show `v0.4.3`. /plan should reconcile — examples should show the post-bump version or be marked as illustrative.

- **"Existing 354 lines" repeated (Summary, Approach, Out of scope).** Implies a hard line-count assertion. If the additive surgery itself adds, say, 80 lines, install.sh becomes ~434 lines — does that violate "if install.sh later grows past ~500 lines, extraction is a follow-up"? No, but the 500-line threshold is itself a weasel number ("~500"). Pin or drop.

- **"Loud notice" wording "silently no-op" (Edge Cases line ~298).** The notice promises features will "silently no-op" — but `gh` missing causes `/autorun` PR ops to *fail* visibly, not silently no-op. Either the user-facing copy is wrong, or the underlying claim about feature behavior is wrong. /plan should reconcile against actual /autorun error behavior.

- **Box-drawing fallback (Edge Cases line ~333).** "If this becomes a real adopter complaint, fall back to plain ASCII." Defers a decision rather than making one. Fine for v0.5.0; flag for /check.

- **Test harness `$HOME=<tmp>` with subshell sourcing (Acceptance preamble line ~337).** "Sourced into a subshell with `HOME=<tmp>`." But install.sh is invoked, not sourced (the one-liner is `./install.sh`). Subshell-source is a different execution model than subshell-exec. /plan should clarify the test invocation pattern (probably `env HOME=$tmp bash install.sh`).

- **Theme `~/.zshrc` append idempotency vs `--no-theme` (State line ~253, Edge Cases line ~320).** State table says sentinel block is appended for theme; Edge Cases says `--no-theme` doesn't remove. So `--no-theme` after theme install leaves the sentinel block — but a reader might expect `--no-theme` to mean "the theme is not active." Sentinel-bracketed blocks *can* be cleanly removed (per the persona-metrics precedent); spec chose not to. Worth surfacing the rationale.

## Verdict

PASS WITH NOTES — the spec is coherent at the architectural level, but five ambiguities (loud-notice format, neutrality test for `config/`, owner-prompt-or-not, `--no-install` + REQUIRED interaction, pip3 migration scope contradiction) will produce divergent implementations and flaky tests if not resolved before /plan.
