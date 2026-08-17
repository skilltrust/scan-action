#!/usr/bin/env bash
set -euo pipefail

# Required env:
#   RUNNER_TEMP
#   INPUT_BASE_REF           base branch name (e.g. "main")
#   INPUT_HEAD_SCAN_JSON     path to existing head scan JSON (from scan.sh)
#   INPUT_PATH               relative scan path within repo (default ".")
#   INPUT_STRICT_MCP         "true" | "false"
#   INPUT_SCAN_ALL           "true" | "false"

BASE_REF="$INPUT_BASE_REF"
HEAD_JSON="$INPUT_HEAD_SCAN_JSON"
SCAN_PATH="${INPUT_PATH:-.}"
BASE_DIR="$RUNNER_TEMP/skilltrust-base-worktree"

echo "delta.sh: fetching base $BASE_REF (depth=1)"
git fetch origin "$BASE_REF" --depth 1

echo "delta.sh: creating worktree at $BASE_DIR"
git worktree add --detach "$BASE_DIR" "origin/$BASE_REF" >/dev/null

BASE_TARGET="$BASE_DIR"
if [ "$SCAN_PATH" != "." ]; then
  BASE_TARGET="$BASE_DIR/$SCAN_PATH"
fi

BASE_ARGS=( "scan" "$BASE_TARGET" "--format" "json" )
[ "${INPUT_STRICT_MCP:-false}" = "true" ] && BASE_ARGS+=( "--strict-mcp" )
[ "${INPUT_SCAN_ALL:-false}"   = "true" ] && BASE_ARGS+=( "--scan-all" )
# --fail-on / --fail-on-axis are deliberately not threaded here: they only
# set the head scan's exit code, and the base scan's exit code is discarded
# below (`|| true`). Threading them would change nothing but the comment.

BASE_JSON="$RUNNER_TEMP/base-scan.json"
echo "delta.sh: scanning base tree"
skill-detector "${BASE_ARGS[@]}" > "$BASE_JSON" || true

DELTA_OUT="$RUNNER_TEMP/delta.json"
echo "delta.sh: computing delta"
skill-detector delta "$BASE_JSON" "$HEAD_JSON" --format json > "$DELTA_OUT"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "delta-json-path=$DELTA_OUT" >> "$GITHUB_OUTPUT"
fi
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "SCAN_ACTION_DELTA_JSON=$DELTA_OUT" >> "$GITHUB_ENV"
fi
echo "delta.sh: wrote $DELTA_OUT"
