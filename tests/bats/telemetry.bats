#!/usr/bin/env bats

load helpers

setup() {
  setup_tmpdir
  export RUNNER_TEMP="$TMPDIR_TEST"
  export GITHUB_STEP_SUMMARY="$TMPDIR_TEST/summary.md"
  echo "summary survives" > "$GITHUB_STEP_SUMMARY"
  echo '{"version":"0.10.0","axes":{"security":{"grade":"B"},"quality":{"grade":"A"}},"findings":[{"private_marker":"DO_NOT_SEND","file_path":"secret/path"}],"private_marker":"DO_NOT_SEND"}' > "$RUNNER_TEMP/scan.json"

  # Fake curl that records POST body to $FAKE_CURL_BODY.
  cat > "$TMPDIR_TEST/curl" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "${FAKE_CURL_LOG:-/dev/null}"
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
  export FAKE_CURL_LOG="$TMPDIR_TEST/curl.log"
  : > "$FAKE_CURL_BODY"
  : > "$FAKE_CURL_LOG"

  export GITHUB_SERVER_URL="https://github.com"
  export GITHUB_REPOSITORY="private-owner/private-repo"
  export GITHUB_REPOSITORY_VISIBILITY="private"
  export GITHUB_EVENT_NAME="pull_request"
  export RUNNER_OS="Linux"
  export RUNNER_ARCH="X64"
  export INPUT_SCAN_JSON="$RUNNER_TEMP/scan.json"
  export INPUT_ACTION_VERSION="1.11.0"
  export INPUT_DETECTOR_VERSION="v0.10.0"
  export INPUT_DELTA_ENABLED="false"
}
teardown() { teardown_tmpdir; }

@test "telemetry.sh: captures exactly ten typed fields without private data or UTM context" {
  before="$(sha256sum "$INPUT_SCAN_JSON")"
  run bash "$BATS_TEST_DIRNAME/../../scripts/telemetry.sh"
  [ "$status" -eq 0 ]
  body="$(cat "$FAKE_CURL_BODY")"
  [ "$(jq 'keys | length' <<< "$body")" -eq 10 ]
  [ "$(jq -r 'keys | join(",")' <<< "$body")" = 'action_version,delta_enabled,detector_version,finding_count,grade,repo_hash,repo_visibility,runner_arch,runner_os,trigger' ]
  jq -e '
    .action_version == "1.11.0" and .detector_version == "v0.10.0" and
    .runner_os == "Linux" and .runner_arch == "X64" and
    .repo_visibility == "private" and (.repo_hash | test("^[0-9a-f]{64}$")) and
    .grade == "B" and .finding_count == 1 and
    .trigger == "pull_request" and .delta_enabled == false and
    (.finding_count | type == "number") and (.delta_enabled | type == "boolean")
  ' <<< "$body"
  [[ "$body" != *"private-owner"* && "$body" != *"private-repo"* ]]
  [[ "$body" != *"DO_NOT_SEND"* && "$body" != *"secret/path"* ]]
  [[ "$body" != *"utm_"* ]]
  [ "$before" = "$(sha256sum "$INPUT_SCAN_JSON")" ]
  grep -q -- '--max-time 3' "$FAKE_CURL_LOG"
}

@test "telemetry.sh: no-surface scan sends empty grade and numeric zero without leaking raw data" {
  printf '%s' '{"findings":[],"no_agent_surface":true,"private_marker":"DO_NOT_SEND","file_path":"secret/path"}' > "$INPUT_SCAN_JSON"
  run bash "$BATS_TEST_DIRNAME/../../scripts/telemetry.sh"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$FAKE_CURL_LOG")" -eq 1 ]
  body="$(cat "$FAKE_CURL_BODY")"
  [ "$(jq 'keys | length' <<< "$body")" -eq 10 ]
  [ "$(jq -r 'keys | join(",")' <<< "$body")" = 'action_version,delta_enabled,detector_version,finding_count,grade,repo_hash,repo_visibility,runner_arch,runner_os,trigger' ]
  jq -e '
    .grade == "" and (.grade | type == "string") and
    .finding_count == 0 and (.finding_count | type == "number") and
    .delta_enabled == false and (.delta_enabled | type == "boolean")
  ' <<< "$body"
  [[ "$body" != *"private-owner"* && "$body" != *"private-repo"* ]]
  [[ "$body" != *"DO_NOT_SEND"* && "$body" != *"secret/path"* ]]
  [[ "$body" != *"utm_"* && "$body" != *"no_agent_surface"* ]]
}

@test "telemetry.sh: succeeds even if curl fails (fire-and-forget)" {
  cat > "$TMPDIR_TEST/curl" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
  chmod +x "$TMPDIR_TEST/curl"
  run bash "$BATS_TEST_DIRNAME/../../scripts/telemetry.sh"
  [ "$status" -eq 0 ]
  grep -qx "summary survives" "$GITHUB_STEP_SUMMARY"
}

@test "telemetry.sh: malformed scan is nonessential and makes no request" {
  printf '{malformed' > "$INPUT_SCAN_JSON"
  run bash "$BATS_TEST_DIRNAME/../../scripts/telemetry.sh"
  [ "$status" -eq 0 ]
  [ ! -s "$FAKE_CURL_LOG" ]
  [ ! -s "$FAKE_CURL_BODY" ]
  grep -qx "summary survives" "$GITHUB_STEP_SUMMARY"
}
