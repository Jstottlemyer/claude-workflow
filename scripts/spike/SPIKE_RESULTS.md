# macOS bash 3.2 Portability Spike — Results

**Task:** 1.1 of `docs/specs/autorun-overnight-policy/plan.md` (v6)
**Host:** macOS Darwin 24.6.0 (arm64), GNU bash 3.2.57(1)-release
**Probes run:** 12 primitives + 1 atomic-append torture test = 13 total
**Result:** **13/13 PASS**
**Run command:** `for s in scripts/spike/*.sh; do /bin/bash "$s"; done`

## Summary table

| # | Primitive | macOS result | GNU result | Canonical command | Notes / portability gotchas |
|---|-----------|--------------|------------|-------------------|------------------------------|
| 01 | `flock` non-blocking exclusive | PASS (Homebrew) / fallback to mkdir on stock | PASS | **`flock -nx "$LOCKFILE" -c CMD`** (file-form). On stock macOS without Homebrew: `mkdir "$LOCKFILE.d"` (atomic). | **Critical macOS gotcha:** the **fd-form** (`flock -nx 9 ... 9>"$LOCKFILE"`) does NOT enforce mutual exclusion across processes on macOS — both contenders acquire fd-9 against the same inode and both succeed (probe verified this empirically). Implementation MUST use the file-form OR mkdir-fallback. NEVER the fd-form. Doctor.sh must warn if `flock` absent. |
| 02 | `timeout` (124-on-expiry) | PASS via `gtimeout` (Homebrew coreutils) | PASS via `timeout` | `gtimeout 600 cmd` (prefer); `timeout 600 cmd` (fall back) | Stock macOS does NOT ship `timeout` or `gtimeout`. Adopter must `brew install coreutils`. Doctor.sh must check both. |
| 03 | `uuidgen` lowercase | PASS — macOS uuidgen emits UPPERCASE; lc-normalize required | PASS | **`RUN_ID="$(uuidgen \| tr 'A-Z' 'a-z')"`** | AC#13 regex `^[0-9a-f]{8}-...` rejects uppercase. SF3 fix is mandatory before regex match. |
| 04 | `mktemp` portable | PASS | PASS | **`mktemp -t "${prefix}.XXXXXX"`** (file) / **`mktemp -d -t "${prefix}.XXXXXX"`** (dir) | The `XXXXXX` template is required by BSD mktemp (not optional). GNU `--tmpdir` works on this host but is not portable; do not use it. |
| 05 | `ps -o lstart` | PASS — stable across reads | PASS | **`ps -o lstart= -p "$PID"`** (note `=` to suppress header) | BSD `lstart` format: `Tue May  5 13:32:49 2026` (multi-space; sed-trim before comparison). Lockfile staleness check: read PID+lstart from lockfile, query live ps, exact-match → live; mismatch or empty → stale. |
| 06 | `jq` absent (stdlib JSON only) | PASS | PASS | `python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[...])'` | AC#12 mandates Python stdlib only. `_policy_json.py` MUST NOT shell out to `jq`. AST audit (D34 Codex M7) enforces this. |
| 07 | `sed -i` (in-place) | PASS via `-i.bak` | PASS via `-i.bak` | **`sed -i.bak 's/old/new/' file && rm "${file}.bak"`** | BSD `sed -i` REQUIRES backup-extension argument; bare `sed -i` fails on macOS. The `.bak`+rm form works on both BSD + GNU. NEVER use bare `sed -i`. |
| 08 | `date` ISO-8601 UTC | PASS | PASS | **`date -u +%Y-%m-%dT%H:%M:%SZ`** | `date -d <string>` is GNU-only; BSD rejects it. For BSD parsing, use `date -j -f FMT STR +%s`. Implementation MUST NOT use `date -d`. |
| 09 | `stat` size + mtime | PASS via BSD `-f` | PASS via GNU `-c` | **Detect:** `if stat -f %z FILE >/dev/null 2>&1; then BSD; else GNU; fi`. **BSD:** `stat -f '%z' FILE` (size), `stat -f '%m' FILE` (mtime). **GNU:** `stat -c '%s' FILE`, `stat -c '%Y' FILE`. | Different flag, different format codes. Helper function in `_policy.sh` should encapsulate. |
| 10 | `tar --exclude` | PASS on bsdtar 3.5.3 | PASS | **`tar --exclude='PATTERN' -czf OUT -C SRC .`** | bsdtar honors `--exclude=PAT`. |
| 11 | `tar --null -T -` (NUL list from stdin) | PASS | PASS | **See `queue/.spike-output/tar-untracked.cmd`** (consumed by task 3.3 per Codex L12) | Verified with newline-in-path filename fixture (SF5). The full canonical command emitted to spike-output is: `git ls-files -z --others --exclude-standard \| tar --null -T - -czf "$ARCHIVE" --exclude='node_modules' --exclude='.git'`. |
| 12 | Atomic symlink rotation | PASS — 200/200 reads valid, 0 broken | PASS | **BSD:** `ln -s tgt link.tmp.<id>.<i> && mv -fh link.tmp.<id>.<i> link`. **GNU:** `mv -fT` instead of `-fh`. | NEVER use `ln -sfn` (non-atomic per SF4). When the target is a directory and the link already exists, plain `mv -f` interprets DEST as "move into directory"; BSD `-h` (don't follow symlink) and GNU `-T` (treat DEST as normal file) both prevent this. Detect at runtime. |
| 13 | Atomic-append torture (2 writers × 100 iter) | PASS — 200 lines, balanced (A=100, B=100), all valid JSON | PASS | `flock -x "$LOCK" -c "printf ... >> \"$TARGET\""` (file-form) | Validates the `_policy.sh` atomic-append pattern from spec lines 334-343. **File-form flock is mandatory** for the same macOS reason as probe 01. |

## Critical findings the rest of the plan must internalize

1. **macOS fd-form flock is broken** (probe 01). The pattern `flock -nx 9 ... 9>"$LOCKFILE"` — which is the canonical Linux idiom — does NOT provide mutual exclusion on macOS in our testing. The autorun-shell-reviewer pitfall list (4.1) and `_policy.sh` (2.1) MUST use the file-form `flock -nx "$LOCKFILE" -c CMD` exclusively. Update pitfall #17 to call this out explicitly. The atomic-append torture confirms file-form works correctly.

2. **No `timeout` in stock macOS** (probe 02). Doctor.sh (4.2) MUST detect missing `gtimeout`/`timeout` and emit a doctor block telling the adopter to `brew install coreutils`. Otherwise `TIMEOUT_PERSONA` config is meaningless.

3. **Atomic symlink rotation needs `-fh`/`-T`** (probe 12). The SF4 pitfall said "use temp+`mv -f`, not `ln -sfn`" — but plain `mv -f` is itself broken when the destination is a directory-symlink. The correct portable canonical is `mv -fh` (BSD) / `mv -fT` (GNU); detect at runtime. Pitfall list addition for 4.1.

4. **uuidgen uppercase** (probe 03). Already in SF3, but reaffirmed. `RUN_ID="$(uuidgen | tr 'A-Z' 'a-z')"` MUST happen BEFORE the AC#13 regex match.

5. **`tar --null -T -` is bsdtar-supported** (probe 11). Canonical command emitted to `queue/.spike-output/tar-untracked.cmd`; task 3.3 reads from there per Codex L12. Verified round-tripping a filename containing a literal newline.

6. **`set -e` + expected-failure pattern** (lessons learned from writing probes themselves). When testing for non-zero exit (e.g. lock contention), use `if cmd; then RC=0; else RC=$?; fi` — NOT `set +e ... RC=$? ... set -e` (the `set -e` toggle is racy with line-by-line execution and the ERR trap can still fire). Add to pitfall list.

7. **Bash 3.2 has no `$BASHPID`** (probe 12 dev). In `&`-backgrounded subshells, `$$` is the parent PID, so two parallel writers get the same `$$`. Pass an explicit writer-id for tmp-file uniqueness. Already in CLAUDE.md memory. Reaffirm for 4.1.

## Files produced

- `scripts/spike/01-flock.sh` … `scripts/spike/12-atomic-symlink.sh` (12 primitive probes)
- `scripts/spike/atomic-append-torture.sh` (torture test)
- `scripts/spike/SPIKE_RESULTS.md` (this file)
- `queue/.spike-output/tar-untracked.cmd` (canonical command for task 3.3)

## How to re-run

```bash
for s in scripts/spike/*.sh; do echo "=== $(basename $s) ==="; /bin/bash "$s"; echo "EXIT=$?"; done
```

All 13 must print a `PASS:` line and exit 0.
