#!/usr/bin/env bats

load helpers

setup() {
  setup_tmpdir
  export RUNNER_TEMP="$TMPDIR_TEST"
}
teardown() { teardown_tmpdir; }

@test "render-comment.sh: renders head-only comment with axis rows" {
  cat > "$RUNNER_TEMP/scan.json" <<EOF
{
  "axes": {
    "security":           {"grade": "B"},
    "permission_hygiene": {"grade": "D"},
    "transparency":       {"grade": "C"},
    "quality":            {"grade": "A"}
  },
  "findings": [
    {"rule_id":"SD-014","severity":"high","axis":"permission_hygiene","file_path":".claude/settings.json","line":3,"description":"wildcard bash"}
  ],
  "version": "0.2.1"
}
EOF
  export INPUT_SCAN_JSON="$RUNNER_TEMP/scan.json"
  run bash "$BATS_TEST_DIRNAME/../../scripts/render-comment.sh"
  [ "$status" -eq 0 ]
  [ -f "$RUNNER_TEMP/comment.md" ]
  grep -q "<!-- skilltrust:action:v1 -->" "$RUNNER_TEMP/comment.md"
  grep -q "Trust Score \*\*D\*\*"        "$RUNNER_TEMP/comment.md"
  grep -q "SD-014"                       "$RUNNER_TEMP/comment.md"
  grep -q "permission_hygiene"           "$RUNNER_TEMP/comment.md"
}

@test "render-comment.sh: renders no-findings shape when findings empty" {
  cat > "$RUNNER_TEMP/scan.json" <<EOF
{"axes":{"security":{"grade":"A"}},"findings":[],"version":"0.2.1"}
EOF
  export INPUT_SCAN_JSON="$RUNNER_TEMP/scan.json"
  run bash "$BATS_TEST_DIRNAME/../../scripts/render-comment.sh"
  [ "$status" -eq 0 ]
  grep -q "_No findings._" "$RUNNER_TEMP/comment.md"
}
