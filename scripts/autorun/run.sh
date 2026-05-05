#!/bin/bash
##############################################################################
# scripts/autorun/run.sh
#
# Main orchestrator for the autonomous overnight pipeline.
# Invoked via:
#   flock -n "$PROJECT_DIR/queue/.autorun.lock" bash "$ENGINE_DIR/scripts/autorun/run.sh"
#
# Processes every queue/*.spec.md file in order, running the full pipeline:
#   spec-review → risk-analysis → plan → check → build → pr-creation → codex-review → merge
##############################################################################
set -euo pipefail

ENGINE_DIR="${ENGINE_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
PROJECT_DIR="${PROJECT_DIR:-$PWD}"
source "$ENGINE_DIR/scripts/autorun/defaults.sh"

QUEUE_DIR="$PROJECT_DIR/queue"
CONFIG_FILE="$QUEUE_DIR/autorun.config.json"
AUTORUN=1
AUTORUN_VERSION="$(tr -d '[:space:]' < "$ENGINE_DIR/VERSION" 2>/dev/null || echo 'unknown')"
export QUEUE_DIR CONFIG_FILE AUTORUN AUTORUN_VERSION ENGINE_DIR PROJECT_DIR

# ---------------------------------------------------------------------------
# DRY RUN notice (stage scripts handle their own stubs; run.sh just logs it)
# ---------------------------------------------------------------------------
if [ "${AUTORUN_DRY_RUN:-0}" = "1" ]; then
    echo "[autorun] DRY RUN mode — stage scripts will stub their outputs"
fi

# ---------------------------------------------------------------------------
# Helper: write_state
# Write state.json atomically to ARTIFACT_DIR.
# Requires SLUG, ARTIFACT_DIR, ITEM_STARTED_AT to be set in calling scope.
# ---------------------------------------------------------------------------
write_state() {
    local stage="$1"
    local tmp
    tmp="$(mktemp "$ARTIFACT_DIR/state.XXXXXX.json")"
    cat > "$tmp" <<STATE
{"stage": "$stage", "started_at": "$ITEM_STARTED_AT", "pid": $$}
STATE
    mv "$tmp" "$ARTIFACT_DIR/state.json"
}

# ---------------------------------------------------------------------------
# Helper: log_run
# Append a JSON line to queue/run.log.
# ---------------------------------------------------------------------------
log_run() {
    local slug="$1" stage="$2" exit_code="$3"
    echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"slug\":\"$slug\",\"stage\":\"$stage\",\"exit_code\":$exit_code}" \
        >> "$QUEUE_DIR/run.log"
}

# ---------------------------------------------------------------------------
# Helper: update_stage
# Write queue/.current-stage (human-readable) and log as in-progress.
# Requires SLUG to be set in calling scope.
# ---------------------------------------------------------------------------
update_stage() {
    echo "$SLUG: $1" > "$QUEUE_DIR/.current-stage"
    log_run "$SLUG" "$1" 0  # status 0 = in-progress
}

