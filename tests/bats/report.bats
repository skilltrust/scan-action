#!/usr/bin/env bats

load helpers

setup() {
  setup_tmpdir
  cp "$BATS_TEST_DIRNAME/fixtures/fake-gh.sh" "$TMPDIR_TEST/gh"
  chmod +x "$TMPDIR_TEST/gh"
  export PATH="$TMPDIR_TEST:$PATH"
  export RUNNER_TEMP="$TMPDIR_TEST"
  export FAKE_GH_LOG="$TMPDIR_TEST/gh.log"
  : > "$FAKE_GH_LOG"
  echo "rendered body" > "$RUNNER_TEMP/comment.md"
  export INPUT_GITHUB_REPOSITORY="acme/widgets"
  export INPUT_PULL_NUMBER="42"
  export INPUT_HEAD_REPOSITORY="acme/widgets"
  export INPUT_BASE_REPOSITORY="acme/widgets"
  export GH_TOKEN="test-token"
  unset FAKE_GH_COMMENTS FAKE_GH_FAIL
}
teardown() { teardown_tmpdir; }

@test "report.sh: same-repo PR in a forked repository creates a new comment" {
  export INPUT_GITHUB_REPOSITORY="fork-owner/widgets"
  export INPUT_HEAD_REPOSITORY="fork-owner/widgets"
  export INPUT_BASE_REPOSITORY="fork-owner/widgets"
  run bash "$BATS_TEST_DIRNAME/../../scripts/report.sh"
  [ "$status" -eq 0 ]
  grep -q "api repos/fork-owner/widgets/issues/42/comments" "$FAKE_GH_LOG"
  ! grep -q "PATCH" "$FAKE_GH_LOG"
}

@test "report.sh: PATCHes existing marker comment when present" {
  export FAKE_GH_COMMENTS='[[{"id":777,"body":"<!-- skilltrust:action:v1 -->\nold"}]]'
  run bash "$BATS_TEST_DIRNAME/../../scripts/report.sh"
  [ "$status" -eq 0 ]
  grep -q "PATCH repos/acme/widgets/issues/comments/777" "$FAKE_GH_LOG"
}

@test "report.sh: reruns update one PR comment; another PR has its own lookup" {
  export FAKE_GH_COMMENTS='[[{"id":777,"body":"<!-- skilltrust:action:v1 -->\nold"}]]'
  for body in 'first report' 'updated report'; do
    printf '<!-- skilltrust:action:v1 -->\n%s\n' "$body" > "$RUNNER_TEMP/comment.md"
    run bash "$BATS_TEST_DIRNAME/../../scripts/report.sh"
    [ "$status" -eq 0 ]
  done
  [ "$(grep -c 'PATCH repos/acme/widgets/issues/comments/777' "$FAKE_GH_LOG")" -eq 2 ]
  [ "$(grep -c 'issues/42/comments?per_page=100' "$FAKE_GH_LOG")" -eq 2 ]
  : > "$FAKE_GH_LOG"
  export INPUT_PULL_NUMBER="43" FAKE_GH_COMMENTS='[[]]'
  run bash "$BATS_TEST_DIRNAME/../../scripts/report.sh"
  [ "$status" -eq 0 ]
  grep -q 'issues/43/comments?per_page=100' "$FAKE_GH_LOG"
  grep -q 'issues/43/comments -F body=@' "$FAKE_GH_LOG"
  ! grep -q 'PATCH\|issues/42' "$FAKE_GH_LOG"
}

@test "report.sh: compares repository identity and skips API for a true fork" {
  export INPUT_HEAD_REPOSITORY="contributor/widgets"
  run bash "$BATS_TEST_DIRNAME/../../scripts/report.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fork PR detected; printing comment to log"* ]]
  [ ! -s "$FAKE_GH_LOG" ]
}

@test "report.sh: stays silent when the SkillTrust App has already commented" {
  export FAKE_GH_COMMENTS='[[{"id":900,"body":"<!-- skilltrust:bot:v1 -->\napp"}]]'
  run bash "$BATS_TEST_DIRNAME/../../scripts/report.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"App comment present"* ]]
  ! grep -q "PATCH" "$FAKE_GH_LOG"
  ! grep -q "\-F body=@" "$FAKE_GH_LOG"
}

@test "report.sh: replaces its own comment with a superseded note when the App is present" {
  export FAKE_GH_COMMENTS='[[{"id":777,"body":"<!-- skilltrust:action:v1 -->\nold"}],[{"id":900,"body":"<!-- skilltrust:bot:v1 -->\napp"}]]'
  run bash "$BATS_TEST_DIRNAME/../../scripts/report.sh"
  [ "$status" -eq 0 ]
  grep -q "PATCH repos/acme/widgets/issues/comments/777" "$FAKE_GH_LOG"
  grep -qi "superseded" "$RUNNER_TEMP/comment.md.superseded"
  [ "$(head -n 1 "$RUNNER_TEMP/comment.md.superseded")" = "<!-- skilltrust:action:v1 -->" ]
}

