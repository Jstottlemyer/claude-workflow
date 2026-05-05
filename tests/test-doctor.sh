#!/usr/bin/env bash
##############################################################################
# tests/test-doctor.sh
#
# Functional tests for scripts/doctor.sh (Task 5.4 of autorun-overnight-policy).
#
# Strategy: doctor.sh's path layout is anchored on $SCRIPT_DIR/..  We build
# a minimal fake-repo tree under a tmpdir, copy doctor.sh into
# tmpdir/scripts/doctor.sh, and run it with a sanitized PATH that contains
# stub `gh` and `crontab` binaries so the tests never actually file an issue
# or read the host crontab.
#
# Bash 3.2 compatible. No ${arr[-1]}. Quoted paths everywhere.
##############################################################################
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCTOR_SH="$REPO_ROOT/scripts/doctor.sh"

if [ ! -f "$DOCTOR_SH" ]; then
  echo "FATAL: $DOCTOR_SH not found"
  exit 2
fi

PASS=0
FAIL=0
FAILED=()

ok()    { PASS=$(( PASS + 1 )); printf "  PASS %s\n" "$1"; }
fail()  { FAIL=$(( FAIL + 1 )); FAILED+=("$1"); printf "  FAIL %s — %s\n" "$1" "$2"; }
case_() { printf "\n--- %s\n" "$1"; }

# ---------------------------------------------------------------------------
# Fixture builder: lay out a fake repo skeleton so doctor.sh runs cleanly.
#
# Args: $1 = root dir to populate
# Optional env: SKIP_CONFIG=1 (omit queue/autorun.config.json),
#               BAD_CONFIG=1  (write malformed JSON),
#               NO_POLICIES=1 (write valid JSON without 'policies' block),
#               NO_BATCH=1    (omit scripts/autorun/autorun-batch.sh)
# ---------------------------------------------------------------------------
mk_fake_repo() {
  local root="$1"
  mkdir -p "$root/scripts/autorun" "$root/queue" "$root/schemas" \
           "$root/commands/_prompts" "$root/tests/fixtures/normalized_signature"

  # VERSION file (read by doctor.sh)
  printf '0.7.0\n' > "$root/VERSION"

  # Copy doctor.sh into the fake repo
  cp "$DOCTOR_SH" "$root/scripts/doctor.sh"
  chmod +x "$root/scripts/doctor.sh"

  # Always-stub a resolve-personas.sh so the resolver self-check doesn't WARN
  cat > "$root/scripts/resolve-personas.sh" <<'STUB'
#!/usr/bin/env bash
# stub for tests
exit 0
STUB
  chmod +x "$root/scripts/resolve-personas.sh"

  # autorun-batch.sh present + executable (unless NO_BATCH=1)
  if [ "${NO_BATCH:-0}" != "1" ]; then
    cat > "$root/scripts/autorun/autorun-batch.sh" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    chmod +x "$root/scripts/autorun/autorun-batch.sh"
  fi

  # queue/autorun.config.json (controlled by env flags)
  if [ "${SKIP_CONFIG:-0}" = "1" ]; then
    : # leave missing
  elif [ "${BAD_CONFIG:-0}" = "1" ]; then
    # truncated / malformed JSON
    printf '{ "webhook_url": "", \n' > "$root/queue/autorun.config.json"
  elif [ "${NO_POLICIES:-0}" = "1" ]; then
    cat > "$root/queue/autorun.config.json" <<'JSON'
{
  "webhook_url": "",
  "mail_to": "",
  "timeout_stage": 1800
}
JSON
  else
    # Healthy default
    cat > "$root/queue/autorun.config.json" <<'JSON'
{
  "webhook_url": "",
  "mail_to": "",
  "timeout_stage": 1800,
  "policies": {
    "verdict": "block",
    "branch":  "block",
    "codex_probe":  "block",
    "verify_infra": "block"
  }
}
JSON
  fi
}

# ---------------------------------------------------------------------------
# Stub-binary builder: drop a fake `gh` and `crontab` (and optionally
# remove `flock` / `timeout`) into a stubdir, then prepend it to PATH.
#
# Args: $1 = stubdir path
# Env:  STUB_FLOCK=skip      (don't shadow flock)
#       STUB_TIMEOUT=skip    (don't shadow timeout)
#       STUB_GTIMEOUT=skip   (don't shadow gtimeout)
# ---------------------------------------------------------------------------
mk_stub_bin() {
  local d="$1"
  mkdir -p "$d"

  # gh stub: print fake auth + always succeed for issue create.
  cat > "$d/gh" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  --version)  echo "gh version 2.0.0 (stub)"; exit 0 ;;
  auth)       exit 0 ;;
  issue)      echo "https://github.com/Jstottlemyer/MonsterFlow/issues/9999"; exit 0 ;;
  *)          exit 0 ;;
esac
STUB
  chmod +x "$d/gh"

  # crontab stub: emit nothing → "no crontab" branch in doctor.sh
  cat > "$d/crontab" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$d/crontab"
}

