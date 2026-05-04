# `install-rewrite` Implementation Plan

**Created:** 2026-05-04
**Spec:** `docs/specs/install-rewrite/spec.md` v1.1 (sha256 `f7cb4706…`)
**Design agents:** 7 (api, data-model, ux, scalability, security, integration, wave-sequencer)
**Constitution:** none — defaults-only roster

## Architecture Summary

Install.sh becomes an **opinionated, idempotent, owner-vs-adopter-aware installer** via additive surgery on the existing 354-line script. Net delta: **+180 / −8 lines, ~12 edited; ends at ~530 lines.** The single deletion is the existing "Continue anyway?" prompt (lines 82-88) — fully replaced by tier-aware decline. The single swap is owner detection (lines 190-202) → hardened variant that preserves the `OWNER`/`ADOPTER_ROOT` contracts that downstream code depends on.

**Three ordering invariants** (per integration agent) hold across all waves:

1. **Linux guard** runs between current lines 2–4, before any path computation
2. **SIGINT trap** is installed before the first `.monsterflow.tmp` write (Stage 9 theme is the first such writer)
3. **Migration detect** runs before any symlink mutation, so opt-out cleanly bails

**Critical-path waves:** `W1 → (W2 || W3) → W4 → W5`. W1 (data + flag contract) closes everything downstream code reads, then W2 (install.sh stages, strictly sequential) and W3 (onboard.sh, depends only on env contract) can author in parallel.

## Design Decisions

### D1 — Flag surface (7 flags, fixed)

`--help`/`-h`, `--no-install`, `--install-theme`, `--no-theme` (wins over `--install-theme`), `--non-interactive` (auto-detect via `[ -t 0 ]`), `--no-onboard`, `--force-onboard` (overrides non-interactive panel suppression).

**Argv parse runs BEFORE Linux guard** so `install.sh --help` works on Linux.

### D2 — Exit code matrix

| Code | Meaning |
|------|---------|
| 0 | Success / `--no-install` bypass / `--help` / RECOMMENDED-only-missing-and-declined |
| 1 | REQUIRED-missing (no `--no-install`), Linux guard, brew-bundle failure |
| **2** | **Unknown flag (NEW)** — distinguishes user-error from REQUIRED-missing |
| 130 | SIGINT cleanup |

### D3 — Env var contract

| Env var | Set by | Read by | Effect |
|---------|--------|---------|--------|
| `MONSTERFLOW_OWNER` | user | install.sh | `=1` force owner; `=0` force adopter (test ergonomics — extends spec) |
| `MONSTERFLOW_NON_INTERACTIVE` | install.sh flag-parse | install.sh + onboard.sh | suppress all prompts |
| `MONSTERFLOW_FORCE_ONBOARD` | install.sh flag-parse | onboard.sh | run panel even under non-interactive |
| `MONSTERFLOW_INSTALL_TEST` | tests/test-install.sh | install.sh | short-circuit plugin-install + test-suite-validate prompts (resolves the recursion bug Scalability discovered) |
| `HOMEBREW_NO_AUTO_UPDATE=1` | install.sh top | brew | non-negotiable for the `<3s` repeat-run budget |
| `PERSONA_METRICS_GITIGNORE` | (existing) | (existing) | unchanged |

### D4 — Owner detection (hardened, per integration)

```bash
detect_owner() {
    if [ "${MONSTERFLOW_OWNER:-}" = "1" ]; then echo 1; return; fi
    if [ "${MONSTERFLOW_OWNER:-}" = "0" ]; then echo 0; return; fi
    local script_dir git_root
    script_dir="$(cd "$(dirname "$0")" && pwd -P)"
    git_root="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || true)"
    [ -n "$git_root" ] && [ "$script_dir" = "$git_root" ] && echo 1 || echo 0
}
```

### D5 — `config/` file contents (data-model pins, resolves spec Open Q2)

- `config/cmux.json` — 3-key minimal: `app.appearance: system`, `sidebar.branchLayout: vertical`, `notifications.sound: default`. Path verified: `~/.config/cmux/cmux.json`.
- `config/tmux.conf` — `Ctrl-a` prefix, 256-color cyan (`colour51`) / dark grey (`colour234`) palette, `~/.tmux.local.conf` source-hook for adopter overrides. All paths `$HOME`-relative.
- `config/zsh-prompt-colors.zsh` — 5 env-overridable color vars, minimal `_monsterflow_git_branch` helper, two-line prompt. **Pure theme, no PATH/alias/plugin behavior.**

### D6 — `.zshrc` sentinel block (security-hardened)

```bash
# BEGIN MonsterFlow theme
[ -f "<repo>/config/zsh-prompt-colors.zsh" ] && source "<repo>/config/zsh-prompt-colors.zsh"
# END MonsterFlow theme
```

