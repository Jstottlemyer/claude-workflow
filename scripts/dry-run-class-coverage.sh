#!/usr/bin/env bash
##############################################################################
# scripts/dry-run-class-coverage.sh
#
# Pre-merge sanity check for the class-tagging splice (W3 of the
# pipeline-gate-permissiveness work). Scans pipeline-gate persona files and
# reports, per persona, whether the canonical class-tagging block (defined in
# personas/_templates/class-tagging.md) has been spliced in and is byte-
# identical to the template.
#
# Without this check, the first real /check after the W3 batch-splice could hit
# an `unclassified=block` deadlock — a finding emitted by an unspliced persona
# carries no `class:` field, the Judge coerces it to `unclassified`, and the
# unclassified policy axis defaults to block. This script lets us verify
# coverage before merging W3.
#
# Usage:
#   scripts/dry-run-class-coverage.sh [--gate <spec-review|plan|check|all>]
#
# Output:
#   stdout — JSON Lines, one record per scanned persona:
#     {"persona": "review/scope", "status": "PASS"}
#     {"persona": "judge", "status": "NOT_APPLICABLE", "reason": "..."}
#   stderr — final summary (coverage X/Y, NOT_APPLICABLE count, exit code).
#
# Exit codes:
#   0 — every applicable persona has the block AND content matches the template
#   1 — at least one applicable persona is MISSING_BLOCK
#   2 — at least one applicable persona is STALE_BLOCK (clean re-splice needed)
#       Exit 2 takes precedence over exit 1 only if no MISSING_BLOCK exists;
#       MISSING_BLOCK is the more severe failure (exit 1) because no content
#       at all is worse than drifted content. If both are present, exit 1.
#
# NOT_APPLICABLE personas (hardcoded):
#   - judge.md     — uses class-aware section instead of splice block (W2.3)
#   - synthesis.md — uses class-aware section instead of splice block (W2.4)
#
# Bash 3.2 compatible. macOS-friendly. Read-only — never mutates persona files.
##############################################################################
set -uo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PERSONAS_DIR="$ENGINE_DIR/personas"
TEMPLATE="$PERSONAS_DIR/_templates/class-tagging.md"

GATE="all"

# Parse args (simple — only one supported flag).
while [ $# -gt 0 ]; do
  case "$1" in
    --gate)
      shift
      if [ $# -eq 0 ]; then
        echo "ERROR: --gate requires an argument (spec-review|plan|check|all)" >&2
        exit 64
      fi
      GATE="$1"
      ;;
    --help|-h)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      echo "Usage: $0 [--gate <spec-review|plan|check|all>]" >&2
      exit 64
      ;;
  esac
  shift
done

case "$GATE" in
  spec-review|plan|check|all) ;;
  *)
    echo "ERROR: --gate must be one of spec-review|plan|check|all (got: $GATE)" >&2
    exit 64
    ;;
esac

if [ ! -f "$TEMPLATE" ]; then
  echo "ERROR: canonical template missing at $TEMPLATE" >&2
  exit 65
fi

##############################################################################
# Extract content strictly between BEGIN/END sentinels (exclusive).
# Uses POSIX awk. We do NOT trust grep line counting because an embedded
# sentinel inside the body would skew it.
#
# Behavior on malformed input:
#   - No BEGIN sentinel        → empty output, missing=1
#   - BEGIN but no END         → empty output, unterminated=1
#   - Multiple BEGIN sentinels → only the first block is extracted (we report
#                                 truncation via reason field if it happens)
##############################################################################
extract_between_sentinels() {
  # $1 = path
  # Prints lines between (exclusive) the FIRST <!-- BEGIN class-tagging -->
  # and the FIRST subsequent <!-- END class-tagging -->.
  # Sets exit status 0 always; caller checks output emptiness and sentinel
  # presence separately via grep.
  awk '
    BEGIN { in_block = 0; done = 0 }
    /<!-- BEGIN class-tagging -->/ {
      if (done == 0 && in_block == 0) { in_block = 1; next }
    }
    /<!-- END class-tagging -->/ {
      if (in_block == 1) { in_block = 0; done = 1; next }
    }
    in_block == 1 { print }
  ' "$1"
}

