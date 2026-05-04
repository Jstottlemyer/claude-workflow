---
name: install-rewrite
description: Pivot install.sh from a checker into a detect → install → verify → onboard flow with brew-bundle install, owner-vs-adopter theme baseline, indexing kickoff, and a regression-proofed test harness.
created: 2026-05-03
constitution: none — defaults-only roster (precedent: pipeline-wiki-integration, persona-metrics, spec-upgrade)
confidence: 0.90 (scope 0.90 · ux 0.90 · data 0.85 · integration 0.85 · edge_cases 0.88 · acceptance 0.92)
session_roster: defaults only (27 stock personas — no domain agents installed for this spec)
---

# Install Rewrite Spec

*Session roster only — run /kickoff later to make this a persistent constitution.*

## Summary

Pivot `install.sh` from its current "detect → warn → symlink" flow into "detect → install → verify → onboard." Today an adopter who runs the one-liner ends up with a working symlink graph but no `gh`, no `shellcheck`, no `jq`, and no idea what to type next; features degrade silently. After this spec, a fresh-Mac adopter ends with a demonstrably-working pipeline, a one-screen "what to do next" panel, and (if they opt in) a baseline shell theme matching MonsterFlow's dogfood configuration.

The change is **additive surgery** on the existing 354-line `install.sh`, not a rewrite. Existing logic — owner-vs-adopter detection, persona-metrics gitignore default-flip, post-commit hook installation, sentinel-bracketed gitignore blocks — is preserved verbatim. New stages slot in: brew-bundle install (single confirm), config-theme symlink (owner-vs-adopter default flip), and a new standalone `scripts/onboard.sh` that prints the next-steps panel and kicks off graphify + wiki indexing when their detection conditions hold.

## Backlog Routing

| # | Item | Source | Routing |
|---|------|--------|---------|
| 1 | Opinionated idempotent install.sh | BACKLOG.md:46-68 | **(a) In scope — this spec** |
| 2 | Per-plugin cost measurement | BACKLOG.md:13-17 | (b) Stays — token-economics track |
| 3 | Plugin scoping per gate | BACKLOG.md:19-23 | (b) Stays — depends on #2 |
| 4 | Holistic token instrumentation | BACKLOG.md:25-42 | (b) Stays — partially in token-economics spec |
| 5 | Account-type agent scaling | BACKLOG.md:72-78 | (b) Stays — depends on token-economics |
| 6 | Inter-agent debate (Agent Teams) | BACKLOG.md:82-89 | (b) Stays — research-grade, deferred |

## Scope

### In scope

- Brewfile-driven install of REQUIRED + RECOMMENDED tools (Brewfile already shipped in commit 9c08163)
- `python_pip()` helper wired into install.sh and any sister scripts that currently hardcode `pip3` (helper already shipped in 9c08163)
- Tier-aware decline behavior: REQUIRED-missing hard-stops, RECOMMENDED-missing continues with loud notice
- Brew itself promoted to REQUIRED tier (no special-case code path); error message names the brew.sh URL and the install command
- `cmux` added to RECOMMENDED (homebrew-cask formula, auto-updates); `tmux` demoted to OPTIONAL
- New `config/` directory shipping neutral opinionated defaults: `cmux.json`, `tmux.conf`, `zsh-prompt-colors.zsh`
- `--install-theme` / `--no-theme` flags; default behavior is owner-default-YES (when `PWD == REPO_DIR`), adopter-default-NO
- `--no-install` flag — skip brew-bundle (CI / restricted envs); symlinking still runs
- New standalone `scripts/onboard.sh` invoked by install.sh as its last step; independently re-runnable
- onboard.sh runs `scripts/doctor.sh`, prints next-steps panel, optionally kicks off graphify indexing (`bootstrap-graphify.sh`) and wiki indexing (`wiki-export` skill if `~/.obsidian-wiki/config` exists)
- onboard.sh offers `gh auth login` if `gh` installed but unauthenticated
- onboard.sh surfaces codex opt-in as a single line ("Want adversarial review? Run `/codex:setup`")
- `tests/test-install.sh` — 7 idempotency/behavior cases (see Acceptance Criteria); runs against a temp `$HOME` so it doesn't touch the dev machine

### Out of scope

