#!/usr/bin/env bats

load helpers

setup() {
  setup_tmpdir
  export RUNNER_TEMP="$TMPDIR_TEST"
  echo '{"version":"0.3.1","axes":{"security":{"grade":"B"}},"findings":[]}' > "$RUNNER_TEMP/scan.json"

  # Fake curl that records POST body to $FAKE_CURL_BODY.
  cat > "$TMPDIR_TEST/curl" <<'EOF'
#!/usr/bin/env bash
LAST=""
while [ $# -gt 0 ]; do
  case "$1" in
    -d|--data)        LAST="$2"; shift 2 ;;
    --data-binary)    LAST="$2"; shift 2 ;;
    *) shift ;;
  esac
done
# Strip leading @file: marker — fake-curl interprets it as a file path.
if [[ "$LAST" == @* ]]; then
  cat "${LAST:1}" > "${FAKE_CURL_BODY:-/dev/null}"
else
  echo -n "$LAST" > "${FAKE_CURL_BODY:-/dev/null}"
fi
echo "OK"
EOF
  chmod +x "$TMPDIR_TEST/curl"
  export PATH="$TMPDIR_TEST:$PATH"
  export FAKE_CURL_BODY="$TMPDIR_TEST/curl-body.txt"
  : > "$FAKE_CURL_BODY"

  export GITHUB_SERVER_URL="https://github.com"
  export GITHUB_REPOSITORY="acme/widgets"
  export GITHUB_EVENT_NAME="pull_request"
  export RUNNER_OS="Linux"
  export RUNNER_ARCH="X64"
  export INPUT_SCAN_JSON="$RUNNER_TEMP/scan.json"
  export INPUT_ACTION_VERSION="1.0.0"
  export INPUT_DETECTOR_VERSION="v0.3.1"
}
teardown() { teardown_tmpdir; }

@test "telemetry.sh: POSTs payload with hashed repo identifier" {
  run bash "$BATS_TEST_DIRNAME/../../scripts/telemetry.sh"
  [ "$status" -eq 0 ]
  body="$(cat "$FAKE_CURL_BODY")"
  [[ "$body" == *'"action_version":"1.0.0"'* ]]
  [[ "$body" == *'"detector_version":"v0.3.1"'* ]]
  [[ "$body" == *'"runner_os":"Linux"'* ]]
  [[ "$body" == *'"repo_hash":'* ]]
  # No raw repo URL or findings
  [[ "$body" != *"acme/widgets"* ]]
}

@test "telemetry.sh: succeeds even if curl fails (fire-and-forget)" {
  cat > "$TMPDIR_TEST/curl" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
  chmod +x "$TMPDIR_TEST/curl"
  run bash "$BATS_TEST_DIRNAME/../../scripts/telemetry.sh"
  [ "$status" -eq 0 ]
}
