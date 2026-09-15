#!/usr/bin/env bats

load helpers

setup() {
  setup_tmpdir
  export RUNNER_TEMP="$TMPDIR_TEST/runner temp"
  mkdir -p "$RUNNER_TEMP" "$TMPDIR_TEST/bin"
  export GITHUB_ENV="$TMPDIR_TEST/github_env"
  export GITHUB_OUTPUT="$TMPDIR_TEST/github_output"
  : > "$GITHUB_ENV"
  : > "$GITHUB_OUTPUT"

  git init -q --bare "$TMPDIR_TEST/origin.git"
  git init -q "$TMPDIR_TEST/repo"
  git -C "$TMPDIR_TEST/repo" config user.email test@example.invalid
  git -C "$TMPDIR_TEST/repo" config user.name Test
  mkdir -p "$TMPDIR_TEST/repo/agent path/ñ"
  echo base > "$TMPDIR_TEST/repo/agent path/ñ/marker"
  git -C "$TMPDIR_TEST/repo" add .
  git -C "$TMPDIR_TEST/repo" commit -qm base
  git -C "$TMPDIR_TEST/repo" branch -M main
  git -C "$TMPDIR_TEST/repo" remote add origin "$TMPDIR_TEST/origin.git"
  git -C "$TMPDIR_TEST/repo" push -q -u origin main
  echo head > "$TMPDIR_TEST/repo/agent path/ñ/marker"
  git -C "$TMPDIR_TEST/repo" commit -qam head

  cat > "$TMPDIR_TEST/bin/git" <<'EOF'
#!/usr/bin/env bash
if [ "${FAIL_GIT_STAGE:-}" = "fetch" ] && [ "$1" = fetch ]; then exit 9; fi
if [ "${FAIL_GIT_STAGE:-}" = "worktree" ] && [ "$1" = worktree ] && [ "$2" = add ]; then exit 9; fi
exec /usr/bin/git "$@"
EOF
  cat > "$TMPDIR_TEST/bin/skill-detector" <<'EOF'
#!/usr/bin/env bash
printf '%s\0' "$@" >> "$ARGS_LOG"
printf '\n' >> "$ARGS_LOG"
if [ "$1" = scan ]; then
  printf '%s\n' "${FAKE_BASE_JSON:-$(jq -nc '{findings:[],axes:{security:{grade:"A"},permission_hygiene:{grade:"A"},transparency:{grade:"A"},quality:{grade:"A"}}}')}"
  exit "${BASE_EXIT:-0}"
fi
printf '%s\n' "${DELTA_JSON:-$(jq -nc '{per_axis:{quality:{Old:"A",New:"B",Direction:"down"}},new_findings:[{rule_id:"new"}],resolved_findings:[{rule_id:"old"}],axis_explanations:{quality:"changed"}}')}"
exit "${DELTA_EXIT:-0}"
EOF
  chmod +x "$TMPDIR_TEST/bin/git" "$TMPDIR_TEST/bin/skill-detector"
  export PATH="$TMPDIR_TEST/bin:$PATH"
  export ARGS_LOG="$TMPDIR_TEST/args.log"
  : > "$ARGS_LOG"
  export INPUT_BASE_REF=main
  export INPUT_PATH='agent path/ñ'
  export INPUT_STRICT_MCP=false
  export INPUT_SCAN_ALL=false
  export INPUT_HEAD_SCAN_JSON="$RUNNER_TEMP/head result.json"
  graded_scan_json '[{"rule_id":"head"}]' B > "$INPUT_HEAD_SCAN_JSON"
}

teardown() { teardown_tmpdir; }

run_delta() {
  run bash -c 'cd "$1" && exec bash "$2"' _ "$TMPDIR_TEST/repo" "$BATS_TEST_DIRNAME/../../scripts/delta.sh"
}

@test "delta.sh: real fetched commit, difficult path, valid delta, and cleanup" {
  run_delta
  [ "$status" -eq 0 ]
  [ -s "$RUNNER_TEMP/delta.json" ]
  grep -q '^SCAN_ACTION_DELTA_JSON=.*delta.json$' "$GITHUB_ENV"
  [ ! -e "$RUNNER_TEMP/skilltrust-base-worktree" ]
  grep -Fq 'agent path/ñ' "$ARGS_LOG"
}

