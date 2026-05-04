# Scope Discipline Review — install-rewrite plan

## Verdict

**PASS WITH NOTES** — the plan is largely justified by spec/BACKLOG, but it has accumulated ~3-5 cuttable items (worth ~10-15% of build time) that are gold-plating relative to the user-confirmed MVP cut ("wiki only, keep theme + cmux"). None are fatal; all are cleanly droppable without breaking the user-facing contract.

The 21-task plan can ship the BACKLOG.md ask in **~16 tasks** with no loss of user-visible behavior. Recommend taking the cuts before /build to avoid the "we already wrote it, leaving it in" anchor.

## Must Fix Before Building

None. (Scope-discipline doesn't gate; it advises.) All items below are SHOULD-FIX with rationale.

## Should Fix (proposed cuts)

### C1 — Drop `MONSTERFLOW_INSTALL_TEST` env var; use `MONSTERFLOW_NON_INTERACTIVE` instead (D3, R2, task 2.9)

**Cut confidence: HIGH. Impact if kept: LOW.**

The plan introduces 5 net-new env vars (D3 table). `MONSTERFLOW_INSTALL_TEST` is one-of-one — exists solely to short-circuit `claude plugins install` and `bash tests/run-tests.sh` recursion in the test harness. But task 2.9 already wraps every existing prompt in `NON_INTERACTIVE` guard. A test harness running install.sh has no TTY (tests use `mktemp -d` HOME, subshell), so `[ -t 0 ]` auto-sets `MONSTERFLOW_NON_INTERACTIVE=1`. Plugin-install and test-suite-validate prompts under non-interactive should already skip — that's the contract from spec line 51 ("disables every prompt, selects safe defaults").

If non-interactive doesn't skip plugin-install, that's a bug in 2.9, not a need for a second env var. **Fix 2.9, delete the env var.** Saves: 1 env var in user-visible contract (4 instead of 5), reduces test-harness surface.

### C2 — Collapse Open Question #1 + Open Question #4 + Open Question #5 (none are real questions for /check)

**Cut confidence: HIGH. Impact if kept: LOW (gold-plating of /check time).**

- **Q1 (`MONSTERFLOW_OWNER=0`)**: plan already recommends "yes." This is a decision, not a question. Delete the question, add `=0` to D3 row.
- **Q4 (`config/` file pre-review)**: this is a process step ("Justin reviews 3 small files before commit"), not a plan question. Move it to a /build pre-flight checklist line and delete from Open Questions.
- **Q5 (bootstrap-graphify defensive edit)**: 3-line change explicitly tagged as W5 follow-up. Either include it as task 5.5 or delete it. Don't leave it ambiguous in Open Questions.

Result: Open Questions drops from 5 → 2 (only Q2 migration-under-non-interactive and Q3 `bash -n` ship-criterion are genuine open decisions). This isn't task work, but it's plan-doc gold-plating that signals false uncertainty.

### C3 — Merge task 5.4 (delete BACKLOG item 1) into task 5.3 (CHANGELOG commit)

**Cut confidence: HIGH. Impact if kept: LOW.**

Task 5.4 is a one-line deletion in BACKLOG.md. The CHANGELOG.md commit at 5.3 is the natural moment to also retire the source backlog item ("shipped → remove from backlog"). Splitting into a dedicated task adds a commit that says "delete BACKLOG.md:46-68" — noise in git log. Merge: 5.3 becomes "CHANGELOG.md + BACKLOG.md cleanup."

Saves: 1 task, 1 commit.

### C4 — CI grep gate against `curl|wget|eval|bash <(` (Security T9, referenced via D6/R5) is overengineered

**Cut confidence: MEDIUM. Impact if kept: LOW (CI second), but it's testing for an attack surface we don't have.**

The `.zshrc` sentinel block sources a file from a known repo path written by `printf %q` quoting. The threat model "attacker crafts a `<repo>` path containing `; curl … | bash`" requires the attacker to control `$REPO_DIR`, which is `$(cd "$(dirname "$0")" && pwd -P)` — i.e., the attacker already has write access to the repo. At that point grep-gating one line in `.zshrc` is theatre.

`printf %q` (already in D6) is the right defense. The CI grep gate is gold-plating for a small theme repo with one shell-sourced file. **Cut the grep gate, keep `printf %q`.** If it stays, scope it to "fail CI if `.zshrc` block contains literal `curl http`" — narrower, intent-clear, no false positives on legitimate config.

(Note: this is referenced indirectly via Security T9 mitigation language but doesn't appear as a discrete task in W1-W5. If it isn't a task, it's already cut — verify with security agent.)

### C5 — `gh auth status` 5s trap-alarm timeout (D9, task 3.2) is genuine risk, KEEP

**Cut confidence: LOW. Impact if kept: LOW (justified).**

Reviewed for completeness: this is NOT gold-plating. R3 cites "corporate proxy that swallows port 443" — the kind of failure an adopter at a real company will hit. 5s ceiling on the very last step (onboard panel) is worth ~15 lines of bash. Keep.

### C6 — Negative tests N1-N3 (task 4.5) — all 3 are warranted, but N3 (brew-fail) overlaps acceptance case 4

**Cut confidence: MEDIUM. Impact if kept: LOW.**

- N1 (unknown flag → exit 2) — required, exit-code matrix has it as a public contract. KEEP.
- N2 (Linux guard) — required, only automated check we'll have for the guard. KEEP.
- N3 (brew-fail) — overlaps with the implicit happy/unhappy path of acceptance case 4 ("re-install after brew uninstall jq"). If N3 is "brew bundle returns non-zero, install.sh exits 1, no symlinks created," that's the negative complement to case 4. Either: (a) merge N3 INTO case 4 as case 4b, or (b) keep N3 standalone and trim case 4 to just the happy re-install path.

Recommend (a) — same brew stub already in scope for case 4, two assertions in one test setup. Saves: ~one test scaffolding block.

### C7 — Theme stage contents review: `zsh-prompt-colors.zsh` is the most cuttable of the three theme files

**Cut confidence: MEDIUM. Impact if kept: MEDIUM (Justin specifically chose to keep theme).**

User picked "keep theme." Within the three files (D5):

- **`config/cmux.json`** — 3 keys, directly justifies the cmux Brewfile addition. Without this, "we install cmux" is half-done. KEEP.
- **`config/tmux.conf`** — Justin uses tmux daily (per user CLAUDE.md, dev-session.sh). Owner-dogfood justified. KEEP.
- **`config/zsh-prompt-colors.zsh`** — 5 env-overridable color vars + `_monsterflow_git_branch` helper + two-line prompt. This is the LEAST justified by "owner dogfood": Justin's existing zsh prompt setup (per `~/.zshrc` references in user CLAUDE.md) already exists. Adding a sourced file that mutates the prompt risks conflict with the existing setup; pure-color overrides could live as 5 env vars set in `.zshenv.local` (which user CLAUDE.md already documents).

**Recommendation:** keep cmux.json + tmux.conf, **defer zsh-prompt-colors.zsh to a follow-up spec.** The `.zshrc` sentinel block (D6, ~3 lines + `printf %q` quoting + Security T9 attention) is overhead specifically for this one file. Cutting it eliminates the entire `.zshrc` mutation path — no sentinel block, no `printf %q`, no D6 entirely.

If kept, that's fine — Justin gets to choose. But this is the highest-impact single cut available (eliminates a whole risk class).

### C8 — `MONSTERFLOW_FORCE_ONBOARD` env var (D3) could be merged into the flag (D1)

**Cut confidence: LOW. Impact if kept: LOW.**

The flag `--force-onboard` is the user-facing contract. The env var exists to propagate from install.sh into the onboard.sh subprocess. This is a legitimate impl detail (env vars cross process boundaries; flags don't auto-propagate). KEEP — but consider whether it needs to be in the public D3 table or just an internal implementation detail. Renaming to `_MONSTERFLOW_FORCE_ONBOARD` (leading underscore = private) signals "don't depend on this." Cosmetic; not blocking.

## Observations

### O1 — Task count 21 is proportionate, not bloated

W1=6, W2=10, W3=5, W4=6, W5=4. The W2 sequential chain (2.1→2.10) is the longest, but each task maps to exactly one new install.sh stage from spec section 4 ("the flow becomes" diagram). No "while we're in here" cleanup, no premature refactors. Plan honored the spec's "additive surgery" framing.

### O2 — Spec already absorbed the FAIL→cut from /spec-review

The spec at v1.1 dropped wiki-export indexing per the FAIL verdict, and the plan never resurrected it. Good discipline carrying through. Theme + cmux were explicitly kept by user — plan respects that.

### O3 — `bash trap-alarm 5s timeout` for `gh auth status` is genuine risk

Per C5 above. Don't cut.

### O4 — Net delta ~530 lines (R8) is acknowledged but not a scope creep signal per se

The line count grows because the user-facing contract grows (new flags, migration messaging, theme stage). Each line is traceable to spec. R8's "tracked as future spec only if file grows past ~600 lines" is the right posture.

### O5 — Wave structure is genuinely parallelizable

W2 and W3 can run in parallel after W1 closes — that's 10 + 5 tasks compressed into max(10, 5) = 10 wall-clock units, not 15. Plan documents this correctly. No cut needed.

## Minimum Viable Plan Comparison

**Current plan: 21 tasks across 5 waves.**

**Minimum viable cut (still ships BACKLOG.md ask):**

| Wave | Current | MVP cut | Tasks dropped/merged |
|------|---------|---------|----------------------|
| W1 | 6 tasks (1.1-1.6) | 5 tasks | Drop 1.4 (`zsh-prompt-colors.zsh`) per C7 |
| W2 | 10 tasks (2.1-2.10) | 9 tasks | 2.8 (theme stage) shrinks to cmux.json + tmux.conf only — no `.zshrc` sentinel block; no D6 |
| W3 | 5 tasks (3.1-3.5) | 5 tasks | No change |
| W4 | 6 tasks (4.1-4.6) | 5 tasks | Merge 4.5 N3 (brew-fail) into 4.2 case 4 per C6 |
| W5 | 4 tasks (5.1-5.4) | 3 tasks | Merge 5.4 (BACKLOG cleanup) into 5.3 (CHANGELOG) per C3 |
| **Total** | **21** | **17** | **4 tasks cut/merged** |

**What MVP loses, user-facing:**
- No `~/.zshrc` prompt-color theming (only cmux + tmux themed)
- One fewer commit in /build merge train (BACKLOG cleanup folded into CHANGELOG commit)

**What MVP keeps, user-facing:**
- All BACKLOG.md:46-68 requirements
- `--no-install`, `--non-interactive`, `--no-onboard`, `--install-theme`, `--no-theme`, `--force-onboard`, `--help`
- cmux + tmux theme baseline (Justin's owner-favored extras)
- v0.4.x → v0.5.0 migration messaging
- Linux guard, SIGINT trap, owner detection hardening
- All 9 acceptance cases + 2 negative cases (N1, N2)
- onboard.sh + doctor.sh + graphify offer + gh auth offer + codex one-liner

**Build-time savings estimate: ~15-20%** (4 tasks of ~21, but the cut tasks include the two highest-risk theme-related bits — `.zshrc` sentinel + Security T9 mitigation — which is disproportionate risk reduction for the line count).

**Recommendation:** present C1, C3, C6, C7 to Justin as a single "MVP-cut Y/N?" decision before /build. C7 is the only one that changes user-facing behavior; the other three are purely internal cleanup.
