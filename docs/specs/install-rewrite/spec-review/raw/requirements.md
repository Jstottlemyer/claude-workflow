# Requirements Review — install-rewrite

## Critical Gaps (must answer before building)

- **Acceptance case 3 ("Fresh-Mac happy path") doesn't actually test the happy path it names.** The case (Acceptance Criteria #3) stages all tools missing and asserts the REQUIRED hard-stop fires with exit 1. That's a *hard-stop* test, not a *happy path* test. The Summary promises "a fresh-Mac adopter ends with a demonstrably-working pipeline" but no acceptance case proves end-to-end success after brew installs missing tools. Add a case where REQUIRED is present, RECOMMENDED is missing, user accepts the install prompt, and the run completes with all expected symlinks + onboard panel printed.
- **No measurable success bar for the onboard panel.** UX/User Flow shows the boxed panel verbatim but Acceptance Criteria never asserts what the panel must contain. Case 7 only checks indexing-prompt presence. There is no test that "Next steps" enumeration appears, that the doctor.sh invocation succeeded, or that the panel renders at all on a successful install. "Done" for stage 12 is undefined.
- **"Total runtime: under 2 seconds" target (Edge Cases / Acceptance #2) has no measurement methodology.** No specification of: which machine class (M1 vs Intel), cold vs warm filesystem cache, whether `brew bundle check` network calls count toward the budget, or what to do if it fails on slower hardware. As written, this is an unenforceable target — anyone can claim it and anyone can refute it.
- **Idempotency case (#1) says "byte-identical modulo timestamps" but doesn't define the timestamp-stripping rule.** What regex? Does it cover brew's own progress output, version strings (`v0.4.3` will appear in stdout), or only ISO-8601 patterns? Without an explicit normalization, this test will be flaky or false-positive.
- **`scripts/onboard.sh` exit semantics undefined.** Spec says it's "non-blocking" and "independently re-runnable" but never states: does a failed `doctor.sh` cause onboard.sh to exit non-zero? Does install.sh treat onboard.sh failure as install failure or warning? If onboard.sh exit is ignored, the "demonstrably-working pipeline" promise has no enforcement point.
- **"Loud notice" for RECOMMENDED-decline (Edge Cases table) is not specified.** What exactly does "loud" mean — color codes, lines of output, blocking pause, repeated at end-of-run? Two implementers will produce two different things. Pin the literal text.
- **Network failure mid-`brew bundle` says "Symlinking is also skipped to avoid a half-installed state" (Edge Cases) — this contradicts the `--no-install` behavior (UX flow) where symlinks DO run without brew.** Pick one rule: either symlinks are independent of brew state, or they're not. The current spec is internally inconsistent.

## Important Considerations (should address but not blocking)

- **No security posture statement on the `.zshrc` mutation.** Sentinel-bracketing is mentioned but the spec doesn't require a backup of `.zshrc` before first append, nor specify behavior if the user has existing `# BEGIN MonsterFlow theme` markers from a manual edit. Memory entry `feedback_install_adopter_default_flip.md` exists for the gitignore case — apply the same rigor here.
- **No rollback / uninstall story.** Spec explicitly defers `uninstall-theme.sh` ("out of scope — added if/when an adopter actually asks for it"). For a tool that mutates `~/.tmux.conf`, `~/.config/cmux/cmux.json`, and `~/.zshrc`, "uninstall is deferred" is a real gap. At minimum, document the manual rollback steps in README.
- **Case 6c ("adopter run with `--install-theme`") doesn't specify whether the prompt is suppressed silently or printed-and-auto-confirmed.** Affects log readability and adopter trust.
- **No acceptance case for `--install-theme` + `--no-theme` simultaneously.** What's the precedence? Spec doesn't say. Mutually-exclusive flags should error out, last-wins, or first-wins — pick one.
- **"Documentation parity" acceptance bar is subjective.** "QUICKSTART.md updated to describe the new install/onboard split if any flow change affects users" — who decides if the flow change affects users? Make it concrete: the install one-liner in README must execute end-to-end without manual intervention on a fresh Mac.
- **Brew bundle stdout suppression unspecified.** brew bundle is verbose (per-formula download/build output). Should install.sh tee it to a log, suppress to a summary, or pass through? Affects the "byte-identical stdout" promise of Acceptance #1.
- **No acceptance test for the `python_pip()` helper sourcing.** Integration section says install.sh sources `scripts/lib/python-pip.sh` but no case verifies the helper is callable from install.sh after sourcing, or that sourcing fails loud if the file is missing.
- **Open Question #3 ("config/ file contents") is deferred to /plan but Acceptance Criteria #6 asserts symlinks exist — the test passes even if the files contain broken or empty content.** Add a smoke test: `tmux -f config/tmux.conf -c 'list-keys' >/dev/null` (or equivalent) to prove the config files are at least syntactically valid.

## Observations (non-blocking notes)

- Acceptance test design (temp `$HOME` via `mktemp -d`, subshell with `HOME=<tmp>`) is sound and matches the testability bar in the persona checklist.
- The 7-case enumeration is well-structured for a QA engineer to script from spec alone — good coverage of the flag matrix and the owner/adopter axis.
- Brew bundle's native idempotency (Edge Cases) is a correct call — leveraging it instead of reimplementing is the right move.
- Confidence breakdown in frontmatter (acceptance 0.92) feels slightly high given the gaps above; 0.80–0.85 would be more honest.
- The "additive surgery" framing is well-defended (preserved-verbatim list at lines 274–283 is concrete) and reduces requirements ambiguity for the unchanged stages.
- Tier-promotion of brew to REQUIRED with no special-case path is a clean design call worth preserving.

## Verdict
PASS WITH NOTES — the acceptance matrix is well-structured but has three concrete defects (no actual happy-path test, undefined panel content, contradictory symlink-on-network-failure rule) that should be patched before /plan; everything else is tightening rather than gating.