The `<repo>` path is written via `printf %q` to handle spaces/specials safely (Security T9 mitigation; references the 2026-04-20 PEM-in-`.secrets` incident).

### D7 — SIGINT cleanup (security-hardened)

Per Security T6: replace the spec's permissive `find $REPO_DIR $CLAUDE_DIR -name '*.monsterflow.tmp' -delete` with a scoped `mktemp -d` directory + `rm -rf <single-dir>`. Pre-staged glob attack is impossible.

```bash
INSTALL_SCRATCH="$(mktemp -d -t monsterflow-install)"
cleanup_partial() {
    rm -rf "$INSTALL_SCRATCH"
    echo "" >&2
    echo "⚠ install.sh interrupted; partial state cleaned up." >&2
    echo "  Re-run when ready." >&2
    exit 130
}
trap cleanup_partial INT TERM
```

All atomic writes use `$INSTALL_SCRATCH/<name>.tmp` then `mv -f` to final.

### D8 — Brew-bundle catch (resolves spec finding sr-pipefail10)

```bash
if ! HOMEBREW_NO_AUTO_UPDATE=1 brew bundle --file="$REPO_DIR/Brewfile" install; then
    echo "⚠ brew bundle failed for some formulas." >&2
    echo "  Common causes: network, broken bottle, locked Cellar." >&2
    echo "  Fix and re-run install.sh. Symlinks were skipped." >&2
    exit 1
fi
```

### D9 — `gh auth status` timeout (per Scalability)

Wrap with bash trap-alarm (macOS lacks GNU `timeout`); 5-second cap. Behind a corporate proxy that swallows port 443, install no longer hangs at the very last step.

### D10 — Migration banner version (resolves data-model open Q)

Banner pulls from `VERSION` file at runtime: `VERSION="$(cat "$REPO_DIR/VERSION" | tr -d '[:space:]')"` — already done at line 9 of install.sh, just reuse `$VERSION` in the migration message.

### D11 — Test harness mock + recursion guard

- Mock strategy: `has_cmd() { return 1; }` defined in test, `export -f has_cmd` to inherit into install.sh's bash child.
- Recursion guard: tests set `MONSTERFLOW_INSTALL_TEST=1`; install.sh skips `claude plugins install` and `bash tests/run-tests.sh` prompts under that flag.

### D12 — UX exact strings

All prompts, panels, error messages frozen by ux agent. See `plan/raw/ux.md` for the canonical text. Key invariants:

- Box-drawing chars used; content-survives-degrade discipline (every line readable as plain text if box chars render as `?`)
- Glyph budget capped at `✓ ✗ ⚠ ○ ⬆ ╭─╮│╰─╯ •` — no emoji, no new arrows beyond `→`
- `[Y/n]` for safe/expected actions, `[y/N]` for mutating/opt-in
- All `⚠ ✗` to stderr, success to stdout (CI-grep-friendly)
- Onboard panel pinned 64 chars wide × 13 rows; contains literal `/flow`, `/spec`, `dashboard/index.html`

## Implementation Tasks

### Wave 1 — Data + Flag Contract (parallel-safe, low risk)

| # | Task | Files | Depends On | Size | Parallel? | Notes |
|---|------|-------|------------|------|-----------|-------|
| 1.1 | Brewfile cmux/tmux swap | `Brewfile` | — | S | yes | Add `cask "cmux"`, remove `brew "tmux"` |
| 1.2 | Write `config/cmux.json` | new | — | S | yes | 3-key minimal per D5 |
| 1.3 | Write `config/tmux.conf` | new | — | S | yes | Ctrl-a + cyan/grey 256-color per D5 |
| 1.4 | Write `config/zsh-prompt-colors.zsh` | new | — | S | yes | 5 vars + helper per D5 |
| 1.5 | Add flag-parse + env contract block to install.sh | `install.sh` (top) | — | M | no | Per D1, D2, D3; before Linux guard |
| 1.6 | Source `python_pip` helper in install.sh (forward-compat) | `install.sh` | 1.5 | S | no | After SIGINT trap, before migration detect |

**Ship criterion:** `bash -n install.sh` passes after 1.5 + 1.6 land; flag table in install.sh source matches D1.

### Wave 2 — install.sh Stages (strictly sequential, high risk)