##############################################################################
# Determine if a file is in the NOT_APPLICABLE set.
# Hardcoded: judge.md and synthesis.md (top-level personas/ files).
##############################################################################
is_not_applicable() {
  # $1 = absolute path to persona file
  case "$1" in
    "$PERSONAS_DIR/judge.md"|"$PERSONAS_DIR/synthesis.md") return 0 ;;
    *) return 1 ;;
  esac
}

##############################################################################
# Compute the persona key (e.g. "review/scope", "judge") from an absolute path.
##############################################################################
persona_key() {
  # $1 = absolute path
  # strips $PERSONAS_DIR/ prefix and .md suffix
  local p="$1"
  p="${p#$PERSONAS_DIR/}"
  p="${p%.md}"
  printf '%s' "$p"
}

##############################################################################
# Emit a JSONL record. Avoids `printf '%q'` quoting traps.
# $1 = persona key, $2 = status, $3 (optional) = reason
##############################################################################
emit_record() {
  local persona="$1"
  local status="$2"
  local reason="${3:-}"
  if [ -n "$reason" ]; then
    # Escape backslashes and double quotes in reason for JSON safety.
    # Most reasons are static strings we control, but be defensive.
    local esc
    esc="$(printf '%s' "$reason" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
    printf '{"persona": "%s", "status": "%s", "reason": "%s"}\n' \
      "$persona" "$status" "$esc"
  else
    printf '{"persona": "%s", "status": "%s"}\n' "$persona" "$status"
  fi
}

##############################################################################
# Build the file list according to --gate.
##############################################################################
FILES=""

