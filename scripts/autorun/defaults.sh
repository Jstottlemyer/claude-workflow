##############################################################################
# scripts/autorun/defaults.sh
#
# Sourced (NOT executed) by every autorun stage script and by run.sh.
# Exports config defaults and — if CONFIG_FILE exists — overrides them with
# values from queue/autorun.config.json.
#
# Env vars set by the CALLER (run.sh) before sourcing — do NOT set here:
#   SLUG            queue item slug (e.g. "myfeature")
#   QUEUE_DIR       absolute path to queue/
#   ARTIFACT_DIR    absolute path to queue/<slug>/
#   SPEC_FILE       absolute path to the .spec.md entry file
#   CONFIG_FILE     absolute path to queue/autorun.config.json
#   AUTORUN         "1" — signals headless mode to command files
#   AUTORUN_VERSION read from VERSION file at repo root
#
# AUTORUN_DRY_RUN stub contract (for stage scripts):
#   When AUTORUN_DRY_RUN=1, each stage script should write a minimal stub
#   artifact and exit 0 without calling `claude -p`.  defaults.sh only
#   exports the variable; stub behaviour is implemented in each stage script.
##############################################################################

# No set -euo pipefail here — this file is sourced, not executed.

# ---------------------------------------------------------------------------
# Config defaults — use ${VAR:-default} so a caller can pre-set any of these.
# ---------------------------------------------------------------------------

# Halt a queue item if >= this many FAIL verdicts come from the 6 spec-reviewers.
export SPEC_REVIEW_FATAL_THRESHOLD="${SPEC_REVIEW_FATAL_THRESHOLD:-2}"

# Number of build-wave retries before rolling back.
export BUILD_MAX_RETRIES="${BUILD_MAX_RETRIES:-3}"

# Seconds passed to timeout(1) wrapping every `claude -p` invocation.
export TIMEOUT_STAGE="${TIMEOUT_STAGE:-300}"

# Seconds passed to timeout(1) wrapping every `codex` invocation.
export TIMEOUT_CODEX="${TIMEOUT_CODEX:-120}"

# Set to "1" to run stage scripts in stub mode (exit 0, no real API calls).
export AUTORUN_DRY_RUN="${AUTORUN_DRY_RUN:-0}"

# Email address for notify.sh — empty string disables mail.
export MAIL_TO="${MAIL_TO:-}"

# Slack / generic webhook URL for notify.sh — empty string disables webhook.
export WEBHOOK_URL="${WEBHOOK_URL:-}"

# Shell command run after each build attempt; empty = skip tests. Set to "exit 1" to test retry logic.
export TEST_CMD="${TEST_CMD:-}"

# ---------------------------------------------------------------------------
# Override defaults from autorun.config.json when present
# ---------------------------------------------------------------------------

if [ -f "${CONFIG_FILE:-}" ] && [ -r "${CONFIG_FILE:-}" ]; then
  if command -v python3 >/dev/null 2>&1; then
    _overrides="$(python3 -c "
import json, sys

path = '$CONFIG_FILE'
try:
    with open(path) as f:
        cfg = json.load(f)
except Exception:
    sys.exit(0)

mapping = {
    'spec_review_fatal_threshold': 'SPEC_REVIEW_FATAL_THRESHOLD',
    'build_max_retries':           'BUILD_MAX_RETRIES',
    'timeout_stage':               'TIMEOUT_STAGE',
    'timeout_codex':               'TIMEOUT_CODEX',
    'autorun_dry_run':             'AUTORUN_DRY_RUN',
    'mail_to':                     'MAIL_TO',
    'webhook_url':                 'WEBHOOK_URL',
    'test_cmd':                    'TEST_CMD',
}
for json_key, env_key in mapping.items():
    if json_key in cfg:
        val = str(cfg[json_key])
        # Emit shell-safe export assignments; values are single-quoted.
        safe = val.replace(\"'\", \"'\\\\''\"  )
        print(\"export {}='{}'\".format(env_key, safe))
" 2>/dev/null)"

    # Evaluate the emitted export statements (may be empty string on error).
    if [ -n "$_overrides" ]; then
      eval "$_overrides"
    fi
    unset _overrides
  fi
  # If python3 is not available, silently keep the defaults set above.
fi
