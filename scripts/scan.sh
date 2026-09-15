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
# Mirrors action.yml's `fail-on` default. action.yml is the source of truth;
# this fallback exists only for a direct invocation with no env, and
# tests/bats/gate-defaults.bats reads action.yml and pins the two together so
# they cannot drift.
FAIL_ON="${INPUT_FAIL_ON:-critical}"

OUT="$RUNNER_TEMP/scan.json"
rm -f "$OUT"

defer_failure() {
  local code="${1:-3}"
  [ -n "${GITHUB_ENV:-}" ] && echo "SCAN_EXIT_CODE=$code" >> "$GITHUB_ENV"
  [ -n "${GITHUB_OUTPUT:-}" ] && echo "result-valid=false" >> "$GITHUB_OUTPUT"
}

for value in "${INPUT_STRICT_MCP:-false}" "${INPUT_SCAN_ALL:-false}"; do
  if [ "$value" != "true" ] && [ "$value" != "false" ]; then
    echo "::error title=SkillTrust::boolean inputs must be the string 'true' or 'false'"
    defer_failure 3
    exit 0
  fi
done

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

echo "scan.sh: running skill-detector ${ARGS[*]}"
set +e
skill-detector "${ARGS[@]}" > "$OUT"
EXIT=$?
set -e

if [ "$EXIT" != "0" ] && [ "$EXIT" != "1" ] && [ "$EXIT" != "2" ]; then
  defer_failure "$EXIT"
  echo "scan.sh: detector failed with exit=$EXIT; no result outputs published"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1 ||
   ! jq -e --arg code "$EXIT" '
      def grade: type == "string" and test("^[ABCDF]$");
      . as $result |
      (.findings | type == "array") and
      (if .no_agent_surface == true then
         (.findings | length == 0) and (has("axes") | not) and ($code == "0")
       else
         (has("no_agent_surface") | not) and
         (.axes | type == "object") and
         (["security", "permission_hygiene", "transparency", "quality"] |
           all(. as $axis | ($result.axes[$axis].grade | grade))) and
         (if $code == "0" then (.findings | length == 0)
          else (.findings | length > 0) end)
       end)
    ' "$OUT" 2>/dev/null | grep -qx true; then
  echo "::error title=SkillTrust::detector returned a missing, empty, malformed, or invalid scan result"
  defer_failure 3
  exit 0
fi

GRADE="$(jq -r 'if .no_agent_surface == true then "" else .axes.quality.grade end' "$OUT")"
FINDINGS="$(jq -r '.findings | length' "$OUT")"
NO_SURFACE="$(jq -r '.no_agent_surface == true' "$OUT")"

[ -n "${GITHUB_ENV:-}" ] && echo "SCAN_EXIT_CODE=$EXIT" >> "$GITHUB_ENV"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "result-valid=true"              >> "$GITHUB_OUTPUT"
  echo "scan-json-path=$OUT"            >> "$GITHUB_OUTPUT"
  echo "grade=$GRADE"                   >> "$GITHUB_OUTPUT"
  echo "findings-count=$FINDINGS"       >> "$GITHUB_OUTPUT"
  echo "no-agent-surface=$NO_SURFACE"   >> "$GITHUB_OUTPUT"
fi

echo "scan.sh: detector exit=$EXIT, scan json at $OUT"
