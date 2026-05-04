# Testability Check — Token Economics (spec v4.1 + plan 4-wave)

**Date:** 2026-05-04
**Reviewer:** testability (`/check`)
**Lens:** Can we verify the plan worked? Each task → clear pass/fail signal?

## Verdict

**PASS WITH NOTES** — every acceptance criterion has at least one named test owner and a machine-checkable assertion shape; a handful of inverted-assertion + grep-regex + visual-threshold details need pinning before `/build` so test authors don't have to re-derive intent. None of the gaps block planning; they're all "make the test author's job unambiguous" tightening.

## Must Fix (untestable assertions that would block /build)

None. Every A0–A11 + A1.5 has a named test file and an explicit assertion shape. The items below are Should Fix.

## Should Fix (tighten before Wave 3 test authors start)

### 1. `leakage-fail.jsonl` inverted assertion needs a runner contract (A10)
A10(d) says the deliberate-failure fixture "makes the allowlist test fail when run alone (proves the test catches violations)." This is the classic inverted-assertion trap — a test that asserts another test fails. Pin in plan/spec exactly one of:
- A separate sibling script `tests/test-allowlist-meta.sh` that invokes `tests/test-allowlist.sh` against ONLY `leakage-fail.jsonl` and asserts `$? -ne 0` AND that stderr matches an expected violation marker (e.g. `additionalProperties.*forbidden_field`). Without checking the message, a test that crashes for unrelated reasons (missing file, syntax error) would falsely "pass" the meta-test.
- OR have `test-allowlist.sh` accept a `--expect-fail <fixture>` mode that internally inverts the exit code AND verifies the violating field name appears in the failure output.
Pick one and name it in Wave 1.9 or Wave 3.4.