# Run doctor.sh against a fake-repo tmpdir with a controlled PATH.
# Args: $1 = fake-repo root, $2 = PATH override
# Captures combined stdout+stderr to "$root/out.txt"; returns exit code.
run_doctor() {
  local root="$1"
  local path_override="$2"
  local out="$root/out.txt"
  (
    cd "$root"
    PATH="$path_override" \
      bash "$root/scripts/doctor.sh"
  ) > "$out" 2>&1
  return $?
}

# Compute a "minimal real PATH" that includes stubdir first, then a slim set
# of system locations so basic utilities (python3, awk, grep, find, …) work.
# Optionally include or exclude flock/timeout/gtimeout.
make_path() {
  local stubdir="$1"
  # /usr/bin and /bin are always present on macOS; include /opt/homebrew/bin
  # only when not testing missing-flock / missing-timeout cases.
  local base="/usr/bin:/bin"
  if [ "${INCLUDE_HOMEBREW:-0}" = "1" ]; then
    base="/opt/homebrew/bin:/usr/local/bin:$base"
  fi
  printf '%s:%s' "$stubdir" "$base"
}

# ---------------------------------------------------------------------------
# Test cases
# ---------------------------------------------------------------------------

test_doctor_runs_clean() {
  case_ "test_doctor_runs_clean"
  local tmp; tmp="$(mktemp -d -t "doctor-clean.XXXXXX")"
  mk_fake_repo "$tmp"
  local stub="$tmp/_stub"
  mk_stub_bin "$stub"
  INCLUDE_HOMEBREW=1 \
    run_doctor "$tmp" "$(make_path "$stub")"
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "test_doctor_runs_clean" "doctor exited $rc; tail: $(tail -5 "$tmp/out.txt" | tr '\n' ' ')"
    rm -rf "$tmp"; return
  fi
  # Output must include the section banner that's always mirrored.
  if ! grep -q "Autorun Policy Health" "$tmp/out.txt"; then
    fail "test_doctor_runs_clean" "missing 'Autorun Policy Health' banner in stdout"
    rm -rf "$tmp"; return
  fi
  # Should have filed (stub) issue and printed the URL marker.
  if ! grep -q "Diagnostic filed:" "$tmp/out.txt"; then
    fail "test_doctor_runs_clean" "missing 'Diagnostic filed:' marker"
    rm -rf "$tmp"; return
  fi
  ok "test_doctor_runs_clean"
  rm -rf "$tmp"
}

test_doctor_missing_policies_block() {
  case_ "test_doctor_missing_policies_block"
  local tmp; tmp="$(mktemp -d -t "doctor-nopol.XXXXXX")"
  NO_POLICIES=1 mk_fake_repo "$tmp"
  local stub="$tmp/_stub"
  mk_stub_bin "$stub"
  INCLUDE_HOMEBREW=1 \
    run_doctor "$tmp" "$(make_path "$stub")"
  # WARN about missing policies block
  if ! grep -q "is missing the 'policies' block" "$tmp/out.txt"; then
    fail "test_doctor_missing_policies_block" "no 'missing policies' WARN found"
    rm -rf "$tmp"; return
  fi
  # Lettered 3-fix block (a, b, c options)
  local missing=""
  grep -q "(a) Run: bash scripts/autorun/run.sh" "$tmp/out.txt" || missing="(a)"
  grep -q "(b) Add to crontab: bash scripts/autorun/autorun-batch.sh" "$tmp/out.txt" || missing="$missing (b)"
  grep -q "(c) Edit queue/autorun.config.json" "$tmp/out.txt" || missing="$missing (c)"
  if [ -n "$missing" ]; then
    fail "test_doctor_missing_policies_block" "missing fix options: $missing"
    rm -rf "$tmp"; return
  fi
  ok "test_doctor_missing_policies_block"
  rm -rf "$tmp"
}

test_doctor_invalid_config() {
  case_ "test_doctor_invalid_config"
  local tmp; tmp="$(mktemp -d -t "doctor-bad.XXXXXX")"
  BAD_CONFIG=1 mk_fake_repo "$tmp"
  local stub="$tmp/_stub"
  mk_stub_bin "$stub"
  INCLUDE_HOMEBREW=1 \
    run_doctor "$tmp" "$(make_path "$stub")"
  # Malformed JSON makes the python parse exit non-zero, which doctor.sh
  # treats as "missing 'policies' block" and emits the WARN. That's the
  # observable signal for parse error in v1's surface.
  if ! grep -q "is missing the 'policies' block" "$tmp/out.txt"; then
    fail "test_doctor_invalid_config" "no parse-error WARN surfaced for malformed JSON"
    rm -rf "$tmp"; return
  fi
  ok "test_doctor_invalid_config"
  rm -rf "$tmp"
}

