#!/usr/bin/env bats

# propagate-exit.sh is the action's last step: it re-raises the exit code that
# scan.sh deferred into SCAN_EXIT_CODE. `warn-on-below-threshold` downgrades
# exactly one code — 1, "findings, all below threshold" — and nothing else.
#
# The two cases that keep this honest are 3-with-the-input-on and
# 2-with-the-input-on: a tool error means the scan never ran, and a breach is
# a breach. Both must still be non-zero with the input at its most permissive.

bats_require_minimum_version 1.5.0
load helpers

SCRIPT() { echo "$BATS_TEST_DIRNAME/../../scripts/propagate-exit.sh"; }

run_propagate() {
  # $1 = SCAN_EXIT_CODE (empty string means: leave it unset)
  # $2 = INPUT_WARN_ON_BELOW_THRESHOLD
  if [ -z "$1" ]; then
    run env -u SCAN_EXIT_CODE \
      INPUT_WARN_ON_BELOW_THRESHOLD="$2" \
      INPUT_GRADE="C" INPUT_FINDINGS_COUNT="4" \
      bash "$(SCRIPT)"
  else
    run env SCAN_EXIT_CODE="$1" \
      INPUT_WARN_ON_BELOW_THRESHOLD="$2" \
      INPUT_GRADE="C" INPUT_FINDINGS_COUNT="4" \
      bash "$(SCRIPT)"
  fi
}

# --- input off: pure passthrough, the pre-F-05 behavior --------------------

@test "propagate-exit.sh: exit 0 stays 0 with warn-on-below-threshold off" {
  run_propagate 0 false
  [ "$status" -eq 0 ]
  [[ "$output" != *"::warning"* ]]
}

@test "propagate-exit.sh: exit 1 fails the build with warn-on-below-threshold off" {
  run_propagate 1 false
  [ "$status" -eq 1 ]
  [[ "$output" != *"::warning"* ]]
}

@test "propagate-exit.sh: exit 2 fails the build with warn-on-below-threshold off" {
  run_propagate 2 false
  [ "$status" -eq 2 ]
}

@test "propagate-exit.sh: exit 3 fails the build with warn-on-below-threshold off" {
  run_propagate 3 false
  [ "$status" -eq 3 ]
}

# --- input on: only 1 changes ----------------------------------------------

@test "propagate-exit.sh: exit 0 stays 0 with warn-on-below-threshold on" {
  run_propagate 0 true
  [ "$status" -eq 0 ]
  [[ "$output" != *"::warning"* ]]
}

@test "propagate-exit.sh: exit 1 becomes a warning annotation and exit 0 with warn-on-below-threshold on" {
  run_propagate 1 true
  [ "$status" -eq 0 ]
  # The annotation itself is the feature — asserting only the status would
  # pass against a script that silently swallowed the code.
  [[ "$output" == *"::warning title=SkillTrust::"* ]]
  [[ "$output" == *"4 finding(s)"* ]]
  [[ "$output" == *"grade C"* ]]
  [[ "$output" == *"below your fail-on threshold"* ]]
  # One line, not a block.
  [ "$(printf '%s\n' "$output" | grep -c '::warning')" -eq 1 ]
}

@test "propagate-exit.sh: exit 2 still fails with warn-on-below-threshold on" {
  # At/above threshold is a real breach; the input is about below-threshold
  # findings only.
  run_propagate 2 true
  [ "$status" -eq 2 ]
  [[ "$output" != *"::warning"* ]]
}

@test "propagate-exit.sh: exit 3 still fails with warn-on-below-threshold on" {
  # Tool error: the scan did not run. A scan that could not run is not a
  # passing scan — this must never be downgraded, whatever the input says.
  run_propagate 3 true
  [ "$status" -eq 3 ]
  [[ "$output" != *"::warning"* ]]
}

# --- edges ------------------------------------------------------------------

@test "propagate-exit.sh: unset SCAN_EXIT_CODE is a result failure" {
  run_propagate "" true
  [ "$status" -eq 3 ]
  [[ "$output" == *"did not publish"* ]]
}

@test "report-only downgrades findings exits 1 and 2, but not errors" {
  for code in 1 2; do
    SCAN_EXIT_CODE="$code" INPUT_REPORT_ONLY=true run "$(SCRIPT)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"findings retained"* ]]
  done
  for code in 3 42 127; do
    if [ "$code" -eq 127 ]; then
      SCAN_EXIT_CODE="$code" INPUT_REPORT_ONLY=true run -127 "$(SCRIPT)"
    else
      SCAN_EXIT_CODE="$code" INPUT_REPORT_ONLY=true run "$(SCRIPT)"
    fi
    [ "$status" -eq "$code" ]
  done
}

