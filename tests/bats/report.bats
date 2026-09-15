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

@test "report.sh: creates a new comment when no marker comment exists" {
  run bash "$BATS_TEST_DIRNAME/../../scripts/report.sh"
  [ "$status" -eq 0 ]
  grep -q "api repos/acme/widgets/issues/42/comments" "$FAKE_GH_LOG"
  ! grep -q "PATCH" "$FAKE_GH_LOG"
}

@test "report.sh: PATCHes existing marker comment when present" {
  export FAKE_GH_COMMENTS='[[{"id":777,"body":"<!-- skilltrust:action:v1 -->\nold"}]]'
  run bash "$BATS_TEST_DIRNAME/../../scripts/report.sh"
  [ "$status" -eq 0 ]
  grep -q "PATCH repos/acme/widgets/issues/comments/777" "$FAKE_GH_LOG"
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
  export FAKE_GH_COMMENTS='[[{"id":900,"body":"<!-- skilltrust:bot:v1 -->\napp"}],[{"id":777,"body":"<!-- skilltrust:action:v1 -->\nold"}]]'
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

@test "report.sh: 403, 429, 5xx, and network lookup failures never duplicate POST" {
  for failure in lookup-403 lookup-429 lookup-500 lookup-network; do
    : > "$FAKE_GH_LOG"
    export FAKE_GH_FAIL="$failure"
    run bash "$BATS_TEST_DIRNAME/../../scripts/report.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"comment lookup failed"* ]]
    [ "$(wc -l < "$FAKE_GH_LOG")" -eq 1 ]
    ! grep -q 'body=@' "$FAKE_GH_LOG"
  done
}

@test "report.sh: API write failures warn without failing policy" {
  export FAKE_GH_FAIL="post-403"
  run bash "$BATS_TEST_DIRNAME/../../scripts/report.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"comment creation failed"* ]]
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
