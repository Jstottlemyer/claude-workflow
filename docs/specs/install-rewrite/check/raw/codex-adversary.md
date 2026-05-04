- **Plan already drifts from actual `install.sh`:** current script is 354 lines, but `brew bundle` does not exist anywhere. D8/2.6 assumes an install stage to wrap; implementation must add a new Homebrew path from scratch, not “catch” existing behavior.

- **Flag parsing before Linux guard conflicts with current top-level side effects.** `REPO_DIR`, `VERSION`, and installer banner print before any planned flag parse unless reordered. `--help` will still touch repo files and print the installer banner unless the top is restructured more than the plan admits.

- **`has_cmd` mocking via `export -f has_cmd` will not override the function defined inside `install.sh`.** Bash child inheritance loses to the script’s own later function definition. The test strategy needs PATH stubs or an explicit hook in `install.sh`.

- **Owner detection replacement changes semantics.** Current owner means `PWD == REPO_DIR`; proposed owner means `script_dir == git_root`. Running `/path/to/MonsterFlow/install.sh` from another project would become owner if the script lives at repo root, breaking adopter behavior and `ADOPTER_ROOT` creation.

- **`ADOPTER_ROOT` detection remains too narrow.** Current code only accepts `-d "$PWD/.git"`, so worktrees/subdirs fail. Proposed owner detection does not fix adopter root via `git rev-parse --show-toplevel` from `PWD`.

- **`printf %q` in `.zshrc` is bash-specific output.** `.zshrc` is sourced by zsh; bash `%q` escaping is not guaranteed to round-trip as zsh syntax. Use single-quote escaping or write via a zsh-compatible literal.

- **SIGINT scratch cleanup does not cover real partial state.** Most existing mutations are direct `ln -sf`, `mv`, `mkdir`, append-to-gitignore, and `cp`; moving temp file writes into scratch only protects new atomic writes, not current partial symlink/config/user-file changes.

- **`link_file()` backup behavior is risky for theme/config files.** Existing `mv "$dst" "$dst.bak"` overwrites prior backups and is not atomic. Plan relies on it for `.zshrc`/theme safety without upgrading it.

- **`--non-interactive` auto-detect via `[ -t 0 ]` is not enough.** Current `read -rp` prompts will fail under `set -e` when stdin is closed unless every prompt is gated before execution. Missing one becomes a hard CI failure.

- **Wave 3 is less parallel than claimed.** `scripts/onboard.sh` depends on real install destinations, `has_cmd`/PATH conventions, doctor behavior, and possibly `gh`; it will churn if W2 reshapes env/stages.

- **Runtime targets look optimistic.** Adding `brew bundle`, `gh auth status` timeout, test-suite invocation, and 12 install cases makes `<3s` repeat-run and `<30s` full tests unlikely unless brew/gh/tests are aggressively skipped or mocked.

- **Subagent gate references `autorun-shell-reviewer` policy but no callable mechanism is in this plan.** It is process theater unless the build system actually supports that reviewer invocation.