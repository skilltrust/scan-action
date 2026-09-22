#!/usr/bin/env bats

ROOT="$BATS_TEST_DIRNAME/../.."

@test "README: copyable onboarding is explicitly nonblocking report-only" {
  grep -q "report-only: 'true'" "$ROOT/README.md"
  grep -q 'blocking: false' "$ROOT/README.md"
  ! grep -qiE 'four-axis|four axis|precision|recall|accuracy|skilltrust\.app/ci|paid' "$ROOT/README.md"
}

@test "README: copied candidate parses and pins public input/output contracts" {
  run bash "$BATS_TEST_DIRNAME/../e2e/readme-candidate.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"readme-candidate:"*"passed"* ]]
}

@test "README: documents complete JSON artifact, boundary, hard skips, forks, and exact telemetry" {
  for text in scan-json-path actions/upload-artifact node_modules pull_request_target runner-local repo_hash telemetry:; do
    grep -qi "$text" "$ROOT/README.md"
  done
  fields="$(sed -n '/^{/,/^}/p' "$ROOT/README.md" | grep -o '^  "[a-z_]*"' | tr -d ' "' | sort)"
  expected="$(printf '%s\n' action_version delta_enabled detector_version finding_count grade repo_hash repo_visibility runner_arch runner_os trigger | sort)"
  [ "$fields" = "$expected" ]
}

@test "renderer: attribution URLs have only fixed campaign and context values" {
  grep -q 'UTM = "utm_source=github&utm_medium=scan_action&utm_campaign=free_action_launch"' "$ROOT/scripts/render.py"
  grep -q '"pr_comment"' "$ROOT/scripts/render.py"
  grep -q '"job_summary"' "$ROOT/scripts/render.py"
  [ "$(grep -c 'site_url(' "$ROOT/scripts/render.py")" -eq 3 ]
}

@test "published rule allowlist is the dated v0.10.0 catalogue" {
  ids="$(grep -v '^#' "$ROOT/config/published-rule-ids.txt")"
  expected="$(seq -f 'SD-%03g' 1 25)"
  [ "$ids" = "$expected" ]
  grep -q '2026-09-15' "$ROOT/config/published-rule-ids.txt"
  grep -q "default: 'v0.11.0'" "$ROOT/action.yml"
}

@test "release gate checks every allowlisted public page" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'SH'
#!/usr/bin/env bash
echo "${@: -1}" >> "$CURL_LOG"
printf '%s' "${FAKE_HTTP_CODE:-200}"
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export CURL_LOG="$BATS_TEST_TMPDIR/curl.log"
  run "$ROOT/tests/release/check-published-rules.sh"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CURL_LOG")" -eq 25 ]
  grep -qx 'https://skilltrust.app/rules/sd-001' "$CURL_LOG"
  grep -qx 'https://skilltrust.app/rules/sd-025' "$CURL_LOG"

  export FAKE_HTTP_CODE=404
  run "$ROOT/tests/release/check-published-rules.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"do not release"* ]]
}