add_glob() {
  # $1 = directory path (must exist; ok if no .md inside)
  local dir="$1"
  if [ ! -d "$dir" ]; then return 0; fi
  local f
  # POSIX glob via for loop (no nullglob in bash 3.2; check existence each).
  for f in "$dir"/*.md; do
    if [ -f "$f" ]; then
      FILES="$FILES
$f"
    fi
  done
}

case "$GATE" in
  spec-review)
    add_glob "$PERSONAS_DIR/review"
    FILES="$FILES
$PERSONAS_DIR/judge.md
$PERSONAS_DIR/synthesis.md"
    ;;
  plan)
    add_glob "$PERSONAS_DIR/plan"
    FILES="$FILES
$PERSONAS_DIR/judge.md
$PERSONAS_DIR/synthesis.md"
    ;;
  check)
    add_glob "$PERSONAS_DIR/check"
    FILES="$FILES
$PERSONAS_DIR/judge.md
$PERSONAS_DIR/synthesis.md"
    ;;
  all)
    add_glob "$PERSONAS_DIR/review"
    add_glob "$PERSONAS_DIR/plan"
    add_glob "$PERSONAS_DIR/check"
    FILES="$FILES
$PERSONAS_DIR/judge.md
$PERSONAS_DIR/synthesis.md"
    ;;
esac

##############################################################################
# Compute template block once.
##############################################################################
TEMPLATE_BLOCK="$(extract_between_sentinels "$TEMPLATE")"

TOTAL_SCANNED=0
APPLICABLE=0
PASS_COUNT=0
MISSING_COUNT=0
STALE_COUNT=0
NA_COUNT=0
MISSING_LIST=""
STALE_LIST=""

# Iterate the file list. We use a here-string-free approach for bash 3.2.
OLD_IFS="$IFS"
IFS='
'
for f in $FILES; do
  IFS="$OLD_IFS"
  if [ -z "$f" ]; then IFS='
'; continue; fi
  if [ ! -f "$f" ]; then IFS='
'; continue; fi

  TOTAL_SCANNED=$(( TOTAL_SCANNED + 1 ))
  key="$(persona_key "$f")"

  if is_not_applicable "$f"; then
    NA_COUNT=$(( NA_COUNT + 1 ))
    emit_record "$key" "NOT_APPLICABLE" "uses class-aware section instead of splice block"
    IFS='
'
    continue
  fi

  APPLICABLE=$(( APPLICABLE + 1 ))

  # Sentinel presence checks (BEGIN must precede END).
  has_begin=0
  has_end=0
  if grep -q "<!-- BEGIN class-tagging -->" "$f"; then has_begin=1; fi
  if grep -q "<!-- END class-tagging -->" "$f"; then has_end=1; fi

  if [ "$has_begin" -eq 0 ]; then
    MISSING_COUNT=$(( MISSING_COUNT + 1 ))
    MISSING_LIST="$MISSING_LIST $key"
    emit_record "$key" "MISSING_BLOCK" "no <!-- BEGIN class-tagging --> sentinel"
    IFS='
'
    continue
  fi
  if [ "$has_end" -eq 0 ]; then
    MISSING_COUNT=$(( MISSING_COUNT + 1 ))
    MISSING_LIST="$MISSING_LIST $key"
    emit_record "$key" "MISSING_BLOCK" "BEGIN sentinel present but END sentinel missing (unterminated block)"
    IFS='
'
    continue
  fi

  # Order check: BEGIN must appear on a lower line number than END.
  begin_line="$(grep -n "<!-- BEGIN class-tagging -->" "$f" | head -n 1 | cut -d: -f1)"
  end_line="$(grep -n "<!-- END class-tagging -->" "$f" | head -n 1 | cut -d: -f1)"
  if [ -n "$begin_line" ] && [ -n "$end_line" ] && [ "$begin_line" -ge "$end_line" ]; then
    MISSING_COUNT=$(( MISSING_COUNT + 1 ))
    MISSING_LIST="$MISSING_LIST $key"
    emit_record "$key" "MISSING_BLOCK" "END sentinel appears before BEGIN sentinel"
    IFS='
'
    continue
  fi

  # Both sentinels present in correct order — compare block content to template.
  persona_block="$(extract_between_sentinels "$f")"
  if [ "$persona_block" = "$TEMPLATE_BLOCK" ]; then
    PASS_COUNT=$(( PASS_COUNT + 1 ))
    emit_record "$key" "PASS"
  else
    STALE_COUNT=$(( STALE_COUNT + 1 ))
    STALE_LIST="$STALE_LIST $key"
    emit_record "$key" "STALE_BLOCK" "block content drifts from canonical template; re-run splice script"
  fi

  IFS='
'
done
IFS="$OLD_IFS"

##############################################################################
# Final summary on stderr.
##############################################################################
total_issues=$(( MISSING_COUNT + STALE_COUNT ))
{
  echo "Coverage: ${PASS_COUNT}/${APPLICABLE} personas have class-tagging block (${total_issues} missing/stale)"
  echo "Run with --gate ${GATE} (${TOTAL_SCANNED} personas scanned, ${NA_COUNT} NOT_APPLICABLE)"
  if [ -n "$MISSING_LIST" ]; then
    echo "MISSING_BLOCK:$MISSING_LIST"
  fi
  if [ -n "$STALE_LIST" ]; then
    echo "STALE_BLOCK:$STALE_LIST (run the splice script to refresh)"
  fi
} >&2

# Exit code precedence: MISSING (1) > STALE (2) > clean (0).
if [ "$MISSING_COUNT" -gt 0 ]; then
  echo "Exit: 1 (MISSING_BLOCK in ${MISSING_COUNT} persona(s))" >&2
  exit 1
fi
if [ "$STALE_COUNT" -gt 0 ]; then
  echo "Exit: 2 (STALE_BLOCK in ${STALE_COUNT} persona(s); clean re-splice needed)" >&2
  exit 2
fi
echo "Exit: 0 (PASS)" >&2
exit 0
