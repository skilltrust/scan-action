#!/usr/bin/env bats

load helpers

setup() {
  setup_tmpdir
  export RUNNER_TEMP="$TMPDIR_TEST"

  # Fake skill-detector that produces deterministic output keyed on the input dir,
  # and records every argument list it was called with (one line per call).
  # $TMPDIR_TEST is inherited at run time (exported by setup_tmpdir), so the
  # heredoc stays quoted and nothing here expands at generation time.
  cat > "$TMPDIR_TEST/skill-detector" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "$TMPDIR_TEST/skill-detector-args.log"
case "$1" in
  scan)
    if [[ "$2" == *base* ]]; then
      echo '{"axes":{"security":{"grade":"A"}},"findings":[],"version":"0.3.1"}'
    else
      echo '{"axes":{"security":{"grade":"B"}},"findings":[],"version":"0.3.1"}'
    fi
    ;;
  delta)
    # Reads two JSON files; emits a delta JSON. Use jq if available; here just emit fixed output.
    cat <<JSON
{
  "per_axis": {"security": {"Old":"A","New":"B","Direction":"down"}},
  "new_findings": [],
  "resolved_findings": [],
  "axis_explanations": {}
}
JSON
    ;;
esac
EOF
  chmod +x "$TMPDIR_TEST/skill-detector"
  export PATH="$TMPDIR_TEST:$PATH"

  # Fake git that simulates fetch + worktree add.
  mkdir -p "$TMPDIR_TEST/fake-bin"
  cat > "$TMPDIR_TEST/fake-bin/git" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  fetch)        exit 0 ;;
  worktree)     mkdir -p "$4" ; echo "fixture base content" > "$4/marker"; exit 0 ;;
  rev-parse)    echo "abc123" ;;
  *)            command /usr/bin/git "$@" 2>/dev/null || exit 0 ;;
esac
EOF
  chmod +x "$TMPDIR_TEST/fake-bin/git"
  export PATH="$TMPDIR_TEST/fake-bin:$PATH"

  : > "$TMPDIR_TEST/github_env"
  export GITHUB_ENV="$TMPDIR_TEST/github_env"
}
teardown() { teardown_tmpdir; }

@test "delta.sh: produces delta.json with per_axis content" {
  export INPUT_BASE_REF="main"
  export INPUT_HEAD_SCAN_JSON="$RUNNER_TEMP/scan.json"
  # Pre-create head scan
  echo '{"axes":{"security":{"grade":"B"}},"findings":[],"version":"0.3.1"}' > "$INPUT_HEAD_SCAN_JSON"
  run bash "$BATS_TEST_DIRNAME/../../scripts/delta.sh"
  [ "$status" -eq 0 ]
  [ -f "$RUNNER_TEMP/delta.json" ]
  grep -q '"per_axis"' "$RUNNER_TEMP/delta.json"
}

@test "delta.sh: threads --strict-mcp into the base scan when set" {
  export INPUT_BASE_REF="main"
  export INPUT_HEAD_SCAN_JSON="$RUNNER_TEMP/scan.json"
  export INPUT_STRICT_MCP="true"
  echo '{"axes":{"security":{"grade":"B"}},"findings":[],"version":"0.3.1"}' > "$INPUT_HEAD_SCAN_JSON"
  run bash "$BATS_TEST_DIRNAME/../../scripts/delta.sh"
  [ "$status" -eq 0 ]
  grep -q -- "--strict-mcp" "$TMPDIR_TEST/skill-detector-args.log"
}

@test "delta.sh: threads --scan-all into the base scan when set" {
  export INPUT_BASE_REF="main"
  export INPUT_HEAD_SCAN_JSON="$RUNNER_TEMP/scan.json"
  export INPUT_SCAN_ALL="true"
  echo '{"axes":{"security":{"grade":"B"}},"findings":[],"version":"0.3.1"}' > "$INPUT_HEAD_SCAN_JSON"
  run bash "$BATS_TEST_DIRNAME/../../scripts/delta.sh"
  [ "$status" -eq 0 ]
  grep -q -- "--scan-all" "$TMPDIR_TEST/skill-detector-args.log"
}

@test "delta.sh: passes neither flag when INPUT_STRICT_MCP/INPUT_SCAN_ALL are unset" {
  export INPUT_BASE_REF="main"
  export INPUT_HEAD_SCAN_JSON="$RUNNER_TEMP/scan.json"
  unset INPUT_STRICT_MCP INPUT_SCAN_ALL
  echo '{"axes":{"security":{"grade":"B"}},"findings":[],"version":"0.3.1"}' > "$INPUT_HEAD_SCAN_JSON"
  run bash "$BATS_TEST_DIRNAME/../../scripts/delta.sh"
  [ "$status" -eq 0 ]
  ! grep -q -- "--strict-mcp" "$TMPDIR_TEST/skill-detector-args.log"
  ! grep -q -- "--scan-all" "$TMPDIR_TEST/skill-detector-args.log"
}
