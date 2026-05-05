#!/bin/bash
##############################################################################
# scripts/autorun/_policy.sh — Sourced helper API for autorun policy
#
# CONTRACT: docs/specs/autorun-overnight-policy/API_FREEZE.md §(a)
# This file is SOURCED (not executed) by run.sh / check.sh / build.sh /
# verify.sh / spec-review.sh / notify.sh once at startup.
#
# Public functions (frozen signatures):
#   policy_warn  STAGE AXIS REASON   — append to run-state.warnings[]; return 0
#   policy_block STAGE AXIS REASON   — append to run-state.blocks[];   return nonzero (caller exits)
#   policy_for_axis AXIS             — echo "warn"|"block" per resolved policy
#   policy_act AXIS REASON           — convenience: stage from $AUTORUN_CURRENT_STAGE
#   _json_get JSON_POINTER FILE [DEFAULT]
#   _json_escape STRING
#
# Documented call pattern (D37, mandatory at every site):
#   if ! policy_act <axis> "<reason>"; then
#     render_morning_report
#     exit 1
#   fi
#
# Source-time fail-fast: python3 must be present (R14 / SF-T7).
# Bash 3.2 compatible. NO ${arr[-1]}. Quoted expansions everywhere.
##############################################################################

# ---------- Source-time fail-fast (R14) -------------------------------------
command -v python3 >/dev/null 2>&1 || { echo '[policy] python3 required (source-time check)' >&2; exit 2; }

# ---------- Resolve _policy_json.py path -----------------------------------
# Prefer sibling of this sourced file; fall back to repo-relative.
if [ -n "${BASH_SOURCE[0]:-}" ]; then
  _POLICY_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  _POLICY_SH_DIR="$(cd "$(dirname "$0")" && pwd)"
fi
POLICY_JSON_PY="${POLICY_JSON_PY:-$_POLICY_SH_DIR/_policy_json.py}"

# ---------- Locking primitive selection (spike finding 1) ------------------
# File-form flock ONLY (fd-form is broken on macOS). mkdir-fallback if absent.
if command -v flock >/dev/null 2>&1; then
  POLICY_LOCK_KIND=flock
else
  POLICY_LOCK_KIND=mkdir
fi

# ---------- Enums (AC#26 + AXIS contract) ----------------------------------
# Bash 3.2: use space-separated strings + word-match instead of associative arrays.
_POLICY_STAGE_ENUM="spec-review plan check verify build branch-setup codex-review pr-creation merging complete pr"
_POLICY_AXIS_ENUM="verdict branch codex_probe verify_infra integrity security"

_policy_in_set() {
  # Returns 0 if "$1" appears as whitespace-delimited word in "$2".
  local needle="$1" haystack="$2"
  case " $haystack " in
    *" $needle "*) return 0 ;;
    *) return 1 ;;
  esac
}

_policy_validate_stage() {
  local stage="$1"
  if ! _policy_in_set "$stage" "$_POLICY_STAGE_ENUM"; then
    echo "[policy] error: invalid stage: $stage" >&2
    exit 2
  fi
}

_policy_validate_axis() {
  local axis="$1"
  if ! _policy_in_set "$axis" "$_POLICY_AXIS_ENUM"; then
    echo "[policy] error: invalid axis: $axis" >&2
    exit 2
  fi
}

# ---------- STATE_FILE resolution ------------------------------------------
_policy_state_file() {
  if [ -n "${AUTORUN_RUN_STATE:-}" ]; then
    printf "%s" "$AUTORUN_RUN_STATE"
  else
    printf "%s" "queue/runs/current/run-state.json"
  fi
}

# ---------- Atomic-append under lock ---------------------------------------
# _policy_locked_append <state_file> <subcommand> <stage> <axis> <reason>
# subcommand is "append-warning" or "append-block".
_policy_locked_append() {
  local state_file="$1" sub="$2" stage="$3" axis="$4" reason="$5"
  local lockfile="${state_file}.lock"

  # Allow tests to override the lock kind via env (PATH-stub / forced fallback).
  local kind="${POLICY_LOCK_KIND_OVERRIDE:-$POLICY_LOCK_KIND}"

  if [ "$kind" = "flock" ] && command -v flock >/dev/null 2>&1; then
    # File-form flock per spike finding 1 (probe 13 atomic-append torture).
    # Blocking acquire (-x, no -n): we WANT to serialize concurrent writers,
    # not fail-fast. Use env-vars to pass values into -c subshell to keep
    # quoting sane (avoid embedded reason chars breaking -c).
    POLICY_PY="$POLICY_JSON_PY" \
    POLICY_FILE="$state_file" \
    POLICY_SUB="$sub" \
    POLICY_STAGE="$stage" \
    POLICY_AXIS="$axis" \
    POLICY_REASON="$reason" \
    flock -x "$lockfile" -c \
      'python3 "$POLICY_PY" "$POLICY_SUB" "$POLICY_FILE" "$POLICY_STAGE" "$POLICY_AXIS" "$POLICY_REASON"'
    return $?
  fi

  # mkdir-fallback (atomic on POSIX). Retry-with-backoff loop.
  local lockdir="${state_file}.lockdir"
  local tries=0
  local max_tries=600
  while ! mkdir "$lockdir" 2>/dev/null; do
    tries=$(( tries + 1 ))
    if [ "$tries" -ge "$max_tries" ]; then
      echo "[policy] error: could not acquire lock after $max_tries tries: $lockdir" >&2
      return 1
    fi
    # Backoff: ~50ms; 600 tries → ~30s ceiling.
    sleep 0.05 2>/dev/null || sleep 1
  done
  # Cleanup on any exit from this function scope. Use a subshell trap so we
  # don't clobber callers' EXIT trap.
  local rc=0
  (
    trap 'rmdir "$lockdir" 2>/dev/null || true' EXIT
    python3 "$POLICY_JSON_PY" "$sub" "$state_file" "$stage" "$axis" "$reason"
  )
  rc=$?
  rmdir "$lockdir" 2>/dev/null || true
  return $rc
}