| # | Task | install.sh location | Depends On | Size | Risk |
|---|------|---------------------|------------|------|------|
| 2.1 | Linux guard (Stage 0) | between current lines 2–4 | 1.5 | S | low |
| 2.2 | SIGINT trap + `INSTALL_SCRATCH` mktemp (Stage 2) | after 2.1, before any tmp write | 2.1 | S | medium |
| 2.3 | Migration detect (Stage 3) | after 2.2, before symlink stages | 2.2 | M | medium |
| 2.4 | Brew → REQUIRED tier (extends Stage 4) | line 35 area | 1.5 | S | low |
| 2.5 | Hardened owner detection swap (replaces 190-202) | replaces existing block | 1.5 | M | medium |
| 2.6 | Install stage with `if !` brew-bundle catch (Stage 5) | after detection panel, before symlinks | 2.4 | M | high |
| 2.7 | Tier-split decline behavior (Stage 6, REPLACES lines 82-86) | replaces "Continue anyway?" prompt | 2.6 | M | high |
| 2.8 | Theme stage with `link_file()` reuse (Stage 9) | after persona-metrics block | 2.7 | M | medium |
| 2.9 | Wrap existing prompts in `NON_INTERACTIVE` guard | lines 284, 307, 312, 321 | 1.5 | S | low |
| 2.10 | Onboard call (Stage 14, last) | after test-suite-validate | 2.9 | S | low |

**Ship criterion:** `shellcheck install.sh` returns 0; manual smoke test on owner-machine: `MONSTERFLOW_OWNER=1 ./install.sh` runs cleanly.

**Subagent gate:** before merging W2, dispatch `autorun-shell-reviewer` against the cumulative diff (per CLAUDE.md: "invoke before committing changes that touch scripts/autorun/*.sh" — same discipline applies to install.sh given the size).

### Wave 3 — `scripts/onboard.sh` (parallel to W2 once W1 closes, low-medium risk)

| # | Task | Files | Depends On | Size |
|---|------|-------|------------|------|
| 3.1 | Write `scripts/onboard.sh` outline (panel, doctor invocation, exit-code semantics) | new | 1.5 | M |
| 3.2 | `gh auth login` offer with trap-alarm 5s timeout (per D9) | inside 3.1 | 3.1 | S |
| 3.3 | `bootstrap-graphify.sh` offer gated on `~/.local/share/MonsterFlow/.last-graphify-run` mtime (`+7` re-offer gate) | inside 3.1 | 3.1 | S |
| 3.4 | `[ -t 0 ]` + `MONSTERFLOW_NON_INTERACTIVE` gating on every prompt | inside 3.1 | 3.1 | S |
| 3.5 | Codex one-liner echo (no prompt) | inside 3.1 | 3.1 | S |

**Ship criterion:** `shellcheck scripts/onboard.sh` returns 0; `MONSTERFLOW_NON_INTERACTIVE=1 bash scripts/onboard.sh` prints the panel without prompts and exits 0.

### Wave 4 — `tests/test-install.sh` (medium risk, deferred until W2/W3 frozen)

| # | Task | Files | Depends On | Size |
|---|------|-------|------------|------|
| 4.1 | Test harness skeleton: `mktemp -d` HOME, function-shadow `has_cmd`, brew-stub | new | W2 + W3 | M |
| 4.2 | Cases 1, 2, 3, 3a, 4 (idempotency, no-op, hard-stop, happy-path, brew-uninstall) | inside 4.1 | 4.1 | M |
| 4.3 | Cases 5, 6 (--no-install bypass, theme owner/adopter/backup matrix) | inside 4.1 | 4.1 | M |
| 4.4 | Cases 7, 8, 9 (indexing gating, migration, non-interactive variants) | inside 4.1 | 4.1 | M |
| 4.5 | Negative cases N1–N3 (unknown flag → exit 2, Linux guard, brew-fail) | inside 4.1 | 4.1 | S |
| 4.6 | Register in `tests/run-tests.sh` TESTS array (last position, slowest) | `tests/run-tests.sh` | 4.5 | S |

**Ship criterion:** `bash tests/run-tests.sh` exits 0 on owner-machine with all 9 + 3 cases green; runtime < 30s local, < 60s CI target.

### Wave 5 — Docs (low risk)

| # | Task | Files | Depends On | Size |
|---|------|-------|------------|------|
| 5.1 | README.md install one-liner verified post-rewrite (no flag-name break) | `README.md` | W2 | S |
| 5.2 | QUICKSTART.md updated with flag surface + migration messaging | `QUICKSTART.md` | W2 | S |
| 5.3 | CHANGELOG.md created/updated with v0.5.0 entry; bullets match install.sh's migration message verbatim | `CHANGELOG.md` | W2, W3 | S |
| 5.4 | BACKLOG.md item 1 (Onboarding) deleted post-merge | `BACKLOG.md` | merge | S |

**Ship criterion:** README install one-liner runs cleanly on a fresh `mktemp -d`; CHANGELOG.md migration bullets `diff` cleanly against install.sh's `print_upgrade_message` source.

## Three-Gate Mapping (data → UI → tests)