test_doctor_missing_flock() {
  case_ "test_doctor_missing_flock"
  local tmp; tmp="$(mktemp -d -t "doctor-noflock.XXXXXX")"
  mk_fake_repo "$tmp"
  local stub="$tmp/_stub"
  mk_stub_bin "$stub"
  # Stock macOS PATH (no Homebrew) → no flock binary.
  # If host has /usr/local/bin/flock or similar, this test still excludes it
  # because we deliberately omit /opt/homebrew/bin and /usr/local/bin.
  INCLUDE_HOMEBREW=0 \
    run_doctor "$tmp" "$(make_path "$stub")"
  # Confirm flock is genuinely unreachable on the test PATH before asserting.
  # (Skip otherwise — host has flock somewhere in /usr/bin which would be a
  # weird configuration, but better to skip than false-positive.)
  if PATH="$(make_path "$stub")" command -v flock >/dev/null 2>&1; then
    printf "  SKIP test_doctor_missing_flock — flock is in /usr/bin or /bin on this host\n"
    ok "test_doctor_missing_flock (skipped)"
    rm -rf "$tmp"; return
  fi
  if ! grep -q "flock not found" "$tmp/out.txt"; then
    fail "test_doctor_missing_flock" "no 'flock not found' WARN surfaced"
    rm -rf "$tmp"; return
  fi
  if ! grep -q "mkdir-fallback for locking" "$tmp/out.txt"; then
    fail "test_doctor_missing_flock" "no 'mkdir-fallback' explanation surfaced"
    rm -rf "$tmp"; return
  fi
  ok "test_doctor_missing_flock"
  rm -rf "$tmp"
}

test_doctor_missing_timeout() {
  case_ "test_doctor_missing_timeout"
  local tmp; tmp="$(mktemp -d -t "doctor-nott.XXXXXX")"
  mk_fake_repo "$tmp"
  local stub="$tmp/_stub"
  mk_stub_bin "$stub"
  # Stock macOS PATH ships neither timeout nor gtimeout.
  INCLUDE_HOMEBREW=0 \
    run_doctor "$tmp" "$(make_path "$stub")"
  if PATH="$(make_path "$stub")" command -v timeout >/dev/null 2>&1; then
    printf "  SKIP test_doctor_missing_timeout — timeout is in /usr/bin or /bin\n"
    ok "test_doctor_missing_timeout (skipped — timeout in /usr/bin)"
    rm -rf "$tmp"; return
  fi
  if PATH="$(make_path "$stub")" command -v gtimeout >/dev/null 2>&1; then
    printf "  SKIP test_doctor_missing_timeout — gtimeout in /usr/bin or /bin\n"
    ok "test_doctor_missing_timeout (skipped — gtimeout in /usr/bin)"
    rm -rf "$tmp"; return
  fi
  if ! grep -q "neither 'timeout' nor 'gtimeout'" "$tmp/out.txt"; then
    fail "test_doctor_missing_timeout" "no 'neither timeout nor gtimeout' WARN surfaced"
    rm -rf "$tmp"; return
  fi
  if ! grep -q "brew install coreutils" "$tmp/out.txt"; then
    fail "test_doctor_missing_timeout" "no 'brew install coreutils' recommendation"
    rm -rf "$tmp"; return
  fi
  ok "test_doctor_missing_timeout"
  rm -rf "$tmp"
}

test_doctor_autorun_batch_present() {
  case_ "test_doctor_autorun_batch_present"
  local tmp; tmp="$(mktemp -d -t "doctor-batch.XXXXXX")"
  mk_fake_repo "$tmp"
  local stub="$tmp/_stub"
  mk_stub_bin "$stub"
  INCLUDE_HOMEBREW=1 \
    run_doctor "$tmp" "$(make_path "$stub")"
  # Should have ok line and no missing-batch warning.
  if ! grep -q "scripts/autorun/autorun-batch.sh present + executable" "$tmp/out.txt"; then
    fail "test_doctor_autorun_batch_present" "missing 'present + executable' ok line"
    rm -rf "$tmp"; return
  fi
  if grep -q "scripts/autorun/autorun-batch.sh missing" "$tmp/out.txt"; then
    fail "test_doctor_autorun_batch_present" "spurious 'missing' WARN despite batch script being present"
    rm -rf "$tmp"; return
  fi
  ok "test_doctor_autorun_batch_present"
  rm -rf "$tmp"
}

test_doctor_r18_visibility_line() {
  case_ "test_doctor_r18_visibility_line"
  local tmp; tmp="$(mktemp -d -t "doctor-r18.XXXXXX")"
  mk_fake_repo "$tmp"
  local stub="$tmp/_stub"
  mk_stub_bin "$stub"
  INCLUDE_HOMEBREW=1 \
    run_doctor "$tmp" "$(make_path "$stub")"
  if ! grep -q "single-fence-spoof" "$tmp/out.txt"; then
    fail "test_doctor_r18_visibility_line" "missing R18 visibility line containing 'single-fence-spoof'"
    rm -rf "$tmp"; return
  fi
  ok "test_doctor_r18_visibility_line"
  rm -rf "$tmp"
}

# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------
test_doctor_runs_clean
test_doctor_missing_policies_block
test_doctor_invalid_config
test_doctor_missing_flock
test_doctor_missing_timeout
test_doctor_autorun_batch_present
test_doctor_r18_visibility_line

echo ""
echo "=========================================="
echo "test-doctor.sh: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed:"
  for t in "${FAILED[@]}"; do
    echo "  - $t"
  done
  exit 1
fi
exit 0
