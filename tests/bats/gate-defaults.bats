#!/usr/bin/env bats

# The gate defaults are a product decision, not an implementation detail.
# Measured on engine v0.7.0 over Set A of the MalSkillBench 906-sample slice,
# raw layout — the layout a repository scan actually sees: `fail-on: high`
# reds 75 of 300 benign repositories (FPR 0.250), `critical` reds 13
# (FPR 0.043). A gate wrong one time in four gets switched off in week one.
#
# The default is written down in three places that must agree — action.yml,
# scan.sh/scan.ps1 and propagate-exit.sh. action.yml is the source of truth;
# the script fallbacks mirror it. These cases read action.yml and pin all
# three, so a silent divergence fails here rather than on a user's runner.

load helpers

ACTION_YML() { echo "$BATS_TEST_DIRNAME/../../action.yml"; }

# Prints the `default:` value of a named top-level input block in action.yml.
input_default() {
  local value
  value="$(awk -v name="$1" '
    $0 == "  " name ":" { inb = 1; next }
    inb && /^  [a-z][a-z0-9-]*:$/ { inb = 0 }
    inb && /^    default:/ { sub(/^    default:[ \t]*/, ""); print; exit }
  ' "$(ACTION_YML)" | tr -d "'\"")"
  if [ -z "$value" ]; then
    echo "input_default: no default found for input '$1' in action.yml" >&2
    return 1
  fi
  printf '%s' "$value"
}

# Prints the `description:` block of a named top-level input, folded to one line.
input_description() {
  awk -v name="$1" '
    $0 == "  " name ":" { inb = 1; next }
    inb && /^  [a-z][a-z0-9-]*:$/ { inb = 0 }
    inb && /^    description:/ { ind = 1; sub(/^    description:[ \t>|+-]*/, ""); printf "%s ", $0; next }
    inb && ind && /^      / { sub(/^ +/, ""); printf "%s ", $0; next }
    inb && ind { exit }
  ' "$(ACTION_YML)"
}

setup() {
  setup_tmpdir
  cp "$BATS_TEST_DIRNAME/fixtures/fake-detector.sh" "$TMPDIR_TEST/skill-detector"
  chmod +x "$TMPDIR_TEST/skill-detector"
  export PATH="$TMPDIR_TEST:$PATH"
  export RUNNER_TEMP="$TMPDIR_TEST"
  : > "$TMPDIR_TEST/github_env";    export GITHUB_ENV="$TMPDIR_TEST/github_env"
  : > "$TMPDIR_TEST/github_output"; export GITHUB_OUTPUT="$TMPDIR_TEST/github_output"
}
teardown() { teardown_tmpdir; }

# Records the argv the scanner was called with, so the --fail-on flag that
# actually reaches the engine is assertable rather than inferred.
recording_detector() {
  cat > "$TMPDIR_TEST/skill-detector" <<EOF
#!/usr/bin/env bash
echo "\$*" > "$TMPDIR_TEST/args.txt"
echo '{"findings":[],"axes":{},"files_scanned":0,"rules_applied":24}'
EOF
  chmod +x "$TMPDIR_TEST/skill-detector"
}

# --- action.yml is the source of truth --------------------------------------

@test "action.yml: fail-on defaults to critical" {
  [ "$(input_default fail-on)" = "critical" ]
}

@test "action.yml: warn-on-below-threshold defaults to true" {
  [ "$(input_default warn-on-below-threshold)" = "true" ]
}

@test "action.yml: the fail-on description carries the measured reason, not just the mechanics" {
  # Done-when in the spec: the description must state WHY, with the numbers.
  # If the measurement is ever redone, this case is meant to be updated with
  # it — not deleted.
  # Re-measured on engine v0.9.0 (was 0.370 on v0.8.0): the SD-003
  # in-package-`../` fix removed one benign false positive at `high`.
  # `critical`, the actual default, is unchanged.
  # Re-verified on v0.10.0 and unchanged: that release widens SD-004 to
  # `$HOME/`-spelled credential paths, and the 906-sample run is identical
  # in every measured field before and after — no sample in this pool
  # spells a credential path that way.
  desc="$(input_description fail-on)"
  [[ "$desc" == *"0.367"* ]]
  [[ "$desc" == *"0.067"* ]]
}

