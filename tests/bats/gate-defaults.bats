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
  awk -v name="$1" '
    $0 == "  " name ":" { inb = 1; next }
    inb && /^  [a-z][a-z0-9-]*:$/ { inb = 0 }
    inb && /^    default:/ { sub(/^    default:[ \t]*/, ""); print; exit }
  ' "$(ACTION_YML)" | tr -d "'\""
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
  desc="$(input_description fail-on)"
  [[ "$desc" == *"0.250"* ]]
  [[ "$desc" == *"0.043"* ]]
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
  run env INPUT_FAIL_ON="$(input_default fail-on)" \
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
  run env INPUT_WARN_ON_BELOW_THRESHOLD="$(input_default warn-on-below-threshold)" \
    SCAN_EXIT_CODE=1 INPUT_GRADE="C" INPUT_FINDINGS_COUNT="1" \
    bash "$BATS_TEST_DIRNAME/../../scripts/propagate-exit.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"below your fail-on threshold"* ]]
}

@test "propagate-exit.sh: under action.yml's defaults, a threshold breach still fails" {
  # The new default softens exit 1 only. A CRITICAL finding is exit 2 and
  # must still red the build with nobody having configured anything.
  run env INPUT_WARN_ON_BELOW_THRESHOLD="$(input_default warn-on-below-threshold)" \
    SCAN_EXIT_CODE=2 INPUT_GRADE="F" INPUT_FINDINGS_COUNT="1" \
    bash "$BATS_TEST_DIRNAME/../../scripts/propagate-exit.sh"
  [ "$status" -eq 2 ]
  [[ "$output" != *"::warning"* ]]
}

@test "propagate-exit.sh: under action.yml's defaults, a tool error still fails" {
  run env INPUT_WARN_ON_BELOW_THRESHOLD="$(input_default warn-on-below-threshold)" \
    SCAN_EXIT_CODE=3 \
    bash "$BATS_TEST_DIRNAME/../../scripts/propagate-exit.sh"
  [ "$status" -eq 3 ]
}
