#!/usr/bin/env bats

load helpers

setup() {
  setup_tmpdir
  mkdir -p "$TMPDIR_TEST/bin" "$TMPDIR_TEST/release"
  cat > "$TMPDIR_TEST/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out= url=
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    --retry) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
printf '%s\n' "$url" >> "$FAKE_CURL_LOG"
[[ "${FAKE_DOWNLOAD_FAILURE:-}" != "$(basename "$url")" ]] || exit 22
cp "$FAKE_RELEASE_DIR/$(basename "$url")" "$out"
EOF
  chmod +x "$TMPDIR_TEST/bin/curl"
  export PATH="$TMPDIR_TEST/bin:$PATH"
  export FAKE_RELEASE_DIR="$TMPDIR_TEST/release"
  export FAKE_CURL_LOG="$TMPDIR_TEST/curl.log"
  export RUNNER_TEMP="$TMPDIR_TEST/runner"
  export GITHUB_PATH="$TMPDIR_TEST/github-path"
  export GITHUB_ENV="$TMPDIR_TEST/github-env"
  export INPUT_DETECTOR_VERSION=v0.10.0
  unset FAKE_DOWNLOAD_FAILURE
}
teardown() { teardown_tmpdir; }

make_release() {
  local os="$1" arch="$2" reported="${3:-0.10.0}"
  local asset="skill-detector_0.10.0_${os}_${arch}.tar.gz"
  rm -rf "$TMPDIR_TEST/payload"
  mkdir -p "$TMPDIR_TEST/payload"
  cat > "$TMPDIR_TEST/payload/skill-detector" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = version ]; then echo "skill-detector version $reported (fixture)"; exit 0; fi
exit 99
EOF
  chmod +x "$TMPDIR_TEST/payload/skill-detector"
  tar -czf "$FAKE_RELEASE_DIR/$asset" -C "$TMPDIR_TEST/payload" skill-detector
  printf '%s  %s\n' "$(sha256sum "$FAKE_RELEASE_DIR/$asset" | awk '{print $1}')" "$asset" > "$FAKE_RELEASE_DIR/checksums.txt"
}

run_install() {
  rm -rf "$RUNNER_TEMP"
  : > "$FAKE_CURL_LOG"; : > "$GITHUB_PATH"; : > "$GITHUB_ENV"
  run env RUNNER_OS="$1" RUNNER_ARCH="$2" bash "$BATS_TEST_DIRNAME/../../scripts/install.sh"
}

@test "install.sh: v0.10.0 exact assets, checksums, and version gate cover supported POSIX paths" {
  local runner_os os runner_arch arch
  while read -r runner_os os runner_arch arch; do
    make_release "$os" "$arch"
    run_install "$runner_os" "$runner_arch"
    [ "$status" -eq 0 ]
    asset="skill-detector_0.10.0_${os}_${arch}.tar.gz"
    grep -qx "https://github.com/skilltrust/skill-detector/releases/download/v0.10.0/$asset" "$FAKE_CURL_LOG"
    grep -qx 'https://github.com/skilltrust/skill-detector/releases/download/v0.10.0/checksums.txt' "$FAKE_CURL_LOG"
    [ "$("$RUNNER_TEMP/skill-detector-install/skill-detector" version)" = 'skill-detector version 0.10.0 (fixture)' ]
    grep -qx "$RUNNER_TEMP/skill-detector-install" "$GITHUB_PATH"
    grep -qx "SCAN_ACTION_DETECTOR_DIR=$RUNNER_TEMP/skill-detector-install" "$GITHUB_ENV"
  done <<'CASES'
Linux linux X64 amd64
Linux linux ARM64 arm64
macOS darwin X64 amd64
macOS darwin ARM64 arm64
CASES
}

@test "install.sh: rejects tampered archive before extraction" {
  make_release linux amd64
  printf tamper >> "$FAKE_RELEASE_DIR/skill-detector_0.10.0_linux_amd64.tar.gz"
  run_install Linux X64
  [ "$status" -ne 0 ]
  [[ "$output" == *"checksum mismatch"* ]]
  [ ! -e "$RUNNER_TEMP/skill-detector-install/skill-detector" ]
}

@test "install.sh: rejects missing checksum entry" {
  make_release linux amd64
  printf '%064d  another-asset.tar.gz\n' 0 > "$FAKE_RELEASE_DIR/checksums.txt"
  run_install Linux X64
  [ "$status" -ne 0 ]
  [[ "$output" == *"must appear exactly once"* ]]
}

@test "install.sh: propagates download failure" {
  make_release linux amd64
  export FAKE_DOWNLOAD_FAILURE=checksums.txt
  run_install Linux X64
  [ "$status" -ne 0 ]
  [ "$(wc -l < "$FAKE_CURL_LOG")" -eq 2 ]
}

@test "install.sh: rejects archive reporting the wrong detector version" {
  make_release linux amd64 0.9.9
  run_install Linux X64
  [ "$status" -ne 0 ]
  [[ "$output" == *"version does not match v0.10.0"* ]]
}

@test "install.sh: rejects unknown RUNNER_OS without a request" {
  run_install AmigaOS X64
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported RUNNER_OS"* ]]
  [ ! -s "$FAKE_CURL_LOG" ]
}

@test "install.sh: rejects unknown RUNNER_ARCH without a request" {
  run_install Linux PowerPC
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported RUNNER_ARCH"* ]]
  [ ! -s "$FAKE_CURL_LOG" ]
}
