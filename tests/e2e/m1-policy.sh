#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
version="$(skill-detector version 2>/dev/null || true)"
[[ "$version" == *"version 0.10.0 "* ]] || {
  echo "m1-policy: requires skill-detector v0.10.0 on PATH" >&2
  exit 1
}

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

engine_exit() {
  local threshold="$1" axis="$2" out="$scratch/engine.json" code=0
  set +e
  args=(scan "$ROOT/tests/fixtures/one-high-repo" --format json --fail-on "$threshold")
  [ -z "$axis" ] || args+=(--fail-on-axis "$axis")
  skill-detector "${args[@]}" > "$out"
  code=$?
  set -e
  echo "$code"
}

[ "$(engine_exit high '')" -eq 2 ]       # severity equality breaches
[ "$(engine_exit critical '')" -eq 1 ]   # HIGH is below CRITICAL
[ "$(engine_exit critical security=D)" -eq 1 ] # axis equality passes
[ "$(engine_exit critical security=C)" -eq 2 ] # D is strictly worse

run_action() {
  local report_only="$1" expected="$2"
  export RUNNER_TEMP="$scratch/run-$report_only"
  mkdir -p "$RUNNER_TEMP"
  export GITHUB_ENV="$RUNNER_TEMP/env" GITHUB_OUTPUT="$RUNNER_TEMP/output"
  : > "$GITHUB_ENV"; : > "$GITHUB_OUTPUT"
  INPUT_PATH="$ROOT/tests/fixtures/critical-repo" INPUT_FAIL_ON=critical \
    INPUT_STRICT_MCP=false INPUT_SCAN_ALL=false bash "$ROOT/scripts/scan.sh"
  set -a
  source "$GITHUB_ENV"
  set +a
  local raw_before="$(sha256sum "$RUNNER_TEMP/scan.json" | cut -d' ' -f1)" code=0
  set +e
  INPUT_REPORT_ONLY="$report_only" INPUT_WARN_ON_BELOW_THRESHOLD=true \
    bash "$ROOT/scripts/propagate-exit.sh"
  code=$?
  set -e
  [ "$code" -eq "$expected" ]
  [ "$(sha256sum "$RUNNER_TEMP/scan.json" | cut -d' ' -f1)" = "$raw_before" ]
  grep -q '^findings-count=' "$GITHUB_OUTPUT"
}

run_action false 2
run_action true 0
echo "m1-policy: severity/axis boundaries and both report modes passed"