@test "delta.sh: base receives only path, strict-mcp, and scan-all" {
  export INPUT_STRICT_MCP=true INPUT_SCAN_ALL=true
  run_delta
  [ "$status" -eq 0 ]
  python3 - "$ARGS_LOG" <<'PY'
import sys
args=open(sys.argv[1],'rb').read().splitlines()[0].split(b'\0')
assert b'--strict-mcp' in args and b'--scan-all' in args
assert b'--fail-on' not in args and b'--fail-on-axis' not in args
PY
}

@test "delta.sh: base exits 0, 1, and 2 are accepted only with valid JSON" {
  for code in 0 1 2; do
    export BASE_EXIT="$code"
    if [ "$code" -eq 0 ]; then
      export FAKE_BASE_JSON="$(graded_scan_json)"
    else
      export FAKE_BASE_JSON="$(graded_scan_json '[{"rule_id":"base"}]')"
    fi
    : > "$GITHUB_ENV"
    run_delta
    [ "$status" -eq 0 ]
    grep -q '^SCAN_ACTION_DELTA_JSON=.*delta.json$' "$GITHUB_ENV"
  done
  export FAKE_BASE_JSON='{bad'
  run_delta
  [ "$status" -eq 0 ]
  [[ "$output" == *"delta unavailable"* ]]
  [ ! -e "$RUNNER_TEMP/delta.json" ]
}

@test "delta.sh: fetch, worktree, missing path, base exit, and delta failures are unavailable" {
  for stage in fetch worktree missing-path base-exit delta-exit; do
    unset FAIL_GIT_STAGE BASE_EXIT DELTA_EXIT
    export INPUT_PATH='agent path/ñ'
    case "$stage" in
      fetch|worktree) export FAIL_GIT_STAGE="$stage" ;;
      missing-path) export INPUT_PATH=absent ;;
      base-exit) export BASE_EXIT=3 ;;
      delta-exit) export DELTA_EXIT=3 ;;
    esac
    run_delta
    [ "$status" -eq 0 ]
    [[ "$output" == *"delta unavailable"* ]]
    [ ! -s "$RUNNER_TEMP/delta.json" ]
    [ ! -e "$RUNNER_TEMP/skilltrust-base-worktree" ]
  done
}

@test "delta.sh: malformed delta never appears as zero findings and stale state is cleared" {
  echo stale > "$RUNNER_TEMP/delta.json"
  echo 'SCAN_ACTION_DELTA_JSON=/stale/delta.json' > "$GITHUB_ENV"
  export DELTA_JSON='{"per_axis":{}}'
  run_delta
  [ "$status" -eq 0 ]
  [[ "$output" == *"delta unavailable"* ]]
  [ ! -e "$RUNNER_TEMP/delta.json" ]
  [ "$(grep -c '^SCAN_ACTION_DELTA_JSON=$' "$GITHUB_ENV")" -ge 1 ]
  ! grep -q 'new_findings.*\[\]' "$GITHUB_ENV"
}

@test "delta.sh: missing base ref or head result is explicitly unavailable" {
  export INPUT_BASE_REF=
  run_delta
  [ "$status" -eq 0 ]
  [[ "$output" == *"base ref is missing"* ]]
  export INPUT_BASE_REF=main INPUT_HEAD_SCAN_JSON="$RUNNER_TEMP/missing.json"
  run_delta
  [ "$status" -eq 0 ]
  [[ "$output" == *"head scan result is missing"* ]]
}

@test "delta unavailable preserves both passing and failing head gates" {
  export INPUT_BASE_REF=
  run_delta
  [ "$status" -eq 0 ]
  for code in 0 2; do
    run env SCAN_EXIT_CODE="$code" INPUT_REPORT_ONLY=false \
      bash "$BATS_TEST_DIRNAME/../../scripts/propagate-exit.sh"
    [ "$status" -eq "$code" ]
  done
}

@test "delta.sh: hostile missing path cannot inject workflow commands" {
  export INPUT_PATH=$'absent\n::error::injected\n::stop-commands::token'
  run_delta
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^::warning')" -eq 1 ]
  [[ "$output" == *"selected path is absent"* ]]
  [[ "$output" != *"::error::injected"* ]]
  [[ "$output" != *"::stop-commands::token"* ]]
}
