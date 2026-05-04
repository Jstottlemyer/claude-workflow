- **“Additive surgery” conflicts with behavioral rewrite.** The spec says stages 5-11 stay unchanged, but adding install gating, post-install verification, theme mutation, onboard invocation, and testability hooks will necessarily alter control flow around existing validation/plugin prompts. Treating this as low-risk preservation may hide the riskiest part: sequencing failures and early exits.

- **`brew` as REQUIRED blocks the promised install flow.** If `brew` is missing, the flow cannot “detect → install → verify”; it becomes “detect → tell user to install brew manually.” That may be the right security tradeoff, but the spec overstates fresh-Mac automation and should explicitly frame Homebrew as a prerequisite.

- **`--no-install` semantics are contradictory.** Scope says symlinking still runs, edge cases say exit 0 or 1 if REQUIRED missing. If REQUIRED missing hard-stops, then `--no-install` is not useful for CI/restricted envs unless CI has every REQUIRED tool. Decide whether `--no-install` bypasses REQUIRED enforcement or only brew execution.

- **Demoting `tmux` while shipping `tmux.conf` is incoherent.** The spec says `tmux` is OPTIONAL, but the theme prompt may install `~/.tmux.conf`, and autorun may still depend on tmux. This creates a UX where users get config for an absent tool and discover breakage later.

- **`cmux` assumptions need verification.** Calling it a “homebrew-cask formula” is imprecise, and “auto-updates” may not match Homebrew cask behavior. If the cask name or availability changes, the entire recommended bundle path becomes brittle.

- **Testing via PATH manipulation will not cover `has_cmd` if it augments PATH internally.** The spec preserves a PATH-augmenting helper, so tests that simulate missing tools by pointing PATH to an empty dir may be invalid. The harness needs an explicit command lookup override or fixture bin directory model.

- **Byte-identical stdout idempotency is too strict and likely counterproductive.** Prompts, brew output, doctor output, plugin installer output, elapsed-time-dependent messages, and onboard gating can vary. Assert stable state and key messages instead.

- **Onboard side effects undermine install idempotency.** Running doctor, offering auth, and kicking off indexing from install’s final step mixes installation with operational actions. Even opt-in prompts can break automation unless `--non-interactive` or CI detection exists.

- **No non-interactive mode is specified.** Single-confirm UX is fine for humans, but tests, CI, scripted installs, and curl-piped installers need deterministic behavior. `yes | ./install.sh` is not a robust API.

- **Theme symlinks can overwrite real user files.** `ln -sf ~/.tmux.conf` and `~/.config/cmux/cmux.json` can replace existing user config without backup if theme default is owner-YES or adopter opts in casually. Need conflict detection, backup, or refusal unless already MonsterFlow-owned.

- **`PWD == REPO_DIR` owner detection is fragile.** Running `../MonsterFlow/install.sh`, using symlinked repo paths, or invoking from scripts can flip defaults unexpectedly. This matters more once owner detection controls theme mutation.

- **Wiki indexing via “skill” is underspecified for shell.** `scripts/onboard.sh` cannot invoke a Codex skill unless there is a concrete CLI/API contract. This is currently an implementation fantasy, not an executable shell design.