@test "action.yml: the warn-on-below-threshold description explains the default, not just the switch" {
  desc="$(input_description warn-on-below-threshold)"
  [[ "$desc" == *"below"* ]]
  [[ "$desc" == *"warning"* ]]
}

# --- scan.sh mirrors it ------------------------------------------------------

@test "scan.sh: an unset INPUT_FAIL_ON falls back to critical, matching action.yml" {
  recording_detector
  run env -u INPUT_FAIL_ON \
    INPUT_PATH="." INPUT_FAIL_ON_AXIS="" INPUT_STRICT_MCP="false" INPUT_SCAN_ALL="false" \
    RUNNER_TEMP="$RUNNER_TEMP" GITHUB_ENV="$GITHUB_ENV" GITHUB_OUTPUT="$GITHUB_OUTPUT" \
    PATH="$PATH" bash "$BATS_TEST_DIRNAME/../../scripts/scan.sh"
  [ "$status" -eq 0 ]
  grep -q -- "--fail-on critical" "$TMPDIR_TEST/args.txt"
  [ "$(input_default fail-on)" = "critical" ]
}

@test "scan.sh: action.yml's default reaches the engine as --fail-on critical" {
  recording_detector
  # A bare assignment, not `env VAR="$(...)"`: under `set -e`, a command
  # substitution's failure is only propagated by the former. `env
  # INPUT_FAIL_ON="$(input_default fail-on)" ...` would swallow
  # input_default's `return 1` and hand env an empty string, which scan.sh's
  # own `${INPUT_FAIL_ON:-critical}` fallback then silently repairs to the
  # same value this case expects — a vacuous pass exactly when the awk it is
  # meant to catch is broken.
  local want
  want="$(input_default fail-on)"
  run env INPUT_FAIL_ON="$want" \
    INPUT_PATH="." INPUT_FAIL_ON_AXIS="" INPUT_STRICT_MCP="false" INPUT_SCAN_ALL="false" \
    RUNNER_TEMP="$RUNNER_TEMP" GITHUB_ENV="$GITHUB_ENV" GITHUB_OUTPUT="$GITHUB_OUTPUT" \
    PATH="$PATH" bash "$BATS_TEST_DIRNAME/../../scripts/scan.sh"
  [ "$status" -eq 0 ]
  grep -q -- "--fail-on critical" "$TMPDIR_TEST/args.txt"
}

@test "scan.sh: an explicit fail-on: high still reaches the engine unchanged" {
  # The stricter posture stays available; the change is which one you get
  # without asking.
  recording_detector
  run env INPUT_FAIL_ON="high" \
    INPUT_PATH="." INPUT_FAIL_ON_AXIS="" INPUT_STRICT_MCP="false" INPUT_SCAN_ALL="false" \
    RUNNER_TEMP="$RUNNER_TEMP" GITHUB_ENV="$GITHUB_ENV" GITHUB_OUTPUT="$GITHUB_OUTPUT" \
    PATH="$PATH" bash "$BATS_TEST_DIRNAME/../../scripts/scan.sh"
  [ "$status" -eq 0 ]
  grep -q -- "--fail-on high" "$TMPDIR_TEST/args.txt"
}

# --- scan.ps1 mirrors it too, and bats cannot execute it to check -----------

@test "scan.ps1: the PowerShell fallback matches action.yml, which bats cannot execute" {
  # bats never runs pwsh, and parse-all-ps1.sh only parses — a wrong literal
  # here is invisible to both. ADR-0002's "change one, change both" needs a
  # check that does not depend on executing the .ps1 half. Bare assignment
  # (see the scan.sh case above) so a broken input_default fails loudly
  # rather than being swallowed under `set -e`.
  local want
  want="$(input_default fail-on)"
  grep -qF "else { \"$want\" }" "$BATS_TEST_DIRNAME/../../scripts/scan.ps1"
}

