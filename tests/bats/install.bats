#!/usr/bin/env bats

load helpers

setup() { setup_tmpdir; }
teardown() { teardown_tmpdir; }

@test "install.sh: rejects unknown RUNNER_OS" {
  local script="$BATS_TEST_DIRNAME/../../scripts/install.sh"
  run env \
    RUNNER_OS=AmigaOS RUNNER_ARCH=X64 \
    RUNNER_TEMP="$TMPDIR_TEST" \
    INPUT_DETECTOR_VERSION=v0.2.1 \
    bash -c "'$script' 2>&1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported RUNNER_OS"* ]]
}

@test "install.sh: rejects unknown RUNNER_ARCH" {
  local script="$BATS_TEST_DIRNAME/../../scripts/install.sh"
  run env \
    RUNNER_OS=Linux RUNNER_ARCH=PowerPC \
    RUNNER_TEMP="$TMPDIR_TEST" \
    INPUT_DETECTOR_VERSION=v0.2.1 \
    bash -c "'$script' 2>&1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported RUNNER_ARCH"* ]]
}
