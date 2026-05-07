#!/bin/bash
##############################################################################
# scripts/autorun-rotate-artifacts.sh
#
# Rotate per-run artifacts in queue/<slug>/ to queue/<slug>/runs/<run_id>/
# BEFORE clearing for the next cycle. Preserves narrative state for rebuild.
#
# Usage:
#   bash scripts/autorun-rotate-artifacts.sh <slug> [<run_id>]
#
# If <run_id> is omitted, derives from the latest queue/run.log entry for slug
# (or generates a fresh ISO-8601-style ID if no log entry found).
#
# Quick-fix wrapper from 2026-05-06 dynamic-roster-per-gate session.
# Formal autorun-side rotation tracked in BACKLOG: pipeline-autorun-run-archive.
##############################################################################
set -euo pipefail

SLUG="${1:?usage: autorun-rotate-artifacts.sh <slug> [<run_id>]}"
RUN_ID_ARG="${2:-}"

PROJECT_DIR="${AUTORUN_PROJECT_DIR:-$PWD}"
QUEUE_DIR="$PROJECT_DIR/queue"
SLUG_DIR="$QUEUE_DIR/$SLUG"

if [ ! -d "$SLUG_DIR" ]; then
    echo "[rotate] no queue/$SLUG/ to rotate (already clean) — nothing to do"
    exit 0
fi

# Derive run_id from latest run.log entry if not provided.
if [ -z "$RUN_ID_ARG" ]; then
    if [ -f "$QUEUE_DIR/run.log" ]; then
        RUN_ID_ARG="$(grep "\"slug\":\"$SLUG\"" "$QUEUE_DIR/run.log" \
                       | tail -1 \
                       | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('run_id','unknown'))" \
                       2>/dev/null || echo "unknown")"
    fi
    if [ -z "$RUN_ID_ARG" ] || [ "$RUN_ID_ARG" = "unknown" ]; then
        RUN_ID_ARG="manual-$(date -u +%Y%m%dT%H%M%SZ)"
    fi
fi

ARCHIVE_DIR="$SLUG_DIR/runs/$RUN_ID_ARG"
mkdir -p "$ARCHIVE_DIR"

# Move (not copy) all top-level files from SLUG_DIR into ARCHIVE_DIR.
# Skip the runs/ subdirectory itself (don't recursively move ourselves).
moved=0
for f in "$SLUG_DIR"/*; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    [ "$base" = "runs" ] && continue
    [ -f "$f" ] || continue   # only files; subdirs preserved in-place
    mv "$f" "$ARCHIVE_DIR/$base"
    moved=$((moved + 1))
done

echo "[rotate] queue/$SLUG/ → queue/$SLUG/runs/$RUN_ID_ARG/ ($moved files archived)"