- Linux support (per BACKLOG.md: "the brew assumption is macOS-only; Linux can wait until there's a real Linux adopter")
- Auto-bootstrapping brew via `curl | bash` (rejected on security grounds — adopter must run brew's installer themselves; we just print the URL)
- Migrating autorun off tmux to a native headless flow (parked under Open Questions; "tmux is used in our headless flow — not sure if we should keep it or use a native headless flow but good either way")
- Per-tool install prompts (rejected as friction — bulk single-confirm is the agreed UX)
- Refactoring the existing 354 lines into helper modules (rejected — additive surgery only)

## Approach

**Additive surgery** on `install.sh`, not a wholesale rewrite. The existing file does several things well and has memory-backed institutional knowledge baked in (PWD-vs-basename owner detection per `feedback_install_adopter_default_flip.md`; sentinel-bracketed gitignore block; auto-bump hook installation; persona-metrics default-flip). Preserving all of it verbatim is the lowest-risk path to closing the BACKLOG.md gap.

**The flow becomes:**

```
1. Parse flags         (--no-install, --install-theme/--no-theme — NEW)
2. Detect tier-by-tier  (existing has_cmd loop — extend to include `brew` in REQUIRED)
3. Install missing      (NEW — brew bundle --file=Brewfile, single confirm; respects --no-install)
4. Decline behavior     (NEW — REQUIRED hard-stop, RECOMMENDED loud-notice continue)
5. Symlink files        (existing — commands, personas, scripts, autorun, settings)
6. Adopter-vs-owner     (existing — queue/.gitignore, persona-metrics gitignore block)
7. Install theme        (NEW — config/ symlinks, default flipped by owner detection)
8. CLAUDE.md baseline   (existing)
9. Git hooks            (existing — install-hooks.sh wiring)
10. Plugin install      (existing — claude plugins install)
11. Validate            (existing — tests/run-tests.sh)
12. Onboard             (NEW — bash scripts/onboard.sh; non-blocking; printed at end)
```

Stages 5–11 are unchanged code. Stages 1, 3, 4, 7, 12 are new. Stage 2 gets one line added to extend REQUIRED with `brew`.

**Why not wholesale rewrite:** Loses too much memory-backed detail. The PWD-based owner detection took a memory entry to land correctly; the gitignore sentinel pattern took another. A blank-slate rewrite would either re-litigate those decisions or accidentally drop them.

**Why not extract-into-helpers:** Premature refactor on top of a feature, violates "don't add abstractions beyond what the task requires" from global CLAUDE.md. If install.sh later grows past ~500 lines, extraction is a follow-up spec.

## Roster Changes

No roster changes. Defaults-only roster (27 stock personas) covers this work — `unix-philosophy`, `idempotency-checker`, `error-handling`, `installer-design`, `shell-script-quality`, `os-compatibility`, `documentation-clarity` are all stock personas that align with the work.

## UX / User Flow

### Fresh-Mac adopter (full happy path)

```
$ git clone https://github.com/Jstottlemyer/MonsterFlow.git ~/Projects/MonsterFlow
$ cd ~/Projects/MonsterFlow && ./install.sh

=== Claude Workflow Pipeline Installer — v0.4.3 ===
Repo:   /Users/.../MonsterFlow
Target: /Users/.../.claude

✗ REQUIRED — pipeline will not work without these:
  - brew (Homebrew) — install from https://brew.sh:
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  - claude (Claude Code CLI) — https://claude.com/claude-code

Install these and re-run install.sh.
$ exit 1
```

After adopter installs brew + claude, re-run:

```
$ ./install.sh
=== Claude Workflow Pipeline Installer — v0.4.3 ===

✓ REQUIRED tools present
⚠ RECOMMENDED missing: gh, shellcheck, jq, cmux

About to install via Homebrew (uses Brewfile at repo root):
  - gh         (GitHub CLI — /autorun PR ops)
  - shellcheck (shellcheck PostToolUse hook)
  - jq         (jq PostToolUse hook)
  - cmux       (Ghostty-based terminal for AI agents — cask)

Proceed? [Y/n]: <enter>

[brew bundle install runs]
✓ brew bundle complete

Installing pipeline commands... [existing output]
Installing personas... [existing output]
[…all the existing symlink output…]

Install MonsterFlow shell theme? [y/N]: y
  LINKED: ~/.tmux.conf -> /Users/.../MonsterFlow/config/tmux.conf
  LINKED: ~/.config/cmux/cmux.json -> /Users/.../MonsterFlow/config/cmux.json
  ✓ source ~/.local/share/MonsterFlow/zsh-prompt-colors.zsh added to ~/.zshrc (sentinel-bracketed)

[…rest of existing install output…]

=== Installation complete ===

Running scripts/onboard.sh...

╭─ MonsterFlow is ready ──────────────────────────────╮
│                                                       │
│  Next steps:                                          │
│    1. cd into a project                               │
│    2. /flow            — see the workflow card        │
│    3. /spec            — design your first feature    │
│    4. open ~/Projects/MonsterFlow/dashboard/index.html│
│                                                       │
│  Optional:                                            │
│    • Index ~/Projects/ for the dashboard? [y/N]       │
│    • Authenticate gh CLI now? (gh auth login) [y/N]   │
│    • Want adversarial review? Run /codex:setup        │
│                                                       │
╰───────────────────────────────────────────────────────╯
```

### Owner re-run (you, on your dev machine)

```
$ ./install.sh
=== Claude Workflow Pipeline Installer — v0.4.3 ===

✓ REQUIRED tools present
✓ RECOMMENDED tools present

[brew bundle check — nothing to install]
[symlinks — all already present, no-op]
[theme — owner default YES, files already symlinked]
[onboard — prints panel; offers indexing only if not run recently]

=== Everything already in place ===
exit 0   (under 2 seconds)
```

### CI / restricted env

```
$ ./install.sh --no-install
[detection runs but install stage is skipped]
[symlinks proceed]
[onboard prints panel but doesn't offer indexing kickoff]
```

## Data & State

### `Brewfile` (already shipped, may add `cmux` cask)

```ruby
# REQUIRED
brew "git"
brew "python@3.11"

# RECOMMENDED
brew "gh"
brew "shellcheck"
brew "jq"
cask "cmux"        # NEW — Ghostty-based terminal for AI coding agents
# tmux removed from default — moved to OPTIONAL (offline/headless flows)
```

### `config/` directory (NEW)

```
config/
├── cmux.json                    # neutral opinionated cmux config (vertical tabs, dark theme)
├── tmux.conf                    # high-contrast cyan/grey theme (matches Justin's CLAUDE.md notes)
└── zsh-prompt-colors.zsh        # sourceable file; theme-only, no behavioral changes
```

These files ship in-repo, are reviewable in git history, contain zero network calls — satisfies the "safety from a security standpoint" requirement: every byte is auditable before it lands on the adopter's disk.

### `scripts/onboard.sh` (NEW, standalone)

Independently re-runnable. Outline:

```bash
#!/bin/bash
# scripts/onboard.sh — post-install onboarding panel
# Re-run anytime: `bash ~/Projects/MonsterFlow/scripts/onboard.sh`

set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# 1. Run doctor.sh to verify wiring
bash "$REPO_DIR/scripts/doctor.sh"

# 2. Print next-steps panel (boxed; copy-pasteable commands)
print_panel

# 3. Optional kickoffs (each gates on detection)
[ -d "$HOME/Projects" ] && offer_graphify_bootstrap
[ -f "$HOME/.obsidian-wiki/config" ] && offer_wiki_indexing
has_cmd gh && ! gh auth status >/dev/null 2>&1 && offer_gh_auth
has_cmd codex || echo "  Want adversarial review? Run /codex:setup"
```

### Flag surface (new)

- `--no-install` — skip brew bundle stage (CI / restricted envs)
- `--install-theme` — force theme install on (overrides owner-vs-adopter default)
- `--no-theme` — force theme install off
- (existing flags / env vars preserved: `PERSONA_METRICS_GITIGNORE`)

### State changes on disk

| Path | Owner-default | Adopter-default | Sentinel-bracketed? |
|------|---------------|-----------------|---------------------|
| `~/.tmux.conf` → `config/tmux.conf` | symlinked | prompt-y/N | N/A (symlink, not append) |
| `~/.config/cmux/cmux.json` → `config/cmux.json` | symlinked | prompt-y/N | N/A |
| `~/.zshrc` (one line: `source <repo>/config/zsh-prompt-colors.zsh`) | appended | prompt-y/N | YES (`# BEGIN MonsterFlow theme` / `# END MonsterFlow theme`) |

The `.zshrc` append uses the same sentinel-bracketing pattern already proven by the persona-metrics gitignore block, so re-running install.sh is idempotent and `--no-theme` on a later run can cleanly remove the block.

## Integration

### Files modified

- `install.sh` — additive surgery only; new flag parsing, install stage, decline handler, theme stage, onboard call
- `Brewfile` — already at repo root (commit 9c08163); add `cask "cmux"` and remove `brew "tmux"`
- `scripts/lib/python-pip.sh` — already at repo path (commit 9c08163); wire into `install.sh` via `source` and use in any sister script that hardcodes `pip3`

### Files created

- `scripts/onboard.sh` — new standalone, ~80 lines
- `config/cmux.json` — new
- `config/tmux.conf` — new (port from Justin's existing personal tmux config, sanitized to "neutral opinionated")
- `config/zsh-prompt-colors.zsh` — new
- `tests/test-install.sh` — new harness covering the 7 acceptance cases below

### Existing code preserved verbatim

- `has_cmd()` PATH-augmenting helper (lines 21-25) — extend its callers, not the function
- Owner-vs-adopter detection (lines 190-202)
- `write_queue_gitignore()` (lines 208-225)
- Persona-metrics default-flip block (lines 232-278) — sentinel-bracketed
- CLAUDE.md baseline merge (lines 280-292)
- Git hooks installation (lines 294-303)
- Plugin install prompts (lines 305-316)
- Test suite validation (lines 318-326)

### Touchpoints with other scripts

- `scripts/bootstrap-graphify.sh` — onboard.sh invokes it on user opt-in (already exists, no changes needed)
- `scripts/doctor.sh` — onboard.sh invokes it (already exists)
- `scripts/install-hooks.sh` — install.sh continues to call it (already exists)
- `scripts/lib/python-pip.sh` — install.sh sources it; sister scripts that hardcode `pip3` get migrated incrementally (low priority — not blocking for this spec; tracked under Open Questions)

## Edge Cases

### Tier-split decline behavior (Q5 (d))

| State | Behavior |
|-------|----------|
| REQUIRED missing AND user declines auto-install | Hard-stop. Print install command per tool. Exit 1. |
| RECOMMENDED missing AND user declines | Continue with loud notice: "Continuing without [list]. Features will silently no-op (PR ops, shellcheck hook, etc.). Re-run install.sh anytime to install." |
| `--no-install` flag passed | Skip install stage entirely. Symlinks still run. Print one-line notice: "Skipped install per --no-install. Some features may be degraded." |

### Brew not installed (Q6 (c+b))

Brew gets a REQUIRED-tier entry (`has_cmd brew || REQUIRED_MISSING+=("brew (Homebrew) — install from https://brew.sh: <one-liner>")`). The unified REQUIRED-missing panel handles it; no special-case code path. Adopter runs the brew installer themselves (no `curl | bash` from us); the friction of one extra step is the security tradeoff Justin explicitly chose.

### Partial brew state (jq uninstalled, others present)

`brew bundle --file=Brewfile` is natively idempotent — installs only what's missing, no-ops on present formulas. Acceptance case 4 covers this.

### Re-run on fully-installed system

- `has_cmd` checks pass for all tiers
- `brew bundle check --file=Brewfile` returns clean → skip the install stage entirely
- Symlinks already exist → `ln -sf` no-ops
- Theme: if owner, all symlinks already present → no-op; if adopter, `~/.tmux.conf` already exists as a symlink to `config/tmux.conf` → no-op
- `.zshrc` sentinel block exists → skip append
- onboard.sh: doctor runs, panel prints, indexing offers gate on "not-run-recently" sentinel files (`~/.local/share/MonsterFlow/.last-graphify-run`)
- Total runtime: under 2 seconds (acceptance case 2)

### `--no-theme` on a system with theme already installed

Spec deliberately does NOT remove the existing theme. `--no-theme` only governs default-no-prompt for the current run. To uninstall the theme cleanly, adopter runs a separate `scripts/uninstall-theme.sh` (out of scope — added if/when an adopter actually asks for it).

### Network failure mid-`brew bundle`

Brew handles its own retries and reports failed formulas. install.sh catches the non-zero exit and prints: "brew bundle failed for [N] formulas. Re-run install.sh after fixing network/registry. Symlinking is also skipped to avoid a half-installed state." Exit 1.

### macOS without Xcode CLI tools

`git` from Xcode CLI is the typical first install. If both `git` and Xcode CLI are absent, the REQUIRED panel prints `xcode-select --install` for git's install command (current install.sh already does this — preserved).

### Terminal that doesn't render box-drawing characters

The onboarding panel uses Unicode box-drawing (`╭─╮│╰─╯`) — degrades acceptably to garbage on legacy terminals but doesn't break the script. If this becomes a real adopter complaint, fall back to plain ASCII (`+----+ | | +----+`).

## Acceptance Criteria

`tests/test-install.sh` runs all 7 cases below against a temp `$HOME` (created with `mktemp -d`, sourced into a subshell with `HOME=<tmp>`) so it never touches the dev machine. Each case asserts via `[[ ]]` / `grep` / `diff` against expected output; one failure halts the suite with the case number and last 20 lines of output.

1. **Idempotency under repeat runs.** Run `install.sh` twice in a row. Diff stdout — must be byte-identical (modulo timestamps). No duplicate symlinks (verified via `find $HOME/.claude -type l -exec readlink {} \; | sort | uniq -d` returns empty). No duplicate PATH entries in `~/.zshrc` (verified via sentinel block grep).
2. **Fast no-op on fully-installed system.** Pre-stage a temp `$HOME` with all symlinks present, all brew tools detectable. Run `install.sh`. Asserts: stdout contains "everything already in place"; exit code 0; total wall-clock under 2 seconds.
3. **Fresh-Mac happy path.** Pre-stage temp `$HOME` with no symlinks, mock `has_cmd` to report all tools missing (via PATH manipulation pointing to a tmp dir with no binaries). Run `install.sh`. Asserts: REQUIRED panel printed, hard-stop on REQUIRED-missing exits with code 1.
4. **Re-install after `brew uninstall jq`.** Pre-stage all symlinks present, all tools present except jq. Run `install.sh`. Asserts: install stage runs (single confirm prompt → simulated `Y`), `brew bundle install` invoked with `--file=Brewfile`, post-install `has_cmd jq` passes, no other state mutated (diff symlink graph before/after — must be identical).
5. **`--no-install` flag.** Run `install.sh --no-install` on a fresh temp `$HOME`. Asserts: install stage skipped (no `brew bundle` invocation in stdout), symlinks still created, exit code 0 (or 1 if REQUIRED missing, with hard-stop messaging).
6. **Theme install honors owner-vs-adopter default.** (a) Run from `$REPO_DIR` with no `--no-theme` flag → theme symlinks created without prompt. (b) Run from a different cwd (simulating adopter) with no flag → prompt printed; simulated `N` → no theme symlinks created. (c) Adopter run with `--install-theme` → theme symlinks created without prompt. Each variant verified via `[ -L ~/.tmux.conf ]` assertion.
7. **Indexing kickoff gates on detection.** (a) Pre-stage temp `$HOME` with `~/.obsidian-wiki/config` present and `~/Projects/test-proj/some.py` present → onboard.sh offers both indexing prompts. (b) Pre-stage with neither → onboard.sh runs silently (no indexing prompts in stdout). Verified via `grep -c "Index ~/Projects" output.txt` returning 1 vs 0 across the two variants.

Plus a non-test acceptance bar:

- **Shellcheck-clean.** `shellcheck install.sh scripts/onboard.sh tests/test-install.sh` returns 0 with no warnings.
- **Documentation parity.** `README.md`'s install one-liner still works post-change (no flag-rename break). `QUICKSTART.md` updated to describe the new install/onboard split if any flow change affects users.

## Open Questions

1. **Tmux in autorun.** Justin's Q3 answer: "tmux is used in our headless flow — not sure if we should keep it or use a native headless flow but good either way." Demoting tmux to OPTIONAL in this spec assumes autorun continues to use it (and adopters of autorun can install tmux on demand). If a follow-up spec migrates autorun to a native headless approach (`nohup`, `disown`, plain `&`), tmux can be removed from OPTIONAL entirely. Tracked here, not blocking.
2. **Sister-script `pip3` migration.** `scripts/lib/python-pip.sh` is wired into `install.sh` in this spec. Other scripts that currently hardcode `pip3` (per global CLAUDE.md note: `bootstrap-graphify.sh` and venv-install paths) are NOT migrated in this spec — that's a separate sweep. Open question: do them in this spec, or follow-up? Current call: follow-up (out of scope here to keep the diff focused).
3. **`config/` file contents.** Spec names the three files (`cmux.json`, `tmux.conf`, `zsh-prompt-colors.zsh`) but doesn't pin exact contents. /plan resolves this — needs a per-file pass naming the colors, the tmux key bindings, the prompt format, and any safety review against shipping anything tied to Justin's machine specifically (e.g., absolute paths in tmux.conf must be `$HOME`-relative).
4. **Versioning.** Adding flags + new files is a `feat:` commit per the auto-bump rules → minor bump (0.4.x → 0.5.0). Confirm at /plan time whether this should be one commit or several (e.g., one per stage).
