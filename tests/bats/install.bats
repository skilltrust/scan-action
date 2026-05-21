#!/usr/bin/env bats

load helpers

setup() { setup_tmpdir; }
teardown() { teardown_tmpdir; }

@test "install.sh: rejects unknown RUNNER_OS" {
  RUNNER_OS=AmigaOS RUNNER_ARCH=X64 \
    RUNNER_TEMP="$TMPDIR_TEST" \
    INPUT_DETECTOR_VERSION=v0.2.1 \
    run bash "$BATS_TEST_DIRNAME/../../scripts/install.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported RUNNER_OS"* ]]
}

@test "install.sh: rejects unknown RUNNER_ARCH" {
  RUNNER_OS=Linux RUNNER_ARCH=PowerPC \
    RUNNER_TEMP="$TMPDIR_TEST" \
    INPUT_DETECTOR_VERSION=v0.2.1 \
    run bash "$BATS_TEST_DIRNAME/../../scripts/install.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported RUNNER_ARCH"* ]]
}
