#!/usr/bin/env bats

ACTION="$BATS_TEST_DIRNAME/../../action.yml"

@test "action.yml: report-only is a string boolean defaulting false" {
  awk '/^  report-only:/{seen=1} seen && /default:/{print; exit}' "$ACTION" | grep -q "default: 'false'"
}

@test "action.yml: all public outputs select the POSIX or Windows scan" {
  for name in grade scan-json-path findings-count no-agent-surface; do
    value="$(awk -v name="$name" '$0 == "  " name ":" {seen=1} seen && /value:/ {print; exit}' "$ACTION")"
    [[ "$value" == *"steps.scan.outputs.$name || steps.scan-win.outputs.$name"* ]]
  done
}

@test "action.yml: both delta branches receive only scope controls from inputs" {
  [ "$(grep -c 'INPUT_STRICT_MCP:.*inputs.strict-mcp' "$ACTION")" -eq 4 ]
  [ "$(grep -c 'INPUT_SCAN_ALL:.*inputs.scan-all' "$ACTION")" -eq 4 ]
  delta_blocks="$(sed -n '/id: delta/,/scripts\/delta.ps1/p' "$ACTION")"
  [[ "$delta_blocks" != *"INPUT_FAIL_ON"* ]]
  [[ "$delta_blocks" != *"INPUT_FAIL_ON_AXIS"* ]]
}

@test "action.yml: trusted-result guard protects every result consumer" {
  [ "$(grep -c "result-valid == 'true'" "$ACTION")" -eq 8 ]
  ! grep -q 'continue-on-error' "$ACTION"
}

@test "action.yml: final policy cannot be skipped by an earlier step outcome" {
  block="$(sed -n '/name: Propagate exit code/,$p' "$ACTION")"
  [[ "$block" == *"if: always()"* ]]
  [ "$(grep -c 'if: always()' "$ACTION")" -eq 1 ]
}

@test "action.yml: every valid completed scan renders while comments remain PR-only" {
  render_blocks="$(sed -n '/name: Render report/,/scripts\/render-comment.ps1/p' "$ACTION")"
  [[ "$render_blocks" != *"github.event_name"* ]]
  [[ "$render_blocks" != *"inputs.comment"* ]]
  [ "$(grep -c "if: runner.os.*result-valid == 'true'" "$ACTION")" -eq 2 ]
  [ "$(grep -c "if: github.event_name == 'pull_request' && inputs.comment == 'true'" "$ACTION")" -eq 2 ]
  [ "$(grep -c 'INPUT_REPORT_ONLY:.*inputs.report-only' "$ACTION")" -eq 3 ]
  [ "$(grep -c 'INPUT_DELTA_ENABLED:.*inputs.delta' "$ACTION")" -eq 4 ]
}

@test "action.yml: push and disabled switches cannot enter delta or comment delivery" {
  [ "$(grep -c "inputs.delta == 'true' && github.event_name == 'pull_request'" "$ACTION")" -eq 2 ]
  [ "$(grep -c "github.event_name == 'pull_request' && inputs.comment == 'true'" "$ACTION")" -eq 2 ]
}

@test "action.yml: fork boundary uses repository identity and withholds token" {
  [ "$(grep -c 'INPUT_HEAD_REPOSITORY:.*head.repo.full_name' "$ACTION")" -eq 2 ]
  [ "$(grep -c 'INPUT_BASE_REPOSITORY:.*base.repo.full_name' "$ACTION")" -eq 2 ]
  [ "$(grep -c 'head.repo.full_name == github.event.pull_request.base.repo.full_name && inputs.github-token' "$ACTION")" -eq 2 ]
  ! grep -q 'head.repo.fork' "$ACTION"
  ! grep -q 'pull_request_target:' "$ACTION"
}

@test "action.yml: telemetry opt-out prevents either request step" {
  [ "$(grep -c "if: inputs.telemetry == 'true'" "$ACTION")" -eq 2 ]
  [ "$(grep -c 'INPUT_ACTION_VERSION:   1.10.0' "$ACTION")" -eq 2 ]
}

@test "report scripts paginate one lookup and never blanket-swallow it" {
  for script in "$BATS_TEST_DIRNAME/../../scripts/report.sh" "$BATS_TEST_DIRNAME/../../scripts/report.ps1"; do
    grep -q -- '--paginate --slurp' "$script"
  done
  ! grep -qE 'gh api.*\|\| true' "$BATS_TEST_DIRNAME/../../scripts/report.sh"
}

@test "scripts: scan and delta do not blanket-swallow failures" {
  ! grep -R -nE '\|\|[[:space:]]+true' "$BATS_TEST_DIRNAME/../../scripts/scan.sh" \
    "$BATS_TEST_DIRNAME/../../scripts/scan.ps1" "$BATS_TEST_DIRNAME/../../scripts/delta.sh" \
    "$BATS_TEST_DIRNAME/../../scripts/delta.ps1"
}

@test "delta scripts resolve the fetched commit instead of an origin ref" {
  grep -q "FETCH_HEAD" "$BATS_TEST_DIRNAME/../../scripts/delta.sh"
  grep -q "FETCH_HEAD" "$BATS_TEST_DIRNAME/../../scripts/delta.ps1"
  ! grep -q 'origin/\$BASE_REF' "$BATS_TEST_DIRNAME/../../scripts/delta.sh"
}
