#!/usr/bin/env bats

load helpers

setup() {
  setup_tmpdir
  # Put fake-detector on PATH as `skill-detector`.
  cp "$BATS_TEST_DIRNAME/fixtures/fake-detector.sh" "$TMPDIR_TEST/skill-detector"
  chmod +x "$TMPDIR_TEST/skill-detector"
  export PATH="$TMPDIR_TEST:$PATH"
  export RUNNER_TEMP="$TMPDIR_TEST"
  : > "$TMPDIR_TEST/github_env"
  export GITHUB_ENV="$TMPDIR_TEST/github_env"
  : > "$TMPDIR_TEST/github_output"
  export GITHUB_OUTPUT="$TMPDIR_TEST/github_output"
}
teardown() { teardown_tmpdir; }

@test "scan.sh: writes scan.json to RUNNER_TEMP" {
  export FAKE_DETECTOR_JSON='{"findings":[],"axes":{"security":{"grade":"A","rationale":""}},"files_scanned":1,"rules_applied":21}'
  export INPUT_PATH="."
  export INPUT_FAIL_ON="high"
  export INPUT_FAIL_ON_AXIS=""
  export INPUT_STRICT_MCP="false"
  export INPUT_SCAN_ALL="false"
  run bash "$BATS_TEST_DIRNAME/../../scripts/scan.sh"
  [ "$status" -eq 0 ]
  [ -f "$RUNNER_TEMP/scan.json" ]
  grep -q '"files_scanned":1' "$RUNNER_TEMP/scan.json"
}

@test "scan.sh: captures non-zero detector exit code into GITHUB_ENV without failing the step" {
  export FAKE_DETECTOR_EXIT=2
  export FAKE_DETECTOR_JSON='{"findings":[{"rule_id":"SD-001"}],"axes":{},"files_scanned":1,"rules_applied":21}'
  export INPUT_PATH="."
  export INPUT_FAIL_ON="high"
  export INPUT_FAIL_ON_AXIS=""
  export INPUT_STRICT_MCP="false"
  export INPUT_SCAN_ALL="false"
  run bash "$BATS_TEST_DIRNAME/../../scripts/scan.sh"
  [ "$status" -eq 0 ]
  grep -q "SCAN_EXIT_CODE=2" "$GITHUB_ENV"
}

@test "scan.sh: threads --fail-on-axis when set" {
  export FAKE_DETECTOR_JSON='{"findings":[],"axes":{},"files_scanned":0,"rules_applied":0}'
  export INPUT_PATH="."
  export INPUT_FAIL_ON="high"
  export INPUT_FAIL_ON_AXIS="permission_hygiene=C,security=C"
  export INPUT_STRICT_MCP="true"
  export INPUT_SCAN_ALL="true"
  # Replace fake with arg-recording variant that writes args to a side-channel file.
  local args_file="$TMPDIR_TEST/args.txt"
  cat > "$TMPDIR_TEST/skill-detector" <<EOF
#!/usr/bin/env bash
echo "\$*" > "$args_file"
echo '${FAKE_DETECTOR_JSON}'
EOF
  chmod +x "$TMPDIR_TEST/skill-detector"
  local script="$BATS_TEST_DIRNAME/../../scripts/scan.sh"
  run env \
    INPUT_PATH="$INPUT_PATH" INPUT_FAIL_ON="$INPUT_FAIL_ON" \
    INPUT_FAIL_ON_AXIS="$INPUT_FAIL_ON_AXIS" INPUT_STRICT_MCP="$INPUT_STRICT_MCP" \
    INPUT_SCAN_ALL="$INPUT_SCAN_ALL" FAKE_DETECTOR_JSON="$FAKE_DETECTOR_JSON" \
    RUNNER_TEMP="$RUNNER_TEMP" GITHUB_ENV="$GITHUB_ENV" GITHUB_OUTPUT="$GITHUB_OUTPUT" \
    PATH="$PATH" \
    bash "$script"
  [ "$status" -eq 0 ]
  [ -f "$args_file" ]
  grep -q -- "--fail-on-axis permission_hygiene=C" "$args_file"
  grep -q -- "--fail-on-axis security=C" "$args_file"
  grep -q -- "--strict-mcp" "$args_file"
  grep -q -- "--scan-all" "$args_file"
}
