#!/usr/bin/env bash
# judge-dashboard-bundle.sh — rebuild dashboard/judge-bundle.js from every
# pipeline gate artifact across ~/Projects/*/docs/specs/.
#
# Reads, per feature, per stage (spec-review | plan | check):
#   <stage>/findings.jsonl       — post-Judge clusters (one row per finding)
#   <stage>/participation.jsonl  — per-persona contribution counts
#   <stage>/run.json             — run metadata (timestamp, prompt_version, hash)
#   <stage>/survival.jsonl       — (check-stage only) which prior findings survived
#   <stage>/raw/*.md             — pre-Judge per-agent outputs (counted, not parsed)
#   <stage>.md                   — final synthesized artifact (verdict + disagreements)
#
# Emits: dashboard/judge-bundle.js — script-tag bundle (file:// safe, no fetch).
#
# Called by dashboard-append.sh after every dashboard event so the Judge tab
# stays current alongside graphify data.

set -euo pipefail

WORKFLOW_ROOT="$HOME/Projects/MonsterFlow"
PROJECTS_ROOT="$HOME/Projects"
OUT="$WORKFLOW_ROOT/dashboard/judge-bundle.js"

python3 "$WORKFLOW_ROOT/scripts/judge-dashboard-bundle.py" "$PROJECTS_ROOT" "$OUT"