- **Data gate (W1):** Brewfile, `config/`, flag-parse + env contract, `python_pip` source line. Every downstream consumer reads from these.
- **UI gate (W2 + W3):** install.sh stages + onboard.sh. Honors W1's flag/env contract.
- **Tests gate (W4):** `tests/test-install.sh` validates everything W2/W3 produced.

## Open Questions

1. **`MONSTERFLOW_OWNER=0` for test ergonomics** — api proposes extending `=1` to also accept `=0` for "force adopter" mode. Security didn't address it. **Recommend yes**: it's a test convenience, not a privilege escalation (adopter mode is more restrictive than owner mode).
2. **Migration detect under `--non-interactive`** — print upgrade-diff to stderr and proceed silently, OR skip the migration message entirely? **Recommend stderr-print + auto-proceed.** Adopter on CI re-running install.sh shouldn't see a hang and shouldn't lose the audit trail.
3. **Stage 14 `|| { breadcrumb }`** masks onboard.sh syntax errors during dev. **Recommend** adding `bash -n scripts/onboard.sh` as part of W3's ship criterion to catch this at build time.
4. **`config/` file contents pre-review** — wave-sequencer flagged whether Justin should pre-review the literal config bytes before /build emits them. **Recommend yes**: 5-minute review of 3 small files; lower regret than landing and discovering tmux config doesn't match Justin's existing tmux muscle memory.
5. **Bootstrap-graphify defensive edit** — integration recommends a small defensive edit to `bootstrap-graphify.sh` (honor `MONSTERFLOW_NON_INTERACTIVE`). Out of this spec's surface but a 3-line change. **Recommend yes** as a tiny W5 follow-up commit.

## Risks

| # | Risk | Wave | Mitigation |
|---|------|------|------------|
| R1 | install.sh stages land out-of-order → SIGINT trap missing when tmp written → orphan files | W2 | Strict sequential commit ordering 2.1→2.10; `autorun-shell-reviewer` subagent on cumulative diff |
| R2 | Test harness recursion via install.sh's existing prompts (Scalability discovery) | W4 | `MONSTERFLOW_INSTALL_TEST=1` env flag; W2 task 2.9 wraps every existing prompt |
| R3 | `gh auth status` hangs on corporate proxy, kills <3s budget | W3 | trap-alarm 5s timeout (D9) |
| R4 | Theme symlink clobbers user config silently | W2 (2.8) | `link_file()` BACKUP→.bak pattern; Acceptance case 6d |
| R5 | `.zshrc` source line breaks on path with spaces or special chars | W2 (2.8) | `printf %q` quoting (Security T9 mitigation) |
| R6 | SIGINT cleanup deletes attacker-staged files | W2 (2.2) | `mktemp -d` scoped scratch + `rm -rf <dir>` (Security T6) |
| R7 | Migration banner hardcodes wrong version after auto-bump | W2 (2.3) | `${VERSION}` from VERSION file at runtime (D10) |
| R8 | Net delta ~530 lines pushes install.sh near the "extract into helpers" threshold | W2 | Acceptable for v1; extraction tracked as future spec only if file grows past ~600 lines |
| R9 | Adopter on macOS without Xcode CLI gets cryptic git error before Linux guard | W2 (2.1) | Linux guard checks `uname`; Xcode CLI absence still hits REQUIRED panel (existing behavior) |
| R10 | Box-drawing renders as garbage on legacy terminal | W3 | content-survives-degrade discipline; deferred ASCII fallback (UX recommendation) |

## Convergence Notes (Judge Pass 1)

**Strong convergence (3+ agents agreed):**

- Flag surface (api, ux, integration) — pinned identical
- `--non-interactive` propagation via env var (api, integration, scalability) — `MONSTERFLOW_NON_INTERACTIVE` adopted
- Test harness needs recursion guard (scalability headline; integration confirmed via existing-prompt wrapping)
- Linux guard placement (api, integration) — between lines 2–4
- `config/` contents pinning (data-model pinned; api + ux + security all reference data-model's contents)

**Resolved divergences:**

- api proposed exit 2 (unknown flag); no other persona contradicted → adopt
- ux: keep box-drawing, no ASCII fallback → adopt (matches spec; lowest /build effort)
- integration deletes lines 82-88 ("Continue anyway?") — bigger than spec's "additive surgery" framing implies, but resolves spec-review finding sr-additivesurgery16 and is the only clean way to honor tier-split decline (Q5d in spec)
- security extends `MONSTERFLOW_OWNER` to be loud-logged + `$HOME`-ownership-validated (api was silent on this; security wins)

**Agent disagreements resolved:**

- None substantive. data-model and api both addressed `python_pip` integration; integration's "after SIGINT trap, before migration detect" placement subsumes both.
