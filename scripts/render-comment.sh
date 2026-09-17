#!/usr/bin/env bash
set -euo pipefail

# Required env: RUNNER_TEMP, INPUT_SCAN_JSON.
# Optional: GITHUB_STEP_SUMMARY, GITHUB_EVENT_NAME, SCAN_EXIT_CODE and Action
# inputs used only as report metadata.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$RUNNER_TEMP/comment.md"
rm -f "$OUT"

ARGS=(
  --scan "$INPUT_SCAN_JSON"
  --published "$ROOT/config/published-rule-ids.txt"
  --comment "$OUT"
  --scope "${INPUT_PATH:-.}"
  --event "${GITHUB_EVENT_NAME:-unknown}"
  --exit-code "${SCAN_EXIT_CODE:-}"
  --report-only "${INPUT_REPORT_ONLY:-false}"
  --warn-below "${INPUT_WARN_ON_BELOW_THRESHOLD:-true}"
  --fail-no-surface "${INPUT_FAIL_ON_NO_AGENT_SURFACE:-false}"
)
[ -n "${GITHUB_STEP_SUMMARY:-}" ] && ARGS+=( --summary "$GITHUB_STEP_SUMMARY" )
[ "${INPUT_DELTA_ENABLED:-false}" = "true" ] && ARGS+=( --delta-enabled )

if ! command -v python3 >/dev/null 2>&1 || ! python3 "$ROOT/scripts/render.py" "${ARGS[@]}"; then
  printf '%s\n%s\n\n%s\n' \
    '<!-- skilltrust:action:v1 -->' \
    '## SkillTrust report unavailable' \
    'The scan completed, but its report could not be rendered. The scan policy and validated JSON remain unchanged.' > "$OUT"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    tail -n +2 "$OUT" >> "$GITHUB_STEP_SUMMARY" || true
  fi
  echo "::warning title=SkillTrust report unavailable::scan completed but safe rendering failed; scan policy is unchanged"
  exit 0
fi

echo "render-comment.sh: safe report written"
