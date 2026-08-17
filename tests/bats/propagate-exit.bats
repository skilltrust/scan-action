#!/usr/bin/env bats

# propagate-exit.sh is the action's last step: it re-raises the exit code that
# scan.sh deferred into SCAN_EXIT_CODE. `warn-on-below-threshold` downgrades
# exactly one code — 1, "findings, all below threshold" — and nothing else.
#
# The two cases that keep this honest are 3-with-the-input-on and
# 2-with-the-input-on: a tool error means the scan never ran, and a breach is
# a breach. Both must still be non-zero with the input at its most permissive.

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

@test "propagate-exit.sh: unset SCAN_EXIT_CODE exits 0" {
  # The scan step is skipped on the OS branch that did not run; the inline
  # version this script replaced defaulted to 0 and so does it.
  run_propagate "" true
  [ "$status" -eq 0 ]
}

@test "propagate-exit.sh: an unknown future exit code passes through unchanged" {
  # Not a case statement: a code this version has never heard of must reach
  # the caller as-is rather than being guessed into 0.
  run_propagate 7 true
  [ "$status" -eq 7 ]
  [[ "$output" != *"::warning"* ]]
}