@test "report.sh: posts normally when only the Action marker is around" {
  export FAKE_GH_COMMENTS='[[]]'
  run bash "$BATS_TEST_DIRNAME/../../scripts/report.sh"
  [ "$status" -eq 0 ]
  grep -q "api repos/acme/widgets/issues/42/comments" "$FAKE_GH_LOG"
  ! grep -q "PATCH" "$FAKE_GH_LOG"
}

@test "report.sh: pagination finds an Action comment on a later page" {
  export FAKE_GH_COMMENTS='[[{"id":1,"body":"ordinary"}],[{"id":888,"body":"<!-- skilltrust:action:v1 -->\nold"}]]'
  run bash "$BATS_TEST_DIRNAME/../../scripts/report.sh"
  [ "$status" -eq 0 ]
  grep -q "PATCH repos/acme/widgets/issues/comments/888" "$FAKE_GH_LOG"
  [ "$(grep -c 'issues/42/comments?per_page=100' "$FAKE_GH_LOG")" -eq 1 ]
}

@test "report.sh: safe maximum comment id remains patchable" {
  export FAKE_GH_COMMENTS='[[{"id":9007199254740991,"body":"<!-- skilltrust:action:v1 -->\nold"}]]'
  run bash "$BATS_TEST_DIRNAME/../../scripts/report.sh"
  [ "$status" -eq 0 ]
  grep -q 'PATCH repos/acme/widgets/issues/comments/9007199254740991' "$FAKE_GH_LOG"
  [ "$(grep -c 'issues/42/comments?per_page=100' "$FAKE_GH_LOG")" -eq 1 ]
}

@test "report.sh: malformed, exponent, or out-of-safe-range ids never write" {
  for response in \
    '{bad' \
    '{}' \
    '[{}]' \
    '[["not-a-comment"]]' \
    '[[{"id":1,"body":false}]]' \
    '[[{"id":"1","body":"ordinary"}]]' \
    '[[{"id":1e100,"body":"<!-- skilltrust:action:v1 -->"}]]' \
    '[[{"id":9007199254740992,"body":"<!-- skilltrust:action:v1 -->"}]]'; do
    : > "$FAKE_GH_LOG"
    export FAKE_GH_COMMENTS="$response"
    run bash "$BATS_TEST_DIRNAME/../../scripts/report.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"invalid response"* ]]
    [ "$(grep -c 'issues/42/comments?per_page=100' "$FAKE_GH_LOG")" -eq 1 ]
    [ "$(wc -l < "$FAKE_GH_LOG")" -eq 1 ]
    ! grep -q 'PATCH\|body=@' "$FAKE_GH_LOG"
  done
  run env SCAN_EXIT_CODE=2 INPUT_REPORT_ONLY=false \
    bash "$BATS_TEST_DIRNAME/../../scripts/propagate-exit.sh"
  [ "$status" -eq 2 ]
}

@test "report.sh: 403, 429, 5xx, network, and timeout lookup failures never duplicate POST" {
  for failure in lookup-403 lookup-429 lookup-500 lookup-network lookup-timeout; do
    : > "$FAKE_GH_LOG"
    export FAKE_GH_FAIL="$failure"
    run bash "$BATS_TEST_DIRNAME/../../scripts/report.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"comment lookup failed"* ]]
    [ "$(wc -l < "$FAKE_GH_LOG")" -eq 1 ]
    ! grep -q 'body=@' "$FAKE_GH_LOG"
  done
}

@test "report.sh: POST and PATCH 403, 429, 5xx, network, and timeout failures preserve Summary and policy" {
  export GITHUB_STEP_SUMMARY="$TMPDIR_TEST/summary.md"
  echo "summary survives" > "$GITHUB_STEP_SUMMARY"
  for operation in post patch; do
    for failure in 403 429 500 network timeout; do
      : > "$FAKE_GH_LOG"
      export FAKE_GH_FAIL="$operation-$failure"
      if [ "$operation" = patch ]; then
        export FAKE_GH_COMMENTS='[[{"id":777,"body":"<!-- skilltrust:action:v1 -->\nold"}]]'
      else
        export FAKE_GH_COMMENTS='[[]]'
      fi
      run bash "$BATS_TEST_DIRNAME/../../scripts/report.sh"
      [ "$status" -eq 0 ]
      [[ "$output" == *"comment "*" failed"* ]]
      grep -qx "summary survives" "$GITHUB_STEP_SUMMARY"
      run env SCAN_EXIT_CODE=2 INPUT_REPORT_ONLY=false bash "$BATS_TEST_DIRNAME/../../scripts/propagate-exit.sh"
      [ "$status" -eq 2 ]
    done
  done
}

@test "report.sh: missing token is a native warning with no API call" {
  unset GH_TOKEN
  run bash "$BATS_TEST_DIRNAME/../../scripts/report.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no writable GitHub token"* ]]
  [ ! -s "$FAKE_GH_LOG" ]
}

@test "report.sh: fork log prefixes hostile workflow commands" {
  export INPUT_HEAD_REPOSITORY="attacker/widgets"
  printf '%s\n' '::error::hostile' > "$RUNNER_TEMP/comment.md"
  run bash "$BATS_TEST_DIRNAME/../../scripts/report.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"| ::error::hostile"* ]]
  [[ "$output" != $'\n::error::hostile'* ]]
  [ ! -s "$FAKE_GH_LOG" ]
}
