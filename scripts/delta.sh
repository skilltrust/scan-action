#!/usr/bin/env bash
set -euo pipefail

# Required env: RUNNER_TEMP, INPUT_BASE_REF, INPUT_HEAD_SCAN_JSON.
# Optional env: INPUT_PATH, INPUT_STRICT_MCP, INPUT_SCAN_ALL, GITHUB_ENV,
# GITHUB_OUTPUT.

BASE_REF="${INPUT_BASE_REF:-}"
HEAD_JSON="${INPUT_HEAD_SCAN_JSON:-}"
SCAN_PATH="${INPUT_PATH:-.}"
BASE_DIR="$RUNNER_TEMP/skilltrust-base-worktree"
BASE_JSON="$RUNNER_TEMP/base-scan.json"
DELTA_OUT="$RUNNER_TEMP/delta.json"
WORKTREE_ADDED=false

clear_delta() {
  rm -f "$BASE_JSON" "$DELTA_OUT"
  [ -n "${GITHUB_ENV:-}" ] && echo "SCAN_ACTION_DELTA_JSON=" >> "$GITHUB_ENV"
  [ -n "${GITHUB_OUTPUT:-}" ] && echo "delta-json-path=" >> "$GITHUB_OUTPUT"
}

unavailable() {
  rm -f "$DELTA_OUT"
  [ -n "${GITHUB_ENV:-}" ] && echo "SCAN_ACTION_DELTA_JSON=" >> "$GITHUB_ENV"
  [ -n "${GITHUB_OUTPUT:-}" ] && echo "delta-json-path=" >> "$GITHUB_OUTPUT"
  echo "::warning title=SkillTrust delta unavailable::$1; the head scan result and gate are unchanged"
  exit 0
}

cleanup() {
  if [ "$WORKTREE_ADDED" = "true" ]; then
    if ! git worktree remove --force "$BASE_DIR" >/dev/null 2>&1; then
      echo "::warning title=SkillTrust::could not remove delta worktree $BASE_DIR"
    fi
  fi
}
trap cleanup EXIT

clear_delta

for value in "${INPUT_STRICT_MCP:-false}" "${INPUT_SCAN_ALL:-false}"; do
  if [ "$value" != "true" ] && [ "$value" != "false" ]; then
    unavailable "invalid boolean scope input"
  fi
done

[ -n "$BASE_REF" ] || unavailable "base ref is missing"
[ -s "$HEAD_JSON" ] || unavailable "head scan result is missing"
command -v jq >/dev/null 2>&1 || unavailable "jq is unavailable"

echo "delta.sh: fetching base $BASE_REF (depth=1)"
if ! git fetch origin "$BASE_REF" --depth 1; then
  unavailable "base fetch failed"
fi
if ! BASE_COMMIT="$(git rev-parse --verify 'FETCH_HEAD^{commit}')"; then
  unavailable "fetched base commit could not be resolved"
fi

rm -rf "$BASE_DIR"
echo "delta.sh: creating worktree at $BASE_DIR from $BASE_COMMIT"
if ! git worktree add --detach "$BASE_DIR" "$BASE_COMMIT" >/dev/null; then
  unavailable "base worktree creation failed"
fi
WORKTREE_ADDED=true

BASE_TARGET="$BASE_DIR"
[ "$SCAN_PATH" = "." ] || BASE_TARGET="$BASE_DIR/$SCAN_PATH"
[ -e "$BASE_TARGET" ] || unavailable "selected path is absent from the base commit"

BASE_ARGS=(scan "$BASE_TARGET" --format json)
[ "${INPUT_STRICT_MCP:-false}" = "true" ] && BASE_ARGS+=(--strict-mcp)
[ "${INPUT_SCAN_ALL:-false}" = "true" ] && BASE_ARGS+=(--scan-all)

echo "delta.sh: scanning base tree"
set +e
skill-detector "${BASE_ARGS[@]}" > "$BASE_JSON"
BASE_EXIT=$?
set -e
case "$BASE_EXIT" in
  0|1|2) ;;
  *) unavailable "base scan failed with exit $BASE_EXIT" ;;
esac

SCAN_VALIDATOR='
  (.findings | type == "array") and
  (if .no_agent_surface == true then
     (.findings | length == 0) and (has("axes") | not)
   else
     (has("no_agent_surface") | not) and (.axes | type == "object") and
     (.axes as $axes | ["security","permission_hygiene","transparency","quality"] |
       all(. as $axis | ($axes[$axis].grade | type == "string" and test("^[ABCDF]$"))))
   end)'
if ! jq -e "$SCAN_VALIDATOR" "$BASE_JSON" 2>/dev/null | grep -qx true; then
  unavailable "base scan result is missing, empty, malformed, or invalid"
fi
if ! jq -e --arg code "$BASE_EXIT" '
  if .no_agent_surface == true then $code == "0"
  elif $code == "0" then (.findings | length == 0)
  else (.findings | length > 0)
  end
' "$BASE_JSON" 2>/dev/null | grep -qx true; then
  unavailable "base scan exit and result disagree"
fi
if ! jq -e "$SCAN_VALIDATOR" "$HEAD_JSON" 2>/dev/null | grep -qx true; then
  unavailable "head scan result is missing, empty, malformed, or invalid"
fi

echo "delta.sh: computing delta"
set +e
skill-detector delta "$BASE_JSON" "$HEAD_JSON" --format json > "$DELTA_OUT"
DELTA_EXIT=$?
set -e
if [ "$DELTA_EXIT" -ne 0 ]; then
  unavailable "delta command failed with exit $DELTA_EXIT"
fi
if ! jq -e '
  (.per_axis | type == "object") and
  ([.per_axis[] | (.Old | type == "string") and (.New | type == "string") and
    (.Direction == "up" or .Direction == "down" or .Direction == "same")] | all) and
  ((.new_findings | type) == "array" or (.new_findings | type) == "null") and
  ((.resolved_findings | type) == "array" or (.resolved_findings | type) == "null") and
  (.axis_explanations | type == "object")
' "$DELTA_OUT" 2>/dev/null | grep -qx true; then
  unavailable "delta result is missing, empty, malformed, or invalid"
fi

[ -n "${GITHUB_OUTPUT:-}" ] && echo "delta-json-path=$DELTA_OUT" >> "$GITHUB_OUTPUT"
[ -n "${GITHUB_ENV:-}" ] && echo "SCAN_ACTION_DELTA_JSON=$DELTA_OUT" >> "$GITHUB_ENV"
echo "delta.sh: wrote $DELTA_OUT"
