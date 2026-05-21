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
}
teardown() { teardown_tmpdir; }

@test "report.sh: creates a new comment when no marker comment exists" {
  # FAKE_GH_LIST_ID unset → fake returns nothing from listing → POST branch
  unset FAKE_GH_LIST_ID
  run bash "$BATS_TEST_DIRNAME/../../scripts/report.sh"
  [ "$status" -eq 0 ]
  grep -q "api repos/acme/widgets/issues/42/comments" "$FAKE_GH_LOG"
  ! grep -q "PATCH" "$FAKE_GH_LOG"
}

@test "report.sh: PATCHes existing marker comment when present" {
  # FAKE_GH_LIST_ID simulates the --jq filter returning just the comment id.
  # Without this, the fake would echo the full JSON list, which is non-empty
  # and would trigger the PATCH branch but with a garbled EXISTING_ID.
  export FAKE_GH_LIST_ID="777"
  run bash "$BATS_TEST_DIRNAME/../../scripts/report.sh"
  [ "$status" -eq 0 ]
  grep -q "PATCH repos/acme/widgets/issues/comments/777" "$FAKE_GH_LOG"
}

@test "report.sh: skips API call and logs warning when GITHUB_TOKEN is read-only (fork PR)" {
  export INPUT_IS_FORK_PR="true"
  run bash "$BATS_TEST_DIRNAME/../../scripts/report.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fork PR detected; printing comment to log"* ]]
  [ ! -s "$FAKE_GH_LOG" ]
}
