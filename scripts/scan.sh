#!/usr/bin/env bash
set -euo pipefail

# Required env:
#   RUNNER_TEMP                  scratch dir
#   GITHUB_ENV                   path appended-to to set step env
#   GITHUB_OUTPUT                path appended-to to set action outputs
# Action inputs (from action.yml):
#   INPUT_PATH                   scan target path
#   INPUT_FAIL_ON                severity threshold
#   INPUT_FAIL_ON_AXIS           comma-separated axis=grade specs (may be empty)
#   INPUT_STRICT_MCP             "true" | "false"
#   INPUT_SCAN_ALL               "true" | "false"

SCAN_PATH="${INPUT_PATH:-.}"
FAIL_ON="${INPUT_FAIL_ON:-high}"

ARGS=( "scan" "$SCAN_PATH" "--format" "json" "--fail-on" "$FAIL_ON" )

if [ -n "${INPUT_FAIL_ON_AXIS:-}" ]; then
  IFS=',' read -ra AXIS_SPECS <<< "$INPUT_FAIL_ON_AXIS"
  for spec in "${AXIS_SPECS[@]}"; do
    spec="$(echo "$spec" | xargs)"  # trim whitespace
    [ -n "$spec" ] && ARGS+=( "--fail-on-axis" "$spec" )
  done
fi

[ "${INPUT_STRICT_MCP:-false}" = "true" ] && ARGS+=( "--strict-mcp" )
[ "${INPUT_SCAN_ALL:-false}"   = "true" ] && ARGS+=( "--scan-all" )

OUT="$RUNNER_TEMP/scan.json"
echo "scan.sh: running skill-detector ${ARGS[*]}"
set +e
skill-detector "${ARGS[@]}" > "$OUT"
EXIT=$?
set -e

if [ -n "${GITHUB_ENV:-}" ]; then
  echo "SCAN_EXIT_CODE=$EXIT" >> "$GITHUB_ENV"
fi
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "scan-json-path=$OUT" >> "$GITHUB_OUTPUT"
fi

# Extract grade + finding count from JSON (best-effort; absent fields render empty).
if command -v jq >/dev/null 2>&1; then
  GRADE="$(jq -r '
    if .axes then
      (.axes | to_entries | map(.value.grade) | sort | last) // ""
    else "" end' "$OUT")"
  FINDINGS="$(jq -r '.findings | length // 0' "$OUT")"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "grade=$GRADE"             >> "$GITHUB_OUTPUT"
    echo "findings-count=$FINDINGS" >> "$GITHUB_OUTPUT"
  fi
fi

echo "scan.sh: detector exit=$EXIT, scan json at $OUT"