### 2. `tests/test-no-raw-print.sh` regex needs an explicit positive + negative corpus
Plan task 1.2 / 3.5 names the grep gate but no regex. Naive `grep -E 'print\(' compute-persona-value.py` will:
- Fire on `# print(...)` comments (false positive).
- Fire on `safe_log(...)` if regex is too loose (won't, but worth pinning).
- Miss `print (foo)` with a space, `__builtins__.print(...)`, or `sys.stdout.write(...)` (sibling to stderr).
Specify in Wave 1.2:
- Regex shape: e.g. `^[[:space:]]*(print[[:space:]]*\(|sys\.stderr\.write|sys\.stdout\.write)` (anchored to start-of-statement, after whitespace, NOT after `#`).
- Positive corpus: a 4-line fixture file with `print("x")`, `  print("x")`, `sys.stderr.write("x")`, `sys.stdout.write("x")` — test asserts grep matches all 4.
- Negative corpus: `# print("ok")`, `safe_log("event")`, `"print(" in s` (string literal containing the token) — test asserts grep matches none.
- Apply scope: only `scripts/compute-persona-value.py` (NOT `tests/`, NOT `scripts/redact-persona-attribution-fixture.py` which legitimately CLI-prints).

### 3. Salt file perms test — cross-platform 600 (A: privacy regression)
Plan task 3.4 says "salt file perms = 600." On macOS/Linux, `stat -f '%Lp' file` (BSD) vs `stat -c '%a' file` (GNU) differ. Pin in test:
- Use `python3 -c 'import os, stat, sys; m = stat.S_IMODE(os.stat(sys.argv[1]).st_mode); sys.exit(0 if m == 0o600 else 1)' ~/.config/monsterflow/finding-id-salt`
- This sidesteps `stat` portability AND fails loud if perms regress to 644.
Spec is macOS-only (out-of-scope §) so portability isn't strictly required, but a `stat -f` vs `stat -c` failure mode would look like a test bug — Python is robust on the only platform we ship.

### 4. A11 fresh-install case (e12) — assert *what* exactly?
A11 explicitly excludes the fresh-install case ("precondition: at least one source row exists"). e12 in the table says "Dashboard tab renders empty data area + full '(never run)' roster" — but no test name owns this assertion. Wave 3.2 (Dashboard A5) could cover it as a "no JSONL present" precondition variant. Pin: in Wave 3.2 add an explicit sub-case "render with `dashboard/data/persona-rankings.jsonl` absent + roster.js present → assert empty-state banner text + ≥1 (never run) row + zero data rows." Otherwise e12 is documented but un-tested.

### 5. Dashboard A5 banner assertions — test by CSS class, not copy
A5 + plan Wave 3.2 say "all three banners render." The plan calls them `.gitignored rendered banners (privacy + stale-cache + empty-state per ux's locked copy)`. Whitespace/wording changes will break copy-equality assertions on every UX tweak. Pin Wave 3.2 to:
- Assert `document.querySelector('.banner-privacy')`, `.banner-stale-cache`, `.banner-empty-state` exist under their respective preconditions.
- Optionally one substring assertion per banner (a load-bearing word like `private` / `last refresh` / `No data yet`) — NOT the full sentence.
This survives copy edits without weakening intent coverage.

### 6. Visual color-band thresholds — assert CSS class, not RGB pixels
Plan Wave 2.3 mentions "color bands" for rates. Don't pixel-diff. Pin Wave 3.2 assertions to:
- Each rate `<td>` carries a class like `.band-low` / `.band-mid` / `.band-high` driven by JS thresholds.
- Test asserts the class boundary (e.g. row with ratio 0.79 → `.band-mid`; ratio 0.80 → `.band-high`).
- Cheaper, deterministic, survives theme changes.

### 7. A0 spike-result content sanity (not just file existence)
A0 currently asserts (a) spec heading present, (b) section names `agentId`, (c) fixture exists. The plan's `plan/raw/spike-q1-result.md` (Wave 0.1) contains the actual probe outcome — but no test asserts the file is non-trivial. Add to `tests/test-phase-0-artifact.sh`:
- File `plan/raw/spike-q1-result.md` exists AND `wc -l > 10` AND contains literal tokens `total_tokens` AND `subagents/agent-` AND a verdict line matching `(agreement|disagreement|inconclusive)`.
- Otherwise a 1-line file "TODO" would pass A0.

### 8. A1.5 forcing function — explicit test invocation (Wave 3.5 unclear)
A1.5 says "on disagreement, build fails." Wave 3.5 says "verify no raw print + verify --help + verify validator." It does NOT explicitly verify the A1.5 disagreement path. The agreement path is exercised by A1 against a real fixture. To prove the inverted forcing function works:
- Add a dedicated sub-test (in `tests/test-compute-persona-value.sh` or a new `tests/test-a1-5-forcing.sh`) that uses a tampered fixture where parent `total_tokens` annotation is intentionally wrong (e.g., parent says 1000, subagent sum is 1100). Assert `compute-persona-value.py` exits non-zero AND `--best-effort` downgrades to exit 0 + warning.
- This is the same inverted-assertion class as #1 above — without it, A1.5 only proves "agreement detected when present," not "disagreement caught when present."

### 9. `tests/test-compute-persona-value.sh` scope — too much for one file?
This single test file owns A2 + A3 + A4 + A7 (e1–e12) + A11 + soft-cap + drill-down + `--scan-projects-root` opt-in default. That's reasonable in shape (one engine → one test driver) but failure diagnostics will suffer — if the file fails, `make tests` shows ONE red dot. Recommendation:
- Keep one file BUT structure with sub-test functions (`test_a2_run_state_counts`, `test_a3_cross_project`, `test_a4_hash_reset`, `test_a7_e1`, ... `test_a7_e12`, `test_a11_distinct_pairs`, `test_soft_cap`, `test_scan_default_off`).
- Each function prints `[PASS] test_name` / `[FAIL] test_name <reason>` and accumulates a fail count; final exit reflects accumulated.
- This is a 30-min wave-3 hygiene item; prevents the "one giant red dot" debugging tax.

## Observations (not action items)

- `test-finding-id-salt.sh` (Wave 3.4) is a clean, easy assertion: fixed-input + two salts → two outputs, assert different. Good shape.
- `test-path-validation.sh` (Wave 1.11) covers symlink escape, `..`, non-absolute, sentinel — solid coverage. Verify the test uses real symlinks (not just string paths) since macOS `realpath` resolves them.
- `test-scan-confirmation.sh` (Wave 3.4) — non-tty refusal is testable via `</dev/null` redirect or `script` wrapper. Pin which approach in Wave 3.4 to avoid test-author drift.
- The `run_state` 6-state table in spec §Data is a strong test contract — A2 can mechanically count fixture directories per state and assert `run_state_counts` matches.
- `persona-metrics-validator` subagent (Wave 3.5) is a separate validator — its test surface is "runs cleanly against Wave-1 output, reports zero schema violations." That's a smoke-level assertion; sufficient for v1.
- Idempotency (A8) test contract is excellent — `sort_keys=True` + `round(x, 6)` + explicit diff-stable allowlist + intentionally-volatile field exclusion. Byte-for-byte diff is the gold standard here.
- The plan's "DoD" lines per wave (Wave 0/1/2/3) are themselves checkable gates — useful as a wave-graduation checklist; consider naming them in `/build` execution.

## Verifiability Net

| ID | Test owner | Machine-checkable? | Notes |
|----|------------|--------------------|-------|
| A0 | test-phase-0-artifact.sh | yes | tighten per Should-Fix #7 |
| A1 | test-compute-persona-value.sh | yes | exact equality, clean |
| A1.5 | test-compute-persona-value.sh + (new) forcing-function sub-test | yes | add per Should-Fix #8 |
| A2 | test-compute-persona-value.sh | yes | run_state_counts table is a strong contract |
| A3 | test-compute-persona-value.sh | yes | cross-project fixtures cover cascade |
| A4 | test-compute-persona-value.sh | yes (best-effort scoped) | hash + post-edit IDs cleared |
| A5 | (new) Wave 3.2 DOM test | yes | tighten per Should-Fix #4, #5, #6 |
| A6 | (new) Wave 3.3 text-format test | yes | substring assertions on `/wrap-insights` output |
| A7 | test-compute-persona-value.sh | yes | e1–e12 — split into sub-tests per Should-Fix #9 |
| A8 | test-compute-persona-value.sh (diff sub-test) | yes | byte-for-byte diff |
| A9 | test-allowlist.sh + git check-ignore | yes | clean |
| A10 | test-allowlist.sh + meta-test | yes (with Should-Fix #1) | inverted assertion needs runner contract |
| A11 | test-compute-persona-value.sh + Wave 3.2 e12 sub-case | yes (with Should-Fix #4) | fresh-install path needs explicit owner |

## Bottom Line

Plan is testable end-to-end. The 9 Should-Fix items are tightening that prevents "test author re-derives intent" thrash in Wave 3 — none invalidates the plan. Recommend `/build` after applying #1, #2, #4, #7, #8 inline (those have the highest test-author-confusion blast radius); #3, #5, #6, #9 can be deferred to Wave 3 itself if Wave-3 author is the same person who wrote this spec.
