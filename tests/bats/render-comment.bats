#!/usr/bin/env bats

load helpers

setup() {
  setup_tmpdir
  export RUNNER_TEMP="$TMPDIR_TEST"
  export GITHUB_STEP_SUMMARY="$TMPDIR_TEST/summary.md"
  export INPUT_SCAN_JSON="$TMPDIR_TEST/scan.json"
  export INPUT_PATH="agent config"
  export INPUT_REPORT_ONLY="true"
  export INPUT_DELTA_ENABLED="false"
  export GITHUB_EVENT_NAME="pull_request"
  export SCAN_EXIT_CODE="1"
  unset INPUT_DELTA_JSON
}
teardown() { teardown_tmpdir; }

write_scan() {
  local findings="${1:-[]}" warnings="${2:-[]}"
  jq -n --argjson findings "$findings" --argjson warnings "$warnings" '{
    findings:$findings, warnings:$warnings, files_scanned:7, version:"0.10.0",
    axes:{security:{grade:"B"},permission_hygiene:{grade:"C"},transparency:{grade:"A"},quality:{grade:"F"}}
  }' > "$INPUT_SCAN_JSON"
}

render() { run bash "$BATS_TEST_DIRNAME/../../scripts/render-comment.sh"; }

@test "safe renderer: clean result writes Summary and marker-first comment" {
  write_scan
  export SCAN_EXIT_CODE="0"
  before="$(sha256sum "$INPUT_SCAN_JSON")"
  render
  [ "$status" -eq 0 ]
  [ "$(head -n 1 "$RUNNER_TEMP/comment.md")" = "<!-- skilltrust:action:v1 -->" ]
  grep -q 'Clean — no findings' "$GITHUB_STEP_SUMMARY"
  grep -q 'Files scanned | \*\*7\*\*' "$GITHUB_STEP_SUMMARY"
  grep -q 'Scope | agent config' "$GITHUB_STEP_SUMMARY"
  grep -q 'Pull request head' "$GITHUB_STEP_SUMMARY"
  [ "$before" = "$(sha256sum "$INPUT_SCAN_JSON")" ]
}

@test "safe renderer: only three public axes are rendered; raw Quality output is untouched" {
  write_scan
  render
  grep -q '| Security | B |' "$RUNNER_TEMP/comment.md"
  grep -q '| Permission hygiene | C |' "$RUNNER_TEMP/comment.md"
  grep -q '| Transparency | A |' "$RUNNER_TEMP/comment.md"
  ! grep -q '| Quality |' "$RUNNER_TEMP/comment.md"
  [ "$(jq -r .axes.quality.grade "$INPUT_SCAN_JSON")" = F ]
}

@test "safe renderer: 10 findings show all; 11 show best 10 and exact count" {
  findings="$(jq -n '[range(1;11) | {rule_id:"SD-001",severity:"low",effective_severity:"low",file_path:"a","line":.,diagnosis:"why",remediation:"fix"}]')"
  write_scan "$findings"
  render
  [ "$(grep -c '  - Explanation:' "$RUNNER_TEMP/comment.md")" -eq 10 ]
  grep -q 'Showing 10 of 10 findings' "$RUNNER_TEMP/comment.md"

  findings="$(jq -n '[range(1;12) | {rule_id:"SD-001",severity:"low",effective_severity:"low",file_path:"a","line":.,diagnosis:"why",remediation:"fix"}]')"
  write_scan "$findings"
  render
  [ "$(grep -c '  - Explanation:' "$RUNNER_TEMP/comment.md")" -eq 10 ]
  grep -q 'Showing 10 of 11 findings' "$RUNNER_TEMP/comment.md"
}

@test "safe renderer: effective severity orders CRITICAL to INFO with stable tie-break" {
  write_scan '[
    {"rule_id":"SD-003","severity":"critical","effective_severity":"info","file_path":"z","line":1},
    {"rule_id":"SD-002","severity":"low","effective_severity":"critical","file_path":"b","line":2},
    {"rule_id":"SD-001","severity":"high","effective_severity":"critical","file_path":"a","line":3}
  ]'
  render
  ids="$(grep '^- \*\*' "$RUNNER_TEMP/comment.md" | sed -E 's/.*\[(SD-[0-9]+)\].*/\1/')"
  [ "$ids" = $'SD-001\nSD-002\nSD-003' ]
  grep -q '^\- \*\*INFO\*\*.*SD-003' "$RUNNER_TEMP/comment.md"
}

@test "safe renderer: hostile Markdown HTML links images mentions and commands are inert" {
  write_scan '[{"rule_id":"[x](https://evil.invalid/a)","severity":"critical","file_path":"</code>\n::error::boom","line":4,"diagnosis":"<img src=x onerror=alert(1)> ![p](https://evil.invalid/i) @everyone ::warning::x \u001b[2J \u202e","remediation":"<script>x</script>"}]' '["::error::warning <b>@team</b>"]'
  export INPUT_PATH='[repo](https://evil.invalid/repo) @all'
  render
  [ "$status" -eq 0 ]
  ! grep -q '<img\|<script\|<b>' "$RUNNER_TEMP/comment.md"
  ! grep -q 'https://evil.invalid' "$RUNNER_TEMP/comment.md"
  ! grep -q '@everyone\|@team\|@all' "$RUNNER_TEMP/comment.md"
  ! grep -q '^::error::\|^::warning::' "$RUNNER_TEMP/comment.md"
  grep -q '&lt;' "$RUNNER_TEMP/comment.md"
  grep -q '&#64;' "$RUNNER_TEMP/comment.md"
  python3 -c 'import sys, unicodedata; text=open(sys.argv[1], encoding="utf-8").read(); assert not any(c != "\n" and unicodedata.category(c) in {"Cc", "Cf", "Cs"} for c in text)' "$RUNNER_TEMP/comment.md"
}