# --- propagate-exit.sh mirrors it -------------------------------------------

@test "propagate-exit.sh: an unset warn input falls back to true, matching action.yml" {
  run env -u INPUT_WARN_ON_BELOW_THRESHOLD \
    SCAN_EXIT_CODE=1 INPUT_GRADE="C" INPUT_FINDINGS_COUNT="1" \
    bash "$BATS_TEST_DIRNAME/../../scripts/propagate-exit.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning title=SkillTrust::"* ]]
  [ "$(input_default warn-on-below-threshold)" = "true" ]
}

@test "propagate-exit.sh: under action.yml's defaults, a below-threshold finding warns and passes" {
  # Same reasoning as scan.sh's default case above: a bare assignment so
  # input_default's failure can't be swallowed by `env VAR="$(...)"` under
  # `set -e`, which would otherwise hand propagate-exit.sh an empty string
  # that its own `${INPUT_WARN_ON_BELOW_THRESHOLD:-true}` fallback repairs to
  # the very value being asserted.
  local want
  want="$(input_default warn-on-below-threshold)"
  run env INPUT_WARN_ON_BELOW_THRESHOLD="$want" \
    SCAN_EXIT_CODE=1 INPUT_GRADE="C" INPUT_FINDINGS_COUNT="1" \
    bash "$BATS_TEST_DIRNAME/../../scripts/propagate-exit.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"below your fail-on threshold"* ]]
}

@test "propagate-exit.sh: under action.yml's defaults, a threshold breach still fails" {
  # The new default softens exit 1 only. A CRITICAL finding is exit 2 and
  # must still red the build with nobody having configured anything.
  # Bare assignment (see the below-threshold case above) so a broken
  # input_default fails loudly instead of "under action.yml's defaults"
  # silently becoming "under propagate-exit.sh's own fallback".
  local want
  want="$(input_default warn-on-below-threshold)"
  run env INPUT_WARN_ON_BELOW_THRESHOLD="$want" \
    SCAN_EXIT_CODE=2 INPUT_GRADE="F" INPUT_FINDINGS_COUNT="1" \
    bash "$BATS_TEST_DIRNAME/../../scripts/propagate-exit.sh"
  [ "$status" -eq 2 ]
  [[ "$output" != *"::warning"* ]]
}

@test "propagate-exit.sh: under action.yml's defaults, a tool error still fails" {
  # Bare assignment, same reasoning as the two cases above.
  local want
  want="$(input_default warn-on-below-threshold)"
  run env INPUT_WARN_ON_BELOW_THRESHOLD="$want" \
    SCAN_EXIT_CODE=3 \
    bash "$BATS_TEST_DIRNAME/../../scripts/propagate-exit.sh"
  [ "$status" -eq 3 ]
}

# --- the below-threshold annotation's tail is event-aware -------------------
# The PR-comment steps in action.yml only run on `pull_request`; a push build
# has no comment to point at, so the annotation must not tell it to look for
# one.

@test "propagate-exit.sh: on a pull_request run, the below-threshold annotation points at the PR comment" {
  run env GITHUB_EVENT_NAME=pull_request \
    SCAN_EXIT_CODE=1 INPUT_WARN_ON_BELOW_THRESHOLD=true INPUT_GRADE="C" INPUT_FINDINGS_COUNT="1" \
    bash "$BATS_TEST_DIRNAME/../../scripts/propagate-exit.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"below your fail-on threshold"* ]]
  [[ "$output" == *"review the PR comment"* ]]
}

@test "propagate-exit.sh: on a push run, the below-threshold annotation points at the job log, not a PR comment that will not exist" {
  run env GITHUB_EVENT_NAME=push \
    SCAN_EXIT_CODE=1 INPUT_WARN_ON_BELOW_THRESHOLD=true INPUT_GRADE="C" INPUT_FINDINGS_COUNT="1" \
    bash "$BATS_TEST_DIRNAME/../../scripts/propagate-exit.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"below your fail-on threshold"* ]]
  [[ "$output" != *"PR comment"* ]]
  [[ "$output" == *"job log"* ]]
}