# ---------- _json_escape STRING --------------------------------------------
_json_escape() {
  if [ "$#" -lt 1 ]; then
    echo "[policy] error: _json_escape requires 1 argument" >&2
    exit 2
  fi
  python3 "$POLICY_JSON_PY" escape "$1"
}

# ---------- _json_get JSON_POINTER FILE [DEFAULT] --------------------------
# Note: pointer first per API_FREEZE.md §(a) and spec line 327.
_json_get() {
  if [ "$#" -lt 2 ]; then
    echo "[policy] error: _json_get requires JSON_POINTER FILE [DEFAULT]" >&2
    exit 2
  fi
  local pointer="$1" file="$2"
  if [ "$#" -ge 3 ]; then
    python3 "$POLICY_JSON_PY" get "$file" "$pointer" --default "$3"
  else
    python3 "$POLICY_JSON_PY" get "$file" "$pointer"
  fi
}

# ---------- policy_warn STAGE AXIS REASON ----------------------------------
policy_warn() {
  if [ "$#" -ne 3 ]; then
    echo "[policy] error: policy_warn requires STAGE AXIS REASON" >&2
    exit 2
  fi
  local stage="$1" axis="$2" reason="$3"
  _policy_validate_stage "$stage"
  _policy_validate_axis "$axis"
  if [ -z "$reason" ]; then
    echo "[policy] error: policy_warn REASON must be non-empty" >&2
    exit 2
  fi
  local state_file
  state_file="$(_policy_state_file)"
  echo "[policy] warn: stage=$stage axis=$axis reason=\"$reason\"" >&2
  _policy_locked_append "$state_file" append-warning "$stage" "$axis" "$reason" || return 0
  return 0
}

# ---------- policy_block STAGE AXIS REASON ---------------------------------
# Returns NONZERO so caller can branch via `if !`. Does NOT exit.
policy_block() {
  if [ "$#" -ne 3 ]; then
    echo "[policy] error: policy_block requires STAGE AXIS REASON" >&2
    exit 2
  fi
  local stage="$1" axis="$2" reason="$3"
  _policy_validate_stage "$stage"
  _policy_validate_axis "$axis"
  if [ -z "$reason" ]; then
    echo "[policy] error: policy_block REASON must be non-empty" >&2
    exit 2
  fi
  local state_file
  state_file="$(_policy_state_file)"
  echo "[policy] block: stage=$stage axis=$axis reason=\"$reason\"" >&2
  _policy_locked_append "$state_file" append-block "$stage" "$axis" "$reason" || true
  return 1
}

# ---------- policy_for_axis AXIS -------------------------------------------
# Precedence: env (AUTORUN_<AXIS>_POLICY) > config (queue/autorun.config.json
# ::policies.<axis>) > hardcoded "block".
# `integrity` and `security` are ALWAYS hardcoded "block".
policy_for_axis() {
  if [ "$#" -ne 1 ]; then
    echo "[policy] error: policy_for_axis requires AXIS" >&2
    exit 2
  fi
  local axis="$1"
  _policy_validate_axis "$axis"

  # Hardcoded: integrity + security cannot be relaxed.
  case "$axis" in
    integrity|security)
      printf "block\n"
      return 0
      ;;
  esac

  # Env override. Uppercase axis name → AUTORUN_<UPPER>_POLICY.
  # Bash 3.2: tr is portable.
  local upper
  upper="$(printf "%s" "$axis" | tr 'a-z' 'A-Z')"
  local env_var="AUTORUN_${upper}_POLICY"
  # Bash 3.2 has indirect expansion via ${!var}.
  local env_val="${!env_var:-}"
  if [ -n "$env_val" ]; then
    case "$env_val" in
      warn|block) printf "%s\n" "$env_val"; return 0 ;;
    esac
  fi

  # Config lookup. Allow override via $AUTORUN_CONFIG_FILE for tests.
  local config_file="${AUTORUN_CONFIG_FILE:-queue/autorun.config.json}"
  if [ -f "$config_file" ]; then
    local cfg_val
    cfg_val="$(python3 "$POLICY_JSON_PY" get "$config_file" "/policies/$axis" --default "" 2>/dev/null || true)"
    case "$cfg_val" in
      warn|block) printf "%s\n" "$cfg_val"; return 0 ;;
    esac
  fi

  # Hardcoded fallback.
  printf "block\n"
  return 0
}

# ---------- policy_act AXIS REASON -----------------------------------------
# Stage from $AUTORUN_CURRENT_STAGE (exported by run.sh update_stage()).
policy_act() {
  if [ "$#" -ne 2 ]; then
    echo "[policy] error: policy_act requires AXIS REASON" >&2
    exit 2
  fi
  if [ -z "${AUTORUN_CURRENT_STAGE:-}" ]; then
    echo "[policy] error: AUTORUN_CURRENT_STAGE not set" >&2
    exit 2
  fi
  local axis="$1" reason="$2"
  local stage="$AUTORUN_CURRENT_STAGE"
  local mode
  mode="$(policy_for_axis "$axis")"
  case "$mode" in
    warn)
      policy_warn "$stage" "$axis" "$reason"
      return 0
      ;;
    block)
      # Returns nonzero. Caller guards with `if ! policy_act ...`.
      policy_block "$stage" "$axis" "$reason"
      return 1
      ;;
    *)
      echo "[policy] error: policy_for_axis returned unexpected value: $mode" >&2
      exit 2
      ;;
  esac
}