@test "safe renderer: oversized text is bounded and visibly truncated" {
  long="$(printf 'x%.0s' $(seq 1 5000))"
  write_scan "$(jq -n --arg x "$long" '[{rule_id:"SD-001",severity:"high",file_path:$x,line:1,diagnosis:$x,remediation:$x}]')"
  render
  [ "$(wc -c < "$RUNNER_TEMP/comment.md")" -lt 10000 ]
  grep -q '…' "$RUNNER_TEMP/comment.md"
}

@test "safe renderer: known rule gets lowercase fixed URL; unknown stays plain" {
  write_scan '[{"rule_id":"SD-004","severity":"critical","file_path":"a","line":1},{"rule_id":"SD-099","severity":"high","file_path":"b","line":2}]'
  render
  grep -q 'https://skilltrust.app/rules/sd-004?utm_source=github&utm_medium=scan_action&utm_campaign=free_action_launch&utm_content=pr_comment' "$RUNNER_TEMP/comment.md"
  grep -q 'https://skilltrust.app/rules/sd-004?utm_source=github&utm_medium=scan_action&utm_campaign=free_action_launch&utm_content=job_summary' "$GITHUB_STEP_SUMMARY"
  ! grep -q '/rules/sd-099' "$RUNNER_TEMP/comment.md"
  grep -q 'https://skilltrust.app/docs/action?utm_source=github&utm_medium=scan_action&utm_campaign=free_action_launch&utm_content=job_summary' "$GITHUB_STEP_SUMMARY"
  grep -q 'https://skilltrust.app/docs/action?utm_source=github&utm_medium=scan_action&utm_campaign=free_action_launch&utm_content=pr_comment' "$RUNNER_TEMP/comment.md"
  ! grep -Eq 'https?://[^ )]*(acme|widgets|agent|SD-099)' "$RUNNER_TEMP/comment.md"
}

@test "safe renderer: push Summary exists without a comment delivery context" {
  write_scan
  export GITHUB_EVENT_NAME="push"
  export SCAN_EXIT_CODE="0"
  render
  grep -q 'Push checkout' "$GITHUB_STEP_SUMMARY"
  grep -q 'utm_content=job_summary' "$GITHUB_STEP_SUMMARY"
}

@test "safe renderer: empty scope has no grades" {
  cat > "$INPUT_SCAN_JSON" <<'JSON'
{"findings":[],"warnings":[],"files_scanned":0,"version":"0.10.0","no_agent_surface":true}
JSON
  export SCAN_EXIT_CODE="0"
  render
  grep -q 'Nothing was checked' "$RUNNER_TEMP/comment.md"
  ! grep -q '### Public axes\|| Security |\|| Findings' "$RUNNER_TEMP/comment.md"
}

@test "safe renderer: critical blocking outcome is explicit" {
  write_scan '[{"rule_id":"SD-001","severity":"critical","file_path":"a","line":1}]'
  export INPUT_REPORT_ONLY="false"
  export SCAN_EXIT_CODE="2"
  render
  grep -q 'Threshold reached — blocking' "$RUNNER_TEMP/comment.md"
}

@test "safe renderer: below-threshold warning policy is nonblocking" {
  write_scan '[{"rule_id":"SD-001","severity":"high","file_path":"a","line":1}]'
  export INPUT_REPORT_ONLY="false"
  export INPUT_WARN_ON_BELOW_THRESHOLD="true"
  export SCAN_EXIT_CODE="1"
  render
  grep -q '| Mode | Gate policy |' "$RUNNER_TEMP/comment.md"
  grep -q 'Findings below threshold — nonblocking' "$RUNNER_TEMP/comment.md"
}

@test "safe renderer: missing requested delta is unavailable, not zero" {
  write_scan
  export INPUT_DELTA_ENABLED="true"
  render
  grep -q 'Delta unavailable' "$RUNNER_TEMP/comment.md"
  grep -q 'head result and policy unchanged' "$RUNNER_TEMP/comment.md"
}

@test "safe renderer: resolved findings are bounded" {
  write_scan
  jq -n '{per_axis:{},new_findings:[],axis_explanations:{},resolved_findings:[range(0;11)|{rule_id:"SD-001",file_path:"a",line:.,description:"gone"}]}' > "$RUNNER_TEMP/delta.json"
  export INPUT_DELTA_JSON="$RUNNER_TEMP/delta.json"
  export INPUT_DELTA_ENABLED="true"
  render
  grep -q 'Showing 10 of 11 resolved findings' "$RUNNER_TEMP/comment.md"
}

@test "safe renderer: render failure is visible and cannot fail scan policy" {
  printf '{broken' > "$INPUT_SCAN_JSON"
  render
  [ "$status" -eq 0 ]
  grep -q 'report unavailable' "$RUNNER_TEMP/comment.md"
  grep -q 'policy.*unchanged' "$GITHUB_STEP_SUMMARY"
  [[ "$output" == *"::warning title=SkillTrust report unavailable::"* ]]
}