# ---------------------------------------------------------------------------
# Helper: write_failure_item
# Write failure.md to ARTIFACT_DIR if not already present.
# Requires SLUG, ARTIFACT_DIR to be set in calling scope.
# ---------------------------------------------------------------------------
write_failure_item() {
    local stage="$1" reason="$2"
    [ -f "$ARTIFACT_DIR/failure.md" ] && return 0  # already written by stage script
    cat > "$ARTIFACT_DIR/failure.md" <<FAIL_EOF
<!-- autorun:stage=$stage slug=$SLUG -->
# Failure: $SLUG

**Stage:** $stage
**Reason:** $reason
**Timestamp:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Re-queue
\`rm $ARTIFACT_DIR/failure.md && cp docs/specs/$SLUG/spec.md $QUEUE_DIR/$SLUG.spec.md\`
FAIL_EOF
}

# ---------------------------------------------------------------------------
# Helper: detect_orphan
# Check for a stale or live run from a previous invocation.
# Returns 0 = safe to proceed, 1 = live process found (skip item).
# Requires SLUG, ARTIFACT_DIR, PROJECT_DIR to be set in calling scope.
# ---------------------------------------------------------------------------
detect_orphan() {
    if [ ! -f "$ARTIFACT_DIR/state.json" ]; then return 0; fi

    local prev_pid
    prev_pid="$(python3 -c "import json; d=json.load(open('$ARTIFACT_DIR/state.json')); print(d.get('pid',''))" 2>/dev/null || echo "")"

    if [ -z "$prev_pid" ]; then return 0; fi

    # Check if the PID is still alive
    if kill -0 "$prev_pid" 2>/dev/null; then
        echo "[autorun] $SLUG: live process found (pid=$prev_pid) — skipping (already running)"
        return 1  # signal to skip this item
    fi

    # Stale PID — orphan state
    echo "[autorun] $SLUG: orphaned run detected (stale pid=$prev_pid) — cleaning up"

    # Delete stale remote branch before Stage 1 re-entry
    git -C "$PROJECT_DIR" push origin --delete "autorun/$SLUG" 2>/dev/null \
        && echo "[autorun] $SLUG: deleted stale remote branch autorun/$SLUG" \
        || true

    # Reset local state
    rm -f "$ARTIFACT_DIR/state.json"
    return 0  # safe to proceed
}

# ---------------------------------------------------------------------------
# run_item: execute the full pipeline for a single queue item
#
# Exit codes:
#   0 — item complete or skipped cleanly
#   3 — clean halt requested via STOP file (bubble up to main loop)
# ---------------------------------------------------------------------------
run_item() {
    local SLUG="$1"
    local SPEC_FILE="$QUEUE_DIR/${SLUG}.spec.md"
    local ARTIFACT_DIR="$QUEUE_DIR/$SLUG"

    export SLUG SPEC_FILE ARTIFACT_DIR

    mkdir -p "$ARTIFACT_DIR"
    ITEM_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # -- Skip if already complete ----------------------------------------------
    if [ -f "$ARTIFACT_DIR/run-summary.md" ]; then
        echo "[autorun] $SLUG: already complete (run-summary.md present) — skipping"
        return 0
    fi

    # -- Skip if failure.md present (no --retry mode in v1) -------------------
    if [ -f "$ARTIFACT_DIR/failure.md" ]; then
        echo "[autorun] $SLUG: failure.md present — skipping (remove to retry)"
        return 0
    fi

    # -- Orphan detection ------------------------------------------------------
    detect_orphan || return 0  # return 0 = skip, not an error

    echo "[autorun] starting: $SLUG"
    write_state "starting"

    # -------------------------------------------------------------------------
    # Stage 1: spec-review
    # -------------------------------------------------------------------------
    if [ -f "$ARTIFACT_DIR/review-findings.md" ]; then
        echo "[autorun] $SLUG: review-findings.md present — resuming past spec-review"
    else
        update_stage "spec-review"
        write_state "spec-review"

        local STAGE_EXIT=0
        bash "$ENGINE_DIR/scripts/autorun/spec-review.sh" || STAGE_EXIT=$?
        log_run "$SLUG" "spec-review" "$STAGE_EXIT"

        if [ "$STAGE_EXIT" -eq 2 ]; then
            echo "[autorun] $SLUG: spec-review threshold exceeded — skipping to next item"
            write_failure_item "spec-review" "threshold exceeded"
            return 0
        elif [ "$STAGE_EXIT" -ne 0 ]; then
            echo "[autorun] $SLUG: spec-review failed (exit $STAGE_EXIT)"
            write_failure_item "spec-review" "exit $STAGE_EXIT"
            return 0
        fi

        # spec-review.sh can exit 0 without producing review-findings.md when
        # neither review.md nor raw persona files are written. Treat that as
        # failure — otherwise risk-analysis appends to a never-created file
        # and planning proceeds without spec-review evidence.
        if [ ! -f "$ARTIFACT_DIR/review-findings.md" ]; then
            echo "[autorun] $SLUG: spec-review exited 0 but review-findings.md missing — treating as failure"
            write_failure_item "spec-review" "review-findings.md not produced"
            return 0
        fi
    fi

    # -------------------------------------------------------------------------
    # Stage 1b: risk-analysis (non-fatal)
    # -------------------------------------------------------------------------
    if [ -f "$ARTIFACT_DIR/risk-findings.md" ]; then
        echo "[autorun] $SLUG: risk-findings.md present — resuming past risk-analysis"
    else
        update_stage "risk-analysis"
        write_state "risk-analysis"

        STAGE_EXIT=0
        bash "$ENGINE_DIR/scripts/autorun/risk-analysis.sh" || STAGE_EXIT=$?
        log_run "$SLUG" "risk-analysis" "$STAGE_EXIT"

        if [ "$STAGE_EXIT" -ne 0 ]; then
            echo "[autorun] $SLUG: risk-analysis failed (exit $STAGE_EXIT) — continuing without risk findings"
            # Non-fatal: create empty risk-findings.md so plan.sh can proceed
            printf '# Risk Analysis\n(risk-analysis failed — skipped)\n' > "$ARTIFACT_DIR/risk-findings.md" || true
        fi

        # Merge risk-findings into review-findings (for plan.sh)
        if [ -f "$ARTIFACT_DIR/risk-findings.md" ]; then
            {
                echo ""
                echo "---"
                echo "## Risk Analysis"
                echo ""
                cat "$ARTIFACT_DIR/risk-findings.md"
            } >> "$ARTIFACT_DIR/review-findings.md"
            echo "[autorun] $SLUG: merged risk-findings.md into review-findings.md"
        fi
    fi

    # -------------------------------------------------------------------------
    # Stage 2: plan
    # -------------------------------------------------------------------------
    if [ -f "$ARTIFACT_DIR/plan.md" ]; then
        echo "[autorun] $SLUG: plan.md present — resuming past plan (manual edits preserved)"
    else
        update_stage "plan"
        write_state "plan"

        STAGE_EXIT=0
        bash "$ENGINE_DIR/scripts/autorun/plan.sh" || STAGE_EXIT=$?
        log_run "$SLUG" "plan" "$STAGE_EXIT"

        if [ "$STAGE_EXIT" -ne 0 ]; then
            echo "[autorun] $SLUG: plan failed (exit $STAGE_EXIT)"
            write_failure_item "plan" "exit $STAGE_EXIT"
            return 0
        fi
    fi

    # -------------------------------------------------------------------------
    # Stage 3: check (gate — exit 2 = NO-GO)
    # Skip only when check.md exists AND verdict is GO (no NO-GO in content).
    # A NO-GO check.md means the plan was fixed and check must re-run.
    # -------------------------------------------------------------------------
    if [ -f "$ARTIFACT_DIR/check.md" ] && ! grep -qi "NO-GO\|NO GO" "$ARTIFACT_DIR/check.md" 2>/dev/null; then
        echo "[autorun] $SLUG: check.md present with GO verdict — resuming past check"
    else
        update_stage "check"
        write_state "check"

        STAGE_EXIT=0
        bash "$ENGINE_DIR/scripts/autorun/check.sh" || STAGE_EXIT=$?
        log_run "$SLUG" "check" "$STAGE_EXIT"

        if [ "$STAGE_EXIT" -eq 2 ]; then
            echo "[autorun] $SLUG: check returned NO-GO — skipping build"
            write_failure_item "check" "NO-GO verdict"
            return 0
        elif [ "$STAGE_EXIT" -ne 0 ]; then
            echo "[autorun] $SLUG: check failed (exit $STAGE_EXIT)"
            write_failure_item "check" "exit $STAGE_EXIT"
            return 0
        fi
    fi

    # --- Branch setup + build (skipped together if build-log exists) ---
    if [ -f "$ARTIFACT_DIR/build-log.md" ]; then
        echo "[autorun] $SLUG: build-log.md present — resuming past build"
        PRE_BUILD_SHA="$(cat "$ARTIFACT_DIR/pre-build-sha.txt" 2>/dev/null || echo "unknown")"
        WAVE_COUNT="$(grep -c "^## Wave" "$ARTIFACT_DIR/build-log.md" 2>/dev/null || echo "unknown")"
    else
        # --- Branch setup (before build) ---
        # Create or reset the autorun branch for this item
        update_stage "branch-setup"
        BRANCH_NAME="autorun/$SLUG"
        git -C "$PROJECT_DIR" fetch origin main 2>/dev/null \
          && BASE_REF="origin/main" \
          || { echo "[autorun] $SLUG: WARN — could not fetch origin/main — using local main"; BASE_REF="main"; }
        if git -C "$PROJECT_DIR" rev-parse --verify "$BRANCH_NAME" >/dev/null 2>&1; then
            # Branch exists — reset to upstream main to start fresh
            git -C "$PROJECT_DIR" checkout "$BRANCH_NAME"
            git -C "$PROJECT_DIR" reset --hard "$BASE_REF"
            echo "[autorun] $SLUG: reset existing branch $BRANCH_NAME to $BASE_REF"
        else
            git -C "$PROJECT_DIR" checkout -b "$BRANCH_NAME" "$BASE_REF"
            echo "[autorun] $SLUG: created branch $BRANCH_NAME from $BASE_REF"
        fi

        # -------------------------------------------------------------------------
        # Stage 4: build
        # -------------------------------------------------------------------------
        update_stage "build"
        write_state "build"

        STAGE_EXIT=0
        bash "$ENGINE_DIR/scripts/autorun/build.sh" || STAGE_EXIT=$?
        log_run "$SLUG" "build" "$STAGE_EXIT"

        if [ "$STAGE_EXIT" -eq 3 ]; then
            # STOP file: clean halt — bubble up to the main loop
            echo "[autorun] $SLUG: build requested clean halt (STOP file)"
            return 3
        elif [ "$STAGE_EXIT" -ne 0 ]; then
            # failure.md already written by build.sh
            echo "[autorun] $SLUG: build failed (exit $STAGE_EXIT)"
            return 0
        fi
    fi

    # --- Stage 5: Create PR ---
    # Re-check STOP before PR creation as a safety net (build.sh also re-checks
    # after a successful wave, but a STOP racing with branch push should still halt).
    if [ -f "$QUEUE_DIR/STOP" ]; then
        echo "[autorun] $SLUG: STOP file detected before PR creation — halting"
        return 3
    fi

    if [ -f "$ARTIFACT_DIR/pr-url.txt" ]; then
        echo "[autorun] $SLUG: pr-url.txt present — resuming past PR creation"
        PRE_BUILD_SHA="$(cat "$ARTIFACT_DIR/pre-build-sha.txt" 2>/dev/null || echo "unknown")"
        WAVE_COUNT="$(grep -c "^## Wave" "$ARTIFACT_DIR/build-log.md" 2>/dev/null || echo "unknown")"
    else
        update_stage "pr-creation"
        write_state "pr-creation"

    # Push branch to remote before creating PR (gh pr create requires the branch to exist remotely)
    PUSH_EXIT=0
    git -C "$PROJECT_DIR" push origin "autorun/$SLUG" 2>/dev/null || PUSH_EXIT=$?
    if [ "$PUSH_EXIT" -ne 0 ]; then
        echo "[autorun] $SLUG: WARN — failed to push branch autorun/$SLUG (exit $PUSH_EXIT)"
    else
        echo "[autorun] $SLUG: pushed branch autorun/$SLUG to origin"
    fi

    PRE_BUILD_SHA="$(cat "$ARTIFACT_DIR/pre-build-sha.txt" 2>/dev/null || echo "unknown")"
    WAVE_COUNT="$(grep -c "^## Wave" "$ARTIFACT_DIR/build-log.md" 2>/dev/null || echo "unknown")"
    TEST_CMD_DISPLAY="${TEST_CMD:-(empty — skipped)}"

    # Resolve owner/repo for --repo. `gh repo view` handles both HTTPS and SSH
    # remotes; fall back to regex-stripping for both URL forms if gh is unavailable.
    PR_REPO="$(cd "$PROJECT_DIR" && gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null \
        || git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null \
           | sed -E 's|^git@github\.com:([^/]+/[^/]+)\.git$|\1|; s|^https://github\.com/([^/]+/[^/]+)\.git$|\1|; s|^https://github\.com/([^/]+/[^/]+)$|\1|')"

    STAGE_EXIT=0
    PR_URL="$(gh pr create \
        --repo "$PR_REPO" \
        --title "autorun: $SLUG" \
        --body "$(cat <<PRBODY
## Summary
Automated implementation of \`$SLUG\` via autorun pipeline.

## Autorun Provenance
- **Slug:** $SLUG
- **Spec:** docs/specs/$SLUG/spec.md
- **Pre-build SHA:** $PRE_BUILD_SHA
- **Autorun version:** $AUTORUN_VERSION
- **Wave count:** $WAVE_COUNT
- **Test cmd:** $TEST_CMD_DISPLAY
- **Timestamp (UTC):** $(date -u +%Y-%m-%dT%H:%M:%SZ)
- **Artifacts:** queue/$SLUG/{review-findings,plan,check,build-log}.md
PRBODY
)" \
        --base main \
        --head "autorun/$SLUG" \
        2>&1)" || STAGE_EXIT=$?

    if [ "$STAGE_EXIT" -eq 0 ] && [ -n "$PR_URL" ]; then
        echo "$PR_URL" > "$ARTIFACT_DIR/pr-url.txt"
        echo "[autorun] $SLUG: PR created: $PR_URL"
        log_run "$SLUG" "pr-creation" 0
    else
        echo "[autorun] $SLUG: PR creation failed (exit $STAGE_EXIT): $PR_URL"
        log_run "$SLUG" "pr-creation" 1
        # Without a PR URL, neither Codex review nor merge can run. Mark the item
        # failed so it doesn't sit in limbo (no failure.md, no run-summary.md)
        # forever — the next run would otherwise re-process it indefinitely.
        write_failure_item "pr-creation" "PR creation failed (exit $STAGE_EXIT)"
        return 0
    fi
    fi  # end pr-url.txt skip block

    # --- Stage 6: Codex review (if available) ---
    CODEX_OUTPUT_FILE="$ARTIFACT_DIR/codex-review.md"  # persisted so resume can skip
    CODEX_AVAILABLE=0
    CODEX_HIGH_COUNT=0

    if [ -f "$CODEX_OUTPUT_FILE" ]; then
        echo "[autorun] $SLUG: codex-review.md present — resuming past Codex review"
        CODEX_AVAILABLE=1
        CODEX_HIGH_COUNT="$(grep -c '^\*\*High:\*\*' "$CODEX_OUTPUT_FILE" 2>/dev/null || true)"
        CODEX_HIGH_COUNT="${CODEX_HIGH_COUNT:-0}"
    elif command -v codex >/dev/null 2>&1; then
        update_stage "codex-review"
        write_state "codex-review"

        echo "[autorun] $SLUG: running Codex review (timeout=${TIMEOUT_CODEX}s)"

        CODEX_EXIT=0
        CODEX_CONTEXT="$(mktemp "${TMPDIR:-/tmp}/autorun-codex-ctx-XXXXXX.md")"
        {
          printf '## Git Diff (committed changes since pre-build SHA)\n'
          [ "$PRE_BUILD_SHA" != "unknown" ] && \
            git -C "$PROJECT_DIR" diff "$PRE_BUILD_SHA" HEAD -- . 2>/dev/null | head -2000 || \
            printf '(diff unavailable)\n'
          printf '\n## Build Log (last 100 lines)\n'
          tail -100 "$ARTIFACT_DIR/build-log.md" 2>/dev/null || true
        } > "$CODEX_CONTEXT"
        timeout "$TIMEOUT_CODEX" codex exec \
            --full-auto --ephemeral \
            --output-last-message "$CODEX_OUTPUT_FILE" \
            "Review this PR implementation for correctness, security issues, and adherence to the spec. Look for: blocking bugs, security vulnerabilities, and significant deviations from the plan. For each finding, start the line with either **High:** (blocking), **Medium:** (non-blocking), or **Low:** (informational)." \
            < "$CODEX_CONTEXT" \
            2>/dev/null || CODEX_EXIT=$?
        rm -f "$CODEX_CONTEXT"

        if [ "$CODEX_EXIT" -eq 0 ] && [ -f "$CODEX_OUTPUT_FILE" ]; then
            CODEX_AVAILABLE=1
            echo "[autorun] $SLUG: Codex review complete"
            log_run "$SLUG" "codex-review" 0

            # Count **High:** findings (blocking)
            CODEX_HIGH_COUNT="$(grep -c '^\*\*High:\*\*' "$CODEX_OUTPUT_FILE" 2>/dev/null || true)"
            CODEX_HIGH_COUNT="${CODEX_HIGH_COUNT:-0}"
            CODEX_MEDIUM_LOW="$(grep -E '^\*\*(Medium|Low):\*\*' "$CODEX_OUTPUT_FILE" 2>/dev/null | wc -l | tr -d ' ')"

            echo "[autorun] $SLUG: Codex findings — High: $CODEX_HIGH_COUNT, Medium+Low: $CODEX_MEDIUM_LOW"

            # Post non-blocking findings as a PR comment
            if [ "$CODEX_MEDIUM_LOW" -gt 0 ] && [ -f "$ARTIFACT_DIR/pr-url.txt" ]; then
                PR_URL_VALUE="$(cat "$ARTIFACT_DIR/pr-url.txt")"
                gh pr comment "$PR_URL_VALUE" \
                    --body "## Autorun: Codex Review (Non-blocking Findings)
$(grep -E '^\*\*(Medium|Low):\*\*' "$CODEX_OUTPUT_FILE" 2>/dev/null)

_These findings are non-blocking. The pipeline will proceed to merge._" \
                    2>/dev/null || true
            fi
        else
            echo "[autorun] $SLUG: Codex review skipped or timed out (exit $CODEX_EXIT) — posting warning to PR"
            log_run "$SLUG" "codex-review" "$CODEX_EXIT"

            if [ -f "$ARTIFACT_DIR/pr-url.txt" ]; then
                gh pr comment "$(cat "$ARTIFACT_DIR/pr-url.txt")" \
                    --body "## Autorun: Codex Review Skipped
Codex review timed out or was unavailable (exit $CODEX_EXIT). Manual review recommended before merge." \
                    2>/dev/null || true
            fi
        fi
    else
        echo "[autorun] $SLUG: codex not installed — skipping review"
        log_run "$SLUG" "codex-review" -1
    fi

    # --- Fix-attempt mechanics (Design Decision #12) ---
    FIX_ATTEMPTED=0

    if [ "$CODEX_HIGH_COUNT" -gt 0 ] && [ "$FIX_ATTEMPTED" -eq 0 ]; then
        FIX_ATTEMPTED=1
        echo "[autorun] $SLUG: $CODEX_HIGH_COUNT High-severity finding(s) — attempting one fix"
        update_stage "fix-attempt"
        write_state "fix-attempt"

        FIX_PROMPT="You are running in fully autonomous overnight mode. Fix the following issues in the codebase. Context from the build log and Codex findings are provided. Produce exactly one commit with the fix. Do not ask for approval.

## Build Context
$(cat "$ARTIFACT_DIR/build-log.md" | tail -200)

## Codex High-Severity Findings
$(grep '^\*\*High:\*\*' "$CODEX_OUTPUT_FILE" 2>/dev/null)"

        SHA_BEFORE_FIX="$(git -C "$PROJECT_DIR" rev-parse HEAD)"

        FIX_EXIT=0
        printf '%s' "$FIX_PROMPT" | timeout "$TIMEOUT_STAGE" claude -p \
            --dangerously-skip-permissions \
            --system-prompt "You are running in fully autonomous overnight mode. Fix the failing issues. Commit your fix. Do not ask for approval." \
            --add-dir "$PROJECT_DIR" \
            2>/dev/null || FIX_EXIT=$?

        SHA_AFTER_FIX="$(git -C "$PROJECT_DIR" rev-parse HEAD)"

        # Verify a new commit was produced
        if [ "$FIX_EXIT" -ne 0 ] || [ "$SHA_BEFORE_FIX" = "$SHA_AFTER_FIX" ]; then
            echo "[autorun] $SLUG: fix attempt failed (exit $FIX_EXIT, no new commit) — closing PR"
            [ -f "$ARTIFACT_DIR/pr-url.txt" ] && gh pr close "$(cat "$ARTIFACT_DIR/pr-url.txt")" 2>/dev/null || true
            git -C "$PROJECT_DIR" push origin --delete "autorun/$SLUG" 2>/dev/null || true
            write_failure_item "fix-attempt" "fix attempt produced no commit (exit $FIX_EXIT)"
            return 0
        fi

        echo "[autorun] $SLUG: fix commit produced — re-running tests"
        log_run "$SLUG" "fix-attempt" 0

        # Re-run test_cmd after fix (in PROJECT_DIR — same as build.sh)
        FIX_TEST_PASSED=1
        if [ -n "${TEST_CMD:-}" ]; then
            TEST_EXIT=0
            (cd "$PROJECT_DIR" && eval "$TEST_CMD") 2>/dev/null || TEST_EXIT=$?
            if [ "$TEST_EXIT" -ne 0 ]; then
                FIX_TEST_PASSED=0
                echo "[autorun] $SLUG: tests failed after fix — closing PR"
            fi
        fi

        # Re-run Codex if tests passed
        FIX_CODEX_HIGH=0
        if [ "$FIX_TEST_PASSED" -eq 1 ] && [ "$CODEX_AVAILABLE" -eq 1 ]; then
            CODEX_FIX_OUTPUT="${TMPDIR:-/tmp}/codex-autorun-fix-review-${SLUG}.txt"
            CODEX_FIX_CONTEXT="$(mktemp "${TMPDIR:-/tmp}/autorun-codex-fix-ctx-XXXXXX.md")"
            {
              printf '## Git Diff (all committed changes)\n'
              [ "$PRE_BUILD_SHA" != "unknown" ] && \
                git -C "$PROJECT_DIR" diff "$PRE_BUILD_SHA" HEAD -- . 2>/dev/null | head -2000 || \
                printf '(diff unavailable)\n'
              printf '\n## Build Log (last 100 lines)\n'
              tail -100 "$ARTIFACT_DIR/build-log.md" 2>/dev/null || true
            } > "$CODEX_FIX_CONTEXT"
            CODEX_FIX_EXIT=0
            timeout "$TIMEOUT_CODEX" codex exec \
                --full-auto --ephemeral \
                --output-last-message "$CODEX_FIX_OUTPUT" \
                "Re-review after the fix attempt. Report only **High:** blocking findings that remain." \
                < "$CODEX_FIX_CONTEXT" \
                2>/dev/null || CODEX_FIX_EXIT=$?
            rm -f "$CODEX_FIX_CONTEXT"
            if [ "$CODEX_FIX_EXIT" -eq 0 ]; then
              FIX_CODEX_HIGH="$(grep -c '^\*\*High:\*\*' "$CODEX_FIX_OUTPUT" 2>/dev/null || true)"
              FIX_CODEX_HIGH="${FIX_CODEX_HIGH:-0}"
            fi
            echo "[autorun] $SLUG: post-fix Codex: $FIX_CODEX_HIGH High findings remain"
        fi

        if [ "$FIX_TEST_PASSED" -eq 0 ] || [ "$FIX_CODEX_HIGH" -gt 0 ]; then
            echo "[autorun] $SLUG: still failing after fix — closing PR, writing failure"
            [ -f "$ARTIFACT_DIR/pr-url.txt" ] && gh pr close "$(cat "$ARTIFACT_DIR/pr-url.txt")" 2>/dev/null || true
            git -C "$PROJECT_DIR" push origin --delete "autorun/$SLUG" 2>/dev/null || true
            write_failure_item "fix-attempt" "still failing after fix (tests=$FIX_TEST_PASSED codex_high=$FIX_CODEX_HIGH)"
            return 0
        fi

        echo "[autorun] $SLUG: fix successful — proceeding to merge"
        # Push the fix commit
        git -C "$PROJECT_DIR" push origin "autorun/$SLUG" 2>/dev/null || true
        CODEX_HIGH_COUNT=0  # cleared — fix succeeded
    fi

    # --- Stage 7: Squash merge gate ---
    if [ ! -f "$ARTIFACT_DIR/pr-url.txt" ]; then
        echo "[autorun] $SLUG: no PR URL — skipping merge"
        return 0
    fi

    if [ "$CODEX_HIGH_COUNT" -gt 0 ]; then
        echo "[autorun] $SLUG: $CODEX_HIGH_COUNT High-severity Codex findings remain — not merging"
        write_failure_item "merge-gate" "$CODEX_HIGH_COUNT High Codex finding(s) remain after fix attempt"
        return 0
    fi

    update_stage "merging"
    write_state "merging"
    PR_URL_MERGE="$(cat "$ARTIFACT_DIR/pr-url.txt")"

    MERGE_EXIT=0
    gh pr merge "$PR_URL_MERGE" --squash --auto 2>/dev/null || MERGE_EXIT=$?

    if [ "$MERGE_EXIT" -eq 0 ]; then
        # `gh pr merge --auto` exits 0 when auto-merge is *enabled*, which may
        # not mean the PR is actually merged yet (it merges when checks pass).
        # Query state so run-summary.md reflects reality.
        MERGE_STATE="$(gh pr view "$PR_URL_MERGE" --json state -q .state 2>/dev/null || echo "UNKNOWN")"
        if [ "$MERGE_STATE" = "MERGED" ]; then
            echo "[autorun] $SLUG: squash merged: $PR_URL_MERGE"
            log_run "$SLUG" "merge" 0
        else
            echo "[autorun] $SLUG: auto-merge enabled (state=$MERGE_STATE) — will merge when checks pass: $PR_URL_MERGE"
            log_run "$SLUG" "merge-auto-enabled" 0
        fi
    else
        echo "[autorun] $SLUG: WARN — merge failed (exit $MERGE_EXIT) — PR left open for manual review"
        log_run "$SLUG" "merge" "$MERGE_EXIT"
    fi

    # -------------------------------------------------------------------------
    # Item complete — write run-summary.md
    # -------------------------------------------------------------------------
    write_state "complete"
    update_stage "complete"

    cat > "$ARTIFACT_DIR/run-summary.md" <<SUMMARY_EOF
# Run Summary: $SLUG

**Completed:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Stages:** spec-review → risk-analysis → plan → check → build → pr-creation → codex-review → merge
**PR:** $(cat "$ARTIFACT_DIR/pr-url.txt" 2>/dev/null || echo "(not created)")
**Codex High findings:** $CODEX_HIGH_COUNT
**Status:** complete
SUMMARY_EOF

    echo "[autorun] $SLUG: complete"
    return 0
}

# ===========================================================================
# Main queue loop
# ===========================================================================
echo "[autorun] run.sh started (version=$AUTORUN_VERSION)"
echo "[autorun] queue: $QUEUE_DIR"

STOP_REQUESTED=0
ITEMS_PROCESSED=0
ITEMS_FAILED=0

for SPEC_FILE in "$QUEUE_DIR"/*.spec.md; do
    [ -f "$SPEC_FILE" ] || continue  # glob miss (no .spec.md files)

    SLUG="$(basename "$SPEC_FILE" .spec.md)"

    # Validate slug per documented regex (commands/autorun.md:61).
    # Unsafe slugs produce invalid branch names and quoting hazards in `python3 -c`.
    if [[ ! "$SLUG" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]]; then
        echo "[autorun] WARN: skipping '$SLUG.spec.md' — slug must match ^[a-z0-9][a-z0-9-]{0,63}\$"
        continue
    fi

    # Check STOP file between items
    if [ -f "$QUEUE_DIR/STOP" ]; then
        echo "[autorun] STOP file detected between items — halting"
        STOP_REQUESTED=1
        break
    fi

    ITEM_EXIT=0
    run_item "$SLUG" || ITEM_EXIT=$?

    if [ "$ITEM_EXIT" -eq 3 ]; then
        echo "[autorun] clean halt requested by build (STOP file)"
        STOP_REQUESTED=1
        break
    elif [ "$ITEM_EXIT" -ne 0 ]; then
        ITEMS_FAILED=$(( ITEMS_FAILED + 1 ))
    fi

    ITEMS_PROCESSED=$(( ITEMS_PROCESSED + 1 ))
done

# ---------------------------------------------------------------------------
# Write queue/index.md (morning artifact)
# ---------------------------------------------------------------------------
{
    echo "# Autorun Run Index"
    echo ""
    echo "**Generated:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    echo "| Slug | Status | Stage Reached | PR | Failure |"
    echo "|------|--------|---------------|----|---------|"
    for d in "$QUEUE_DIR"/*/; do
        [ -d "$d" ] || continue
        s="$(basename "$d")"
        if [ -f "$d/run-summary.md" ]; then
            pr="$(cat "$d/pr-url.txt" 2>/dev/null || echo "—")"
            echo "| $s | complete | merge | $pr | — |"
        elif [ -f "$d/failure.md" ]; then
            stage="$(grep -o 'stage=[a-z-]*' "$d/failure.md" | head -1 | cut -d= -f2 || echo unknown)"
            echo "| $s | failed | $stage | — | $d/failure.md |"
        fi
    done
} > "$QUEUE_DIR/index.md"

echo "[autorun] run complete. items=$ITEMS_PROCESSED failed=$ITEMS_FAILED"
echo "none" > "$QUEUE_DIR/.current-stage"

# ---------------------------------------------------------------------------
# Notify (best-effort — failure here does not affect exit code)
# ---------------------------------------------------------------------------
if [ -x "$ENGINE_DIR/scripts/autorun/notify.sh" ]; then
    NOTIFY_SUMMARY="$QUEUE_DIR/run-summary.md"
    cat > "$NOTIFY_SUMMARY" <<NS_EOF
# Autorun Run Summary
**Completed:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Items processed:** $ITEMS_PROCESSED
**Failures:** $ITEMS_FAILED
**Stop requested:** $STOP_REQUESTED
NS_EOF
    bash "$ENGINE_DIR/scripts/autorun/notify.sh" || true
fi