@test "report-only false preserves legacy 0/1/2 policy" {
  SCAN_EXIT_CODE=0 INPUT_REPORT_ONLY=false run "$(SCRIPT)"
  [ "$status" -eq 0 ]
  SCAN_EXIT_CODE=1 INPUT_REPORT_ONLY=false INPUT_WARN_ON_BELOW_THRESHOLD=false run "$(SCRIPT)"
  [ "$status" -eq 1 ]
  SCAN_EXIT_CODE=2 INPUT_REPORT_ONLY=false run "$(SCRIPT)"
  [ "$status" -eq 2 ]
}

@test "complete report-only truth table preserves 0/1/2/3/42/127 contracts" {
  for row in \
    'false 0 0' 'false 1 1' 'false 2 2' 'false 3 3' 'false 42 42' 'false 127 127' \
    'true 0 0' 'true 1 0' 'true 2 0' 'true 3 3' 'true 42 42' 'true 127 127'; do
    read -r mode code expected <<< "$row"
    if [ "$expected" -eq 127 ]; then
      run -127 env SCAN_EXIT_CODE="$code" INPUT_REPORT_ONLY="$mode" \
        INPUT_WARN_ON_BELOW_THRESHOLD=false "$(SCRIPT)"
    else
      run env SCAN_EXIT_CODE="$code" INPUT_REPORT_ONLY="$mode" \
        INPUT_WARN_ON_BELOW_THRESHOLD=false "$(SCRIPT)"
    fi
    [ "$status" -eq "$expected" ]
  done
}

@test "fail-on-no-agent-surface is independent of report-only" {
  SCAN_EXIT_CODE=0 INPUT_NO_AGENT_SURFACE=true INPUT_REPORT_ONLY=true \
    INPUT_FAIL_ON_NO_AGENT_SURFACE=true run "$(SCRIPT)"
  [ "$status" -eq 2 ]
}

@test "invalid string boolean is an input failure" {
  SCAN_EXIT_CODE=2 INPUT_REPORT_ONLY=yes run "$(SCRIPT)"
  [ "$status" -eq 3 ]
}

@test "propagate-exit.sh: an unknown future exit code passes through unchanged" {
  # Not a case statement: a code this version has never heard of must reach
  # the caller as-is rather than being guessed into 0.
  run_propagate 7 true
  [ "$status" -eq 7 ]
  [[ "$output" != *"::warning"* ]]
}

# --- no_agent_surface: the exit code is the withdrawn claim -----------------

@test "no-agent-surface warns and exits 0 by default" {
  SCAN_EXIT_CODE=0 INPUT_NO_AGENT_SURFACE=true \
    run "$BATS_TEST_DIRNAME/../../scripts/propagate-exit.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning"* ]]
  [[ "$output" == *"nothing was checked"* ]]
}

@test "no-agent-surface fails when the input asks it to" {
  SCAN_EXIT_CODE=0 INPUT_NO_AGENT_SURFACE=true INPUT_FAIL_ON_NO_AGENT_SURFACE=true \
    run "$BATS_TEST_DIRNAME/../../scripts/propagate-exit.sh"
  [ "$status" -eq 2 ]
}

@test "a real breach still fails even with fail-on-no-agent-surface on" {
  SCAN_EXIT_CODE=2 INPUT_NO_AGENT_SURFACE=false INPUT_FAIL_ON_NO_AGENT_SURFACE=true \
    run "$BATS_TEST_DIRNAME/../../scripts/propagate-exit.sh"
  [ "$status" -eq 2 ]
}

@test "no-agent-surface never downgrades a real breach (exit 2), fail-on off" {
  SCAN_EXIT_CODE=2 INPUT_NO_AGENT_SURFACE=true INPUT_FAIL_ON_NO_AGENT_SURFACE=false \
    run "$BATS_TEST_DIRNAME/../../scripts/propagate-exit.sh"
  [ "$status" -eq 2 ]
}

@test "no-agent-surface never downgrades a real breach (exit 2), fail-on on" {
  SCAN_EXIT_CODE=2 INPUT_NO_AGENT_SURFACE=true INPUT_FAIL_ON_NO_AGENT_SURFACE=true \
    run "$BATS_TEST_DIRNAME/../../scripts/propagate-exit.sh"
  [ "$status" -eq 2 ]
}

@test "no-agent-surface never downgrades a tool error (exit 3), fail-on off" {
  SCAN_EXIT_CODE=3 INPUT_NO_AGENT_SURFACE=true INPUT_FAIL_ON_NO_AGENT_SURFACE=false \
    run "$BATS_TEST_DIRNAME/../../scripts/propagate-exit.sh"
  [ "$status" -eq 3 ]
}

@test "no-agent-surface never downgrades a tool error (exit 3), fail-on on" {
  SCAN_EXIT_CODE=3 INPUT_NO_AGENT_SURFACE=true INPUT_FAIL_ON_NO_AGENT_SURFACE=true \
    run "$BATS_TEST_DIRNAME/../../scripts/propagate-exit.sh"
  [ "$status" -eq 3 ]
}
