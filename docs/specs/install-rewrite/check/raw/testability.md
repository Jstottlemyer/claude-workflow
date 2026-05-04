# Testability Review — install-rewrite plan

## Verdict

**FAIL** — the cornerstone mock mechanism (`export -f has_cmd`) does not survive install.sh re-defining `has_cmd()` at line 21, so the entire 12-case acceptance suite as designed cannot exercise REQUIRED/RECOMMENDED detection. Two additional must-fix items (brew-stub strategy uniformity, BSD `script` argv form) are blocking. Multiple sub-cases (6d, 7a, 8) need fixture/mechanism specifics before /build can write tests against them.

This is recoverable with bounded edits to plan D11 and the W4 task list — not a re-spec — but it must be fixed before /build, because the test harness is the gate on the rest of the work.

## Must Fix Before Building

### MF1 — `export -f has_cmd` is shadowed by install.sh's own definition (D11, R2)

Validated on macOS bash 3.2.57 (the OS default and the harness target):

```bash
$ bash -c '
  has_cmd() { echo MOCK; return 1; }
  export -f has_cmd
  bash -c "has_cmd() { echo REAL; return 0; }; has_cmd foo"
'
REAL
```

`install.sh` line 21-25 defines `has_cmd()` as part of its own body. When tests `export -f has_cmd` and then exec install.sh, install.sh's local definition wins on parse. The mock is never called. Cases 3, 3a, 4, 5, 6a-d, and the recursion-guarded subset of 1, 2, 9 all silently exercise the real `command -v` against the test runner's `$PATH`, producing false greens (or false reds, depending on what's actually installed on the dev machine).

Three viable fixes; plan must pick one and pin it in D11 + W4 task 4.1:

1. **PATH-stub model (recommended).** Test prepends a `mktemp -d` directory to `$PATH` containing executable stubs for every command install.sh probes (`brew`, `gh`, `jq`, `shellcheck`, `git`, `python3`, `claude`, `tmux`, `codex`, `cmux`). Each stub is a 3-line bash script that records argv to a per-test log and exits 0/1 per the case's required state. This is what the brew-stub line in spec case 3a already implies — make it uniform. Validated working in this review against `brew bundle install`.
2. **Source-and-shadow model.** Test does `source install.sh` (not exec), with a wrapping function that re-defines `has_cmd` AFTER source but BEFORE the detect block runs. Requires install.sh to be split into "define" and "execute" halves with a `MONSTERFLOW_INSTALL_TEST=1` short-circuit between them. Larger surgery; couples test architecture to production code.
3. **Function-export with install.sh deletion of its own definition under TEST flag.** Add `if [ "${MONSTERFLOW_INSTALL_TEST:-0}" != "1" ]; then has_cmd() { ... }; fi` around lines 21-25. Brittle; future contributor adds a second has_cmd-touching block and forgets the guard.

PATH-stub is the only one that doesn't require install.sh to know it's being tested for the detection path. Pick it. Update D11 to read: "Mock strategy: per-test `$PATH` prefix containing executable stubs that record argv. Function-export not used (would be shadowed by install.sh's own has_cmd at line 21)."

### MF2 — `MONSTERFLOW_INSTALL_TEST` recursion guard is named in D3 + R2 but never specified in install.sh source

D3 lists the env var. R2 lists it as the mitigation. W2 task 2.9 wraps "existing prompts in `NON_INTERACTIVE` guard" — but `MONSTERFLOW_NON_INTERACTIVE` and `MONSTERFLOW_INSTALL_TEST` are different vars with different semantics:

- `MONSTERFLOW_NON_INTERACTIVE` = "no prompts, take safe defaults" (production CI use case).
- `MONSTERFLOW_INSTALL_TEST` = "skip plugin-install + test-suite-validate so the test harness doesn't recursively invoke itself" (test-only).

Plan needs an explicit Wave 2 task (call it 2.9b or fold into 2.9) that adds the `MONSTERFLOW_INSTALL_TEST` short-circuit at TWO specific install.sh sites:

- around line 305-316 (the `claude plugins install` prompt block)
- around line 318-326 (the `bash tests/run-tests.sh` validate block — without this guard, running `tests/test-install.sh` from inside `run-tests.sh` causes infinite recursion)

Without the second site, case 1's "run install.sh twice" assertion will fork-bomb the CI runner. The plan currently glosses over this — D11 says "install.sh skips … and `bash tests/run-tests.sh` prompts under that flag" but the W2 task list doesn't reference line 318-326.

### MF3 — Brew-stub strategy is not uniform across cases (case 3a vs case 4 vs case 1)

Case 3a says "mock the brew binary to a stub that records its argv." Case 4 ("re-install after `brew uninstall jq`") needs the brew stub to TOGGLE state between probes (`brew bundle check` returns 1 → install runs → `brew bundle check` returns 0). Case 1 ("idempotency, run twice") needs the brew stub to PERSIST state between two install.sh invocations. Case 6d (theme backup) needs no brew interaction at all.

Plan needs a single canonical stub spec in D11 or a new D-section. Recommended sketch:

```bash
# tests/fixtures/install-stubs/brew  (chmod +x)
#!/bin/bash
STUB_LOG="${MONSTERFLOW_STUB_LOG:?STUB_LOG unset}"
STUB_STATE="${MONSTERFLOW_STUB_STATE:?STUB_STATE unset}"
echo "brew $*" >> "$STUB_LOG"
case "$1 $2" in
  "bundle check") [ -f "$STUB_STATE/brew-clean" ] && exit 0 || exit 1 ;;
  "bundle install") touch "$STUB_STATE/brew-clean"; exit 0 ;;
  *) exit 0 ;;
esac
```

Each test sets `MONSTERFLOW_STUB_STATE=$(mktemp -d)` per case. Idempotency case (1) reuses the same `STUB_STATE` across two runs; case 4 pre-stages with state present and removes a marker file mid-test. **Case 1's plan currently has no statement on stub state reset; add it.**

### MF4 — BSD `script -q /dev/null` syntax is wrong on macOS (case 7a)

Acceptance case 7 says "(a) With TTY (`script -q /dev/null` wrapper) → onboard.sh offers graphify prompt." Validated on macOS:

```bash
$ script --help
usage: script [-aeFkpqr] [-t time] [file [command ...]]
```

The macOS BSD form is `script -q /tmp/typescript bash -c '<cmd>'`. There's no `-c` flag; the file argument is required (cannot be `/dev/null` and have it understood as "discard"). Linux `util-linux` accepts `script -q -c "<cmd>" /dev/null` with positionally-flipped args. Plan must:

1. Specify the BSD form: `script -q "$(mktemp -t typescript)" bash -c '<cmd>' < /dev/null` and then read the typescript file for assertions.
2. Acknowledge that even with pty allocation, `< /dev/null` on the outer invocation kills the inner bash with `^D` immediately (validated above — the test produced `^DTTY` then exited). Either (a) feed deterministic input via heredoc-piped FIFO so the inner shell sees real TTY but can still be driven, or (b) use `expect` instead, or (c) drop the assertion to "pty IS allocated when run from an interactive shell" and verify only the negative path (case 9a) automatically.

Recommended: use `expect` (ships with macOS) for case 7a, OR drop case 7a from the automated suite and keep only case 7b (non-interactive negative). Document case 7a as a manual TTY check in the PR description (same pattern as the Linux-guard manual check).

## Should Fix

### SF1 — Case 6d does not cover the "already a symlink" no-op branch (R4)

Spec case 6d pre-stages `~/.tmux.conf` as a real file → asserts `.bak` exists post-run. Good. But `link_file()` (existing lines 91-100) ALSO has a "do nothing if already a symlink" branch that the test doesn't exercise. R4 is "Theme symlink clobbers user config silently" — the regression risk is precisely the case where a future refactor forgets the `[ ! -L "$dst" ]` check and starts backing up symlinks too (turning `~/.tmux.conf -> .../tmux.conf` into `~/.tmux.conf.bak` symlink + new `~/.tmux.conf` symlink, polluting `$HOME` on every re-run).

Add case 6e: pre-stage `~/.tmux.conf` as a symlink (any target). Run install with theme. Assert `~/.tmux.conf.bak` does NOT exist. This costs ~6 lines of test code and locks in the no-op branch.

### SF2 — Case 1's two-run idempotency model needs explicit stub state reset documentation

Tied to MF3. Current plan says "Run install.sh twice in a row." Without specifying `MONSTERFLOW_STUB_STATE`, the second run's brew stub may either (a) persist the `brew-clean` marker (correct for the idempotency assertion) or (b) get wiped (false positive: install stage re-runs both times). Plan needs one sentence in W4 task 4.2: "Case 1 holds `MONSTERFLOW_STUB_STATE` constant across both invocations; case 4 mutates state between invocations."

### SF3 — Negative N2 (Linux guard) cannot be tested on macOS without mocking `uname`

Plan W4 task 4.5 lists N2 as "Linux guard" alongside N1 (unknown flag) and N3 (brew-fail). On the macOS CI runner, `uname` returns `Darwin`. The Linux guard short-circuits on `[ "$(uname)" != "Darwin" ]` — it never fires under the test runner. Two options:

1. **Mock via PATH-stub.** Drop a `tests/fixtures/install-stubs/uname` shim that `echo Linux; exit 0` and PATH-prepend it before invoking install.sh. Same harness mechanism as MF1's PATH-stub; near-zero added cost.
2. **Drop N2 from automation.** Spec already says "Linux guard verified manually." Then plan W4 task 4.5 should read N1 + N3 only, and N2 is a manual PR-description check.

Pick (1) — it's three lines of fixture and converts the manual check into a green automated test that catches a future contributor swapping `uname` for `$OSTYPE` and accidentally letting it pass on Linux.

### SF4 — "Documentation parity" assertion is a manual check, not a test (W5 ship criterion)

W5 ship criterion says: "CHANGELOG.md migration bullets `diff` cleanly against install.sh's `print_upgrade_message` source." This is a real assertion but it lives in the docs wave and has no test file behind it. Two ways to make it real:

- Add a 10-line `tests/test-install-changelog-parity.sh` that greps `print_upgrade_message`'s heredoc body, greps the v0.5.0 section of CHANGELOG.md, and `diff`s the bullet text. Register in `tests/run-tests.sh` TESTS array.
- OR demote it to "manual PR-checklist item; reviewer confirms by eye."

The auto-bump versioning workflow makes the manual route fragile — every minor version bump will tempt someone to update one place and forget the other. Recommend automated parity test; ~15 minutes to write.

### SF5 — Subshell forking model and per-case state isolation is asserted but not validated

D11 + W4 imply each case forks a subshell with a fresh `$HOME=$(mktemp -d)`. With 12 cases × (mktemp + stage fixture + run install.sh + assertions + cleanup) the plan estimates 4-6s local / 13s CI. That's plausible. But:

- `INSTALL_SCRATCH=$(mktemp -d -t monsterflow-install)` (D7) is created INSIDE install.sh per run. Each case's install.sh invocation gets its own scratch. Good, no leak risk there.
- The harness's own `mktemp -d` per case for `$HOME` and `MONSTERFLOW_STUB_STATE` need explicit cleanup `trap` so a mid-suite SIGINT doesn't leave 12 directories. W4 task 4.1 should call this out.
- `export`ed env vars (`MONSTERFLOW_OWNER`, `MONSTERFLOW_NON_INTERACTIVE`, etc.) DO leak across cases unless each case runs in `( … )` subshell or `bash -c '…'`. Pick one and document in W4 task 4.1's "skeleton" line. Recommended: each case is a top-level function, invoked as `( case_3a )` so subshell scoping is automatic.

### SF6 — Cases 7a and 7b do not assert what install.sh actually does — they assert what onboard.sh does

The plan delegates onboarding to `scripts/onboard.sh`. Case 7 wraps the whole install.sh in `script -q` (per MF4 broken anyway), but the prompt being asserted lives in onboard.sh. If a future change makes install.sh skip the onboard call (regression on R-something), case 7 still passes by directly invoking `bash scripts/onboard.sh`. Recommend two test layers:

- One integration test invokes `install.sh` end-to-end and asserts onboard panel substrings appear in install's stdout (proves install.sh CALLED onboard.sh).
- One unit test invokes `bash scripts/onboard.sh` directly under various env-var permutations (proves onboard.sh's internal gating works).

W4 task 4.4 currently rolls case 7 into the install.sh suite. Either split it or add explicit "install.sh stdout contains panel substrings" to the assertion list (not just onboard.sh stdout).

### SF7 — Case 8 migration test fixture path is unspecified

Case 8 says "Pre-stage temp `$HOME` with `~/.claude/commands/spec.md` symlinked to a `*/MonsterFlow/*` path (simulating prior install)." The symlink TARGET file needs to exist (otherwise `[ -L … ]` is true but a future tightening to `[ -L … ] && [ -e "$(readlink …)" ]` flips the test red). Plan should specify:

```bash
PRIOR_REPO="$TEST_HOME/Projects/MonsterFlow-prior"
mkdir -p "$PRIOR_REPO/commands" "$TEST_HOME/.claude/commands"
echo "stub" > "$PRIOR_REPO/commands/spec.md"
ln -sf "$PRIOR_REPO/commands/spec.md" "$TEST_HOME/.claude/commands/spec.md"
```

The spec's migration detect logic uses `case "$PRIOR_TARGET" in */MonsterFlow/*|*/claude-workflow/*)` — the fixture must contain `MonsterFlow` in the path, not just be a dangling symlink. Add to W4 task 4.4.

### SF8 — D11 says "test runtime 4-6s local, 13s CI" but does not say which case dominates

Cases that exec real `brew bundle` would dominate (15-60s). Cases using stubs are sub-second. Plan implicitly assumes all-stub. Confirm in W4 ship criterion that NO test case shells out to real `brew`, real `git push`, real `gh auth login`, real `claude plugins install`. The recursion guard MF2 covers the last two; the brew stub MF3 covers the first. The middle one (`git push`) is irrelevant to install.sh but worth noting that bump-version-style sandboxing patterns (already used in `tests/test-bump-version.sh`) are the precedent — `git -C "$dir" init -q -b main` and stay in the sandbox.

## Observations

### O1 — Spec acceptance criteria count: 9 + 4 sub-cases of 6 + 3 sub-cases of 9 + 2 sub-cases of 7 + 3 N-cases = 17 distinct test bodies (not 12)

Plan W4 task list collapses these into 5 task buckets (4.2 through 4.5 + 4.6). That's fine for task tracking but the runtime budget should be re-estimated against 17 case bodies, not 12. At an average 0.3s per case (PATH-stub model, no real brew), that's still ~5s local, which matches plan's estimate. No change needed beyond noting the count — but if /build trims cases to "fit the budget," the spec contract loosens. Recommend: lock the case count in W4 task 4.1 ("17 case bodies, all required to land green").

### O2 — `bash -n install.sh` shellcheck-equivalent check is the W1 ship criterion but no test enforces it long-term

W1 ship criterion is `bash -n install.sh` passes after 1.5/1.6 land. Good for /build's local feedback loop. Spec's non-test acceptance bar requires `shellcheck install.sh scripts/onboard.sh tests/test-install.sh` returns 0. There's a precedent in `tests/test-hooks.sh` for shellcheck-on-critical-files; recommend the same pattern: a `tests/test-shellcheck-install.sh` that runs shellcheck against the three files and asserts exit 0. This is a separate file from `test-install.sh` (different concern; can run even when the integration suite is skipped). 4 lines of code.

### O3 — D7 `mktemp -d -t monsterflow-install` is BSD-form (template suffix); good

`mktemp -d -t monsterflow-install` is the macOS BSD form (creates `/tmp/monsterflow-install.XXXXXXXX`). Linux `util-linux mktemp -d -t TEMPLATE` requires `XXXXXX` literally in the template. Since this code only ever runs on Darwin (post-Linux-guard), the BSD form is correct and the test harness can use the same form. No change.

### O4 — `[ -t 0 ]` under `</dev/null` reliably returns false on bash 3.2

Validated:

```bash
$ bash -c '[ -t 0 ] && echo TTY || echo NOTTY' </dev/null
NOTTY
```

Case 9a (`install.sh </dev/null`) is mechanically sound. Reliably triggers `MONSTERFLOW_NON_INTERACTIVE=1` auto-set. Same applies to case 9b (explicit `--non-interactive`) and 9c (combined). These three cases are the most testable in the suite — high confidence they will land green on first /build pass.

### O5 — Case 5 (`--no-install` bypass) is straightforward but plan doesn't cover the "REQUIRED missing AND `--non-interactive` AND no `--no-install`" path

Edge-case table in spec says: "If REQUIRED missing, hard-stop with `REQUIRED missing in non-interactive mode; pass --no-install to bypass.`" There's no test case for this combination. It's a likely real-world hit (CI without `--no-install` and without all REQUIRED tools). Recommend folding into case 9a or adding case 9d. Cheap (one extra fork, one assertion on exit 1 + grep for the message).

### O6 — Onboard panel substring assertions are listed in spec acceptance criteria's non-test bar, NOT in the case 7 body

Spec says: "Onboard panel substring assertions. Test 7 (or a new dedicated test) asserts the panel contains literal `/flow`, `/spec`, `dashboard/index.html`." Plan W4 task 4.4 references case 7 but the assertion list inside case 7 (in spec) only mentions "offers graphify prompt" — the panel substring check is implicit. Recommend pulling the substring assertion into the explicit case 7 body in /build, OR creating a 7c sub-case. Otherwise the substring contract has no enforcement.

### O7 — `tests/run-tests.sh` registration (W4 task 4.6) is one line; no risk

`TESTS` array in `run-tests.sh` is alphabetical-ish with dependency ordering already documented. `test-install.sh` slots in last (slowest), per the comment "Cheapest first so failures surface fast." Mechanism is well-precedented (`test-bump-version.sh`, `test-build-final.sh` follow the same pattern). No concerns.

### O8 — Plan does not address `printf %q` portability across bash 3.2 (D6)

`printf %q` works on bash 3.2 (validated; been stable since bash 3.0). However the output format DIFFERS between bash 3.2 and bash 5.x for paths containing apostrophes (`'`) — bash 3.2 uses `\'` outside quotes, bash 5.x uses `\'` style or `$'…'` ANSI-C. For the `.zshrc` source line use case (D6), this is harmless because zsh sources both. But if /build's test harness asserts byte-exact output of the sentinel block via `diff`, the assertion would fail on a contributor's bash 5.x machine. Recommend the test assert via `grep -F "<repo>/config/zsh-prompt-colors.zsh" ~/.zshrc` (substring), not `diff` against a fixture. Add to W4 task 4.3 inline note.

### O9 — `autorun-shell-reviewer` subagent gate (W2 ship criterion) is a process step, not a test

The subagent runs against the cumulative diff before merging W2. This is good discipline but it doesn't replace the test harness. Plan correctly distinguishes the two (subagent = pre-merge code-review-bot, tests = post-merge regression net). No issue, just calling it out so /check stage doesn't double-count.

### O10 — Total testability sketch

After Must-Fix items land, the suite is 17 cases × ~0.3s/case + harness setup ≈ 6-8s local, 15-20s CI. Coverage is high (every flag, every tier, every backup branch, every non-interactive permutation, two negative cases). The single biggest gap is the manual Linux-guard check — convert via SF3 to close it. The single biggest risk is the mock mechanism — fix via MF1 to unblock everything else.
