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

@test "install.sh: constructs asset filename with version segment (no 'v' prefix)" {
  # Verify the URL the script would request includes the version number
  # in the GoReleaser-emitted format (e.g. skill-detector_0.3.1_linux_amd64.tar.gz).
  # We can't actually let it download, so trace the curl call via a fake curl.
  cat > "$TMPDIR_TEST/curl" <<'EOF'
#!/usr/bin/env bash
echo "CURL: $*" >> "$TMPDIR_TEST/curl.log"
exit 1   # fail download so the script aborts after logging
EOF
  chmod +x "$TMPDIR_TEST/curl"
  cat > "$TMPDIR_TEST/sha256sum" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$TMPDIR_TEST/sha256sum"
  : > "$TMPDIR_TEST/curl.log"
  local script="$BATS_TEST_DIRNAME/../../scripts/install.sh"
  run env \
    PATH="$TMPDIR_TEST:$PATH" \
    RUNNER_OS=Linux \
    RUNNER_ARCH=X64 \
    RUNNER_TEMP="$TMPDIR_TEST" \
    INPUT_DETECTOR_VERSION=v0.3.1 \
    bash "$script"
  # Script exits non-zero (curl failed) — that's fine. We just assert the URL is right.
  [[ -s "$TMPDIR_TEST/curl.log" ]]
  grep -q "skill-detector_0.3.1_linux_amd64.tar.gz" "$TMPDIR_TEST/curl.log"
}
