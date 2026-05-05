# API Contract Freeze — Autorun Overnight Policy (Task 1.5)

**Status:** FROZEN. Wave 2 implementers (`_policy_json.py`, `_policy.sh`, synthesis prompt) build against this document; deviations require a fresh /spec → /check pass.

**Spec:** `docs/specs/autorun-overnight-policy/spec.md` (v5, 26 ACs)
**Plan:** `docs/specs/autorun-overnight-policy/plan.md` (v6)
**Spike:** `scripts/spike/SPIKE_RESULTS.md` (13/13 PASS — portability findings 1-7 are normative input here)
**Schemas:**
- `schemas/morning-report.schema.json`
- `schemas/check-verdict.schema.json`
- `schemas/run-state.schema.json`

**Cross-references:** AC#15 (shell function signatures), AC#12 (Python stdlib `get`), AC#25 (single fence + detection-hardening framing), AC#26 (11-value STAGE enum + `AUTORUN_CURRENT_STAGE` export).

**Negative space (intentional non-requirements):** No nonce mechanism. No 11th `write-key` subcommand. No "last fence" position requirement. No model-echoed-secret authentication. The earlier nonce design (former AC#27) was reverted per Codex H2 of check v3 — *"don't treat model-echoed secrets as authentication"* — and is documented in plan.md D42 [REVERTED v5].

---

## (a) `_policy.sh` — Shell function signatures

`scripts/autorun/_policy.sh` is a sourced helper. Stage scripts (`run.sh`, `check.sh`, `build.sh`, `verify.sh`, `spec-review.sh`, `notify.sh`) `source` it once at startup.

### Source-time fail-fast

At the top of `_policy.sh`, before any function definition:

```sh
command -v python3 >/dev/null || { echo '[policy] python3 required' >&2; exit 2; }
```

Rationale: every helper in this file ultimately delegates JSON read/write/escape to `_policy_json.py`. If `python3` is absent, every downstream call would fail with an opaque "command not found" deep inside a stage; the source-time guard surfaces the missing dep at the earliest possible point (R14). Wave 5 test `test_policy_helper_no_python3` (5.2) verifies this with `env -i PATH=/nonexistent bash -c 'source _policy.sh'` → exit 2; stderr contains `python3 required`.

### Functions (signatures pinned verbatim from spec lines 320-326)

#### `policy_warn STAGE AXIS REASON`

- **Args:** all 3 required. Missing → fail-fast `exit 2`.
- **Behavior:** appends one entry to `run-state.json` `warnings[]` under flock (atomic-append pattern below). Validates `STAGE` against the 11-value enum and `AXIS` against the 6-value enum. `REASON` is JSON-escaped via `_json_escape` before append. Stamps `ts` as current ISO-8601 UTC.
- **Returns:** `0` always.
- **Stderr:** `[policy] warn: stage=<STAGE> axis=<AXIS> reason="<REASON>"`
- **Stdout:** silent.
- **Side effect:** `run-state.json.warnings[]` grows by one. Caller does NOT exit; pipeline proceeds.

#### `policy_block STAGE AXIS REASON`

- **Args:** all 3 required. Missing → fail-fast `exit 2`.
- **Behavior:** appends one entry to `run-state.json` `blocks[]`. Same validation + escaping rules as `policy_warn`.
- **Returns:** **NONZERO** (caller usually `exit 1` after; see D37 pattern below). **`policy_block` does NOT exit on its own** — exiting from a sourced helper would skip the stage's own cleanup/logging. The contract is: the helper returns nonzero, the caller branches and exits with full context.
- **Stderr:** `[policy] block: stage=<STAGE> axis=<AXIS> reason="<REASON>"`
- **Stdout:** silent.
- **Side effect:** `run-state.json.blocks[]` grows by one.

#### `policy_for_axis AXIS`

- **Args:** 1 required.
- **Behavior:** echoes the resolved policy value (`warn` or `block`) for the given axis, computed from the precedence ladder (env > cli-mode > config > hardcoded). `integrity` and `security` are always `block`. Used by stage scripts that want to branch behavior before incurring the side effect.
- **Returns:** `0` on resolved value; `2` on unknown axis (fail-fast).
- **Stdout:** `warn` or `block` (single token, no newline trailing whitespace concerns — callers `$( ... )` it).

#### `policy_act AXIS REASON`

- **Args:** 2 required (NOT 3 — stage is implicit). Missing → fail-fast `exit 2`.
- **Behavior:** the convenience wrapper used at every call site. Reads `$AUTORUN_CURRENT_STAGE` (exported by `run.sh`'s `update_stage()`); if unset → fail-fast `exit 2` with stderr `[policy] error: AUTORUN_CURRENT_STAGE not set`. Resolves policy via `policy_for_axis AXIS`; if `warn` → calls `policy_warn $AUTORUN_CURRENT_STAGE AXIS REASON` (returns 0); if `block` → calls `policy_block $AUTORUN_CURRENT_STAGE AXIS REASON` (returns nonzero).
- **Returns:** propagates `policy_warn` (0) or `policy_block` (nonzero).
- **Documented call pattern (D37 — verbatim, applied at every site):**

```sh
if ! policy_act <axis> "<reason>"; then
  render_morning_report
  exit 1
fi
```

The `if !` form is mandatory. Reason: `set -e` is on across autorun shells; a bare `policy_act ...` that returns nonzero would be caught by `set -e` and skip the `render_morning_report` step. Wrapping the call in `if !` consumes the nonzero RC for the caller's own branch logic. The autorun-shell-reviewer pitfall list (4.1, pitfall #16) enforces this at code-review time.

#### `_json_get JSON_POINTER FILE [DEFAULT]`

- **Args:** 2 required, 1 optional. Pointer first per spec line 327.
- **Behavior:** thin shell wrapper around `_policy_json.py get FILE JSON_POINTER [--default DEFAULT]`. Echoes value (string unquoted, JSON literal otherwise — see `get` subcommand semantics in §(b)).
- **Returns:** `0/2/3/4/5` per pointer/file/json semantics (see `get` subcommand).

#### `_json_escape STRING`

- **Args:** 1 required.
- **Behavior:** echoes JSON-escaped string (no surrounding quotes — caller wraps in `"..."` when interpolating). Backed by `_policy_json.py escape`. Reads stdin if `STRING` is `-`.
- **Returns:** `0`.

### STAGE enum (AC#26 — 11 values, exact spelling)

```
spec-review, plan, check, verify, build, branch-setup, codex-review, pr-creation, merging, complete, pr
```

Coexistence of `complete` and `pr` is a known open question (plan.md Open Question #1) — kept for now; one may consolidate in a follow-up spec. Validators MUST accept both.

### AXIS enum (6 values, exact spelling)

```
verdict, branch, codex_probe, verify_infra, integrity, security
```

Note: `policy_resolution.security_findings` is the resolution KEY (in morning-report + run-state schemas); `security` is the AXIS used in warning/block events. This intentional asymmetry is documented in `morning-report.schema.json` `$defs/axis.description`.

`integrity` and `security` are hardcoded `block` regardless of config; `policy_for_axis` returns `block` for them; `policy_act` on those axes therefore always returns nonzero.

### Atomic-append pattern (bash 3.2)

The locking pattern used by `policy_warn` and `policy_block` to mutate `run-state.json`:

```sh
flock -nx "$STATE_FILE.lock" -c '_policy_json.py append-warning "$STATE_FILE" "$STAGE" "$AXIS" "$REASON"'
```

**SPIKE FINDING 1 (probe 01) — file-form flock is mandatory.** The fd-form `flock -nx 9 ... 9>"$LOCKFILE"` does NOT enforce mutual exclusion across processes on macOS — both contenders acquire fd-9 against the same inode and both succeed (verified empirically). Implementation MUST use the file-form `flock -nx "$LOCKFILE" -c CMD` exclusively. Stock macOS without Homebrew falls back to `mkdir "$LOCKFILE.d"` (atomic) with cleanup trap. Wave 5 test `test_no_flock_in_wrapper` (SF-T2) plus the 2-writer × 100-iter atomic-append torture (verified at probe 13) protect this invariant.

### Atomic symlink rotation

`_policy.sh` does not own `queue/runs/current` symlink rotation directly (that lives in `run.sh` per task 3.1), but if a helper for symlink rotation is added to `_policy.sh` it MUST use the canonical pattern:

**SPIKE FINDING 2 (probe 12) — `mv -fh` (BSD) / `mv -fT` (GNU) with runtime detect.** Plain `mv -f` is broken when DEST is a directory-symlink (it interprets DEST as "move into directory"). `ln -sfn` is non-atomic per SF4 and forbidden. The canonical pattern:

```sh
ln -s "$TARGET" "$LINK.tmp.$$.$RANDOM"
if mv -fh "$LINK.tmp.$$.$RANDOM" "$LINK" 2>/dev/null; then :
elif mv -fT "$LINK.tmp.$$.$RANDOM" "$LINK" 2>/dev/null; then :
else
  echo "[policy] error: symlink rotation requires mv -fh (BSD) or -fT (GNU)" >&2
  exit 2
fi
```

200/200 reads valid, 0 broken windows verified at probe 12.

---

## (b) `_policy_json.py` — CLI surface (10 subcommands FROZEN)

`scripts/autorun/_policy_json.py` is the Python stdlib backend for all JSON read/write/escape/validate operations. AC#12 mandates Python stdlib only; no `jq` shell-out; AST-audited ban list per D34 (Codex M7 enumerated below). 10 subcommands. Adding an 11th requires a fresh /spec → /check.

All subcommands respect a uniform exit-code grammar:

- `0` — success.
- `1` — schema validation failure (subcommand-specific; see `validate`).
- `2` — missing or unreadable file.
- `3` — semantic error (missing-key without `--default`; invalid enum value).
- `4` — malformed JSON in input file.
- `5` — malformed JSON pointer.

### 1. `read <file>`

- **Args:** `<file>` (required, repo-relative or absolute path).
- **Stdin:** none.
- **Stdout:** full JSON of `<file>`, byte-for-byte (no re-formatting).
- **Stderr:** silent on success; error message on failure.
- **Exit:** `0` ok, `2` missing-file, `4` malformed-json.

### 2. `get <file> <pointer> [--default <value>]`

- **Args:** `<file>` (required), `<pointer>` (required, RFC 6901 subset — `/key/0/sub` form, `~0` and `~1` escapes, no URI-fragment form), `--default <value>` (optional).
- **Stdin:** none.
- **Stdout:** dereferenced value. Strings printed unquoted; numbers/booleans/null printed as JSON literal (`true`, `false`, `null`, `42`, `3.14`); objects/arrays printed as compact JSON (single line, no trailing newline beyond one).
- **Stderr:** silent on success; error message on failure.
- **Exit:** `0` ok, `2` missing-file, `3` missing-key (only when `--default` absent), `4` malformed-json, `5` malformed-pointer. With `--default <value>`: missing-key → print `<value>` to stdout and exit `0`.
- **AC#12 cross-ref:** "Python stdlib reader; no jq dependency."

### 3. `append-warning <file> <stage> <axis> <reason>`

- **Args:** all 4 required. `<stage>` validated against 11-value STAGE enum; `<axis>` validated against 6-value AXIS enum.
- **Stdin:** none.
- **Stdout:** silent.
- **Stderr:** silent on success; error message on failure.
- **Behavior:** atomic mutation of `<file>`'s `warnings[]`. Caller (in `_policy.sh`) holds the flock; this subcommand does NOT acquire it (caller-held flock model — keeps locking discipline at one layer). Reads `<file>` via `json.load`; appends `{stage, axis, reason, ts}` where `ts` is `datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')`; writes via `os.replace(<file>.tmp, <file>)` for atomic-on-disk swap.
- **Exit:** `0` ok, `2` missing-file, `3` invalid stage/axis enum value, `4` malformed-json.

### 4. `append-block <file> <stage> <axis> <reason>`

- **Args + behavior:** identical to `append-warning` but writes to `blocks[]` instead of `warnings[]`.
- **Exit:** `0/2/3/4` (same grammar).

### 5. `validate <file> <schema-name>`

- **Args:** `<file>` (required), `<schema-name>` (required — one of `morning-report`, `check-verdict`, `run-state`; resolves to `schemas/<schema-name>.schema.json`).
- **Stdin:** none.
- **Stdout:** silent.
- **Stderr:** on validation failure, prints `(ok=False, errors=[...])` with one error per line.
- **Behavior:** hand-rolled validator (no `jsonschema` package — stdlib only per D34). Walks the schema's `required`, `type`, `enum`, `pattern`, `const`, and `$ref` (within same document) directives. Strict on `additionalProperties: false`.
- **Exit:** `0` valid, `1` invalid (schema mismatch, missing required, type mismatch, pattern fail), `2` missing input file, `4` malformed-json.

### 6. `finding-id <text>`

- **Args:** `<text>` (required, may include spaces — caller quotes).
- **Stdin:** reads stdin if `<text>` is `-`.
- **Stdout:** `ck-<10-hex>` where the 10-hex is the first 10 hex chars of `sha256(normalize_signature(text))`.
- **Stderr:** silent.
- **Exit:** `0` always.
- **Cross-ref:** `check-verdict.schema.json` `blocking_findings[].finding_id` pattern `^ck-[0-9a-f]{10}$`. `ck` prefix = "check stage" — matches the persona-metrics `schemas/findings.schema.json` convention.

### 7. `normalize-signature <text>`

- **Args:** `<text>` (required).
- **Stdin:** reads stdin if `<text>` is `-`.
- **Stdout:** NFC-normalized + lowercased + whitespace-collapsed text (multiple consecutive whitespace runs → single space; leading/trailing trimmed).
- **Stderr:** silent.
- **Exit:** `0` always.
- **Use:** input feeder for `finding-id`; also exposed standalone for diagnostics + reviewer-tag matching.

### 8. `escape <text>`

- **Args:** `<text>` (required).
- **Stdin:** reads stdin if `<text>` is `-`.
- **Stdout:** JSON-escaped string (escapes `"`, `\`, control chars per RFC 8259) — **no surrounding quotes**. Caller wraps in `"..."` at the interpolation site.
- **Stderr:** silent.
- **Exit:** `0` always.
- **Use:** backs `_json_escape` in `_policy.sh`. Pinning this to `_policy_json.py` (Python stdlib `json.dumps(s)[1:-1]`) prevents the bash-sed escaping footgun documented in autorun-shell-reviewer pitfall #18.

### 9. `extract-fence <file> <lang-tag>`

- **Args:** `<file>` (required, content stream — typically synthesis stdout captured to disk), `<lang-tag>` (required, e.g. `check-verdict`).
- **Stdin:** none.
- **Stdout:** line 1 = integer count of `<lang-tag>` fences found; lines 2+ = the fence's JSON content **iff count == 1**.
- **Stderr:** silent on success.
- **Behavior — extraction order matters (Codex M4):**
  1. Read `<file>` as UTF-8.
  2. **NFKC-normalize the entire input stream.**
  3. **Strip zero-width characters** (U+200B, U+200C, U+200D, U+FEFF).
  4. THEN scan line-by-line for ` ```<lang-tag> ` openers — case-sensitive, exact match (e.g. ` ```check-verdict` opens; ` ```Check-Verdict` does NOT; ` ```check-verdict-foo` does NOT).
  5. State machine: outside-fence → on opener match, enter inside-fence; inside-fence → accumulate lines until closing ` ``` `; on close, increment count, save buffer if first match, return to outside-fence.
- **Exit:** `0` always (count + content are stdout payload).
- **Why normalize-before-scan (D33 v6):** post-normalization makes disguised fences (homoglyph `ⅽheck-verdict`, ZWJ-prefixed `‍check-verdict`) collapse to the canonical form; if they were quoted maliciously, they get counted by D33 multi-fence rejection rather than slipping past. Normalize-after would let disguised fences hide.
- **Single-fence-spoof residual (R18, AC#25):** if synthesis omits its own fence and reviewed content quotes one fake `check-verdict` fence, count==1 passes — extractor returns the forged content. D33 catches multi-fence injection but does NOT authenticate single-fence content. Detection-hardening, not prevention. Architectural fix is `autorun-verdict-deterministic` follow-up spec.

### 10. `render-recovery-hint <run-state-path>`

- **Args:** `<run-state-path>` (required).
- **Stdin:** none.
- **Stdout:** markdown recovery hint string derived from `run-state.json`'s `pre_reset_recovery` block. Example shape:

  ```
  Pre-reset recovery available:
  - SHA: <sha>
  - Patch: <patch_path>
  - Untracked archive: <untracked_archive> (<size> bytes)
  - Recovery ref: <recovery_ref>
  - Restore: git checkout <sha> && git stash apply refs/autorun-recovery/<run-id>
  ```

  Suppressed sections when fields are null. When `partial_capture: true`, prepends a `WARNING: partial capture — some artifacts missing` line.
- **Stderr:** silent on success.
- **Exit:** `0` ok, `2` missing-file, `4` malformed-json.

### AST-audited ban list (D34 v6 — Codex M7 enumerated)

`tests/test-autorun-policy.sh::test_policy_json_no_shell_out` parses `_policy_json.py` AST and rejects on any forbidden node. Wave 5 test 5.2.

**Allowed imports:**
- `os`, `os.path`, `json`, `hashlib`, `sys`, `re`, `argparse`, `unicodedata`, `tempfile`, `pathlib`, `datetime` (for ISO-8601 UTC timestamping in `append-warning` / `append-block`).

**Banned imports (any form: top-level, `from X import Y`, aliased):**
- `subprocess`, `multiprocessing`, `socket`, `urllib`, `http`, `ctypes`, `importlib`, `runpy`.
- Aliased imports of banned names — e.g. `from os import system as s` rejected; AST checker tracks the binding.
- `from subprocess import run` (and any `from subprocess import *`).

**Banned calls (Attribute or Name resolving to forbidden):**
- `os.system`, `os.exec*` (`os.execv`, `os.execve`, `os.execvp`, `os.execvpe`, `os.execl`, `os.execle`, `os.execlp`, `os.execlpe`).
- `os.fork`, `os.forkpty`.
- `os.spawn*` (`os.spawnv`, `os.spawnve`, `os.spawnvp`, `os.spawnvpe`, `os.spawnl`, `os.spawnle`, `os.spawnlp`, `os.spawnlpe`).
- `os.popen`.
- `eval`, `exec`, `compile`, `__import__`.
- `os.environ.update`, `os.environ.setdefault`, `os.environ.pop`, `os.environ.clear`.
- `os.putenv`, `os.unsetenv`.
- Subscript-assign on `os.environ` (e.g. `os.environ['X'] = '...'`).

**Rationale:** `_policy_json.py` is on the autorun trust path — every JSON read/write the pipeline does flows through it. Compromising this single file would compromise the entire pipeline's policy decisions. The ban list eliminates any avenue for shell-out, dynamic import, environment mutation, or arbitrary code evaluation. AST-based audit (rather than regex) is necessary to catch aliased imports.

---

## (c) Fenced JSON block format

### Wire contract

Synthesis (`/check` command) emits a freeform-prose response that contains exactly one fenced JSON block tagged `check-verdict`:

````
OVERALL_VERDICT: GO_WITH_FIXES

... prose content, reviewer summaries, codex critique quotations, etc ...

```check-verdict
{
  "schema_version": 1,
  "prompt_version": "check-verdict@1.0",
  "verdict": "GO_WITH_FIXES",
  "blocking_findings": [],
  "security_findings": [],
  "generated_at": "2026-05-05T18:42:11Z"
}
```

... more prose, recommendations, etc ...
````

### Constraints (AC#25)

- **Exactly one** ` ```check-verdict ` fence per synthesis output.
- **No "last fence" position requirement** — the fence may appear anywhere in the stream.
- **Other-language fences unconstrained** — both in count and position. Quoted JSON code samples, ` ```sh ` examples, ` ```diff ` blocks, even reviewer prose containing a ` ```json ` block are all fine.
- **Case-sensitive, exact lang-tag match** — ` ```check-verdict ` opens; ` ```Check-Verdict ` does not; ` ```check-verdict-v2 ` does not.
- **No nonce field.** v6 dropped the nonce mechanism per Codex H2 — *"don't treat model-echoed secrets as authentication"*. Earlier drafts proposed a `nonce` field that synthesis would echo back; the model-visible nonce is not a trust boundary.

### Sidecar JSON contents

The extracted fence content MUST validate against `schemas/check-verdict.schema.json`. Required keys:

- `schema_version: 1` (integer const).
- `prompt_version: "check-verdict@1.0"` (string const — bumped when the synthesis contract or schema changes).
- `verdict`: one of `GO`, `GO_WITH_FIXES`, `NO_GO`.
- `blocking_findings[]`: array of `{persona, finding_id, summary}`. Empty iff `verdict == GO`.
- `security_findings[]`: array of `{persona, finding_id, summary, tag}` where `tag` is the const `sev:security`.
- `generated_at`: ISO-8601 UTC timestamp.

`finding_id` derivation: `ck-<first 10 hex of sha256(normalize-signature(summary))>`. Subcommands `finding-id` and `normalize-signature` produce these deterministically, allowing reviewers and consumers to derive the same id from the same signature.

### Extractor decision table (D33 v6)

| `check-verdict` fence count | `OVERALL_VERDICT:` first line | Outcome |
|---|---|---|
| **>1** | any | `policy_block check integrity "multiple check-verdict fences (possible prompt injection)"` |
| **0** | present | `policy_block check integrity "synthesis omitted check-verdict block"` |
| **0** | absent | legacy grep fallback (one-release back-compat; removed in v0.9.0) + deprecation warning |
| **1** | any | extract → `check-verdict.json` sidecar; strip fence from stream; write remaining to `check.md`; validate sidecar via `_policy_json.py validate <file> check-verdict`; on schema fail → `policy_block check integrity "malformed sidecar"`; on success → consume `verdict` + `security_findings[]` per AC#5/#4 |

### Known v1 residual — single-fence-spoof class

**Documented limitation, deferred fix.** D33 multi-fence rejection raises the cost of the easy attack class (synthesize multiple fences and hope one wins) but does NOT authenticate a single fence quoted from reviewed content:

- Attack: prompt-injection content embedded in spec/review text contains its own ` ```check-verdict\n{forged GO}\n``` ` block. Synthesis omits its own fence (or is induced to). Extractor sees count==1 → forged GO ships.
- Mitigation in v1: synthesis prompt requirement #5 instructs the model to emit a verdict fence and also embed authoring guidance (requirement #6) for 4-backtick fencing of any quoted ` ```check-verdict ` content, so legitimate reviewer quotations don't inadvertently inflate the count. Additionally, doctor.sh emits an R18 visibility line on every run and CHANGELOG carries a "Known v1 limitation" section.
- **Adopter recommendation (R18):** for repos processing untrusted spec sources (third-party PRs, externally-authored queue items), set `verdict_policy=block` and disable unattended auto-merge until the architectural fix ships.
- **Architectural fix:** follow-up spec `autorun-verdict-deterministic` (BACKLOG entry, sized XL) drops the synthesis-emits-sidecar pattern entirely; reviewers emit structured `sev:security` + verdict tags; post-processor aggregates `check-verdict.json` deterministically without trusting any model-emitted fence.
- **Framing (per Codex H2 from check v4):** D33 + prompt-hardening is **detection-hardening, not prevention**. This wording is normative for AC#25, doctor.sh output, CHANGELOG section, and run.sh `--help` text.

### Extraction order (Codex M4 — restated, normative)

The extractor MUST NFKC-normalize and zero-width-strip the input stream BEFORE scanning for ` ```<lang-tag> ` openers. Order matters: normalize-after would let homoglyph and zero-width-prefixed disguised fences slip past the count, defeating D33 multi-fence rejection. `_policy_json.py extract-fence` enforces this order (§(b) subcommand 9).

---

## Sign-off checklist (for Wave 2 implementers)

Before declaring `_policy.sh` / `_policy_json.py` / synthesis prompt complete, verify:

- [ ] All 6 shell functions implemented with exact signatures (§(a)).
- [ ] Source-time `command -v python3` fail-fast present and tested (R14 / SF-T7).
- [ ] STAGE enum has all 11 values; AXIS enum has all 6 values; both validated in `policy_warn` / `policy_block` / `append-warning` / `append-block`.
- [ ] `policy_block` returns nonzero (does NOT exit); every call site uses the `if ! policy_act` pattern (D37).
- [ ] `_policy_json.py` ships exactly 10 subcommands (no 11th, no `write-key`).
- [ ] AST audit (`test_policy_json_no_shell_out`) passes against the enumerated ban list.
- [ ] `extract-fence` performs NFKC-normalize + zero-width-strip BEFORE scanning.
- [ ] All flock invocations use file-form (`flock -nx FILE -c CMD`); zero `flock -nx N ... N>FILE` patterns.
- [ ] Atomic symlink rotation (anywhere it occurs) uses `mv -fh` / `mv -fT` runtime detect.
- [ ] Synthesis prompt contract: exactly one `check-verdict` fence; no nonce instruction; v1 limitation language quoted in `--help` + CHANGELOG + doctor.sh.
- [ ] `prompt_version` const is `"check-verdict@1.0"` in the sidecar; matches schema const.
