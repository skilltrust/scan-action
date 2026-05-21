#!/usr/bin/env bats

load helpers

setup() {
  setup_tmpdir
  export RUNNER_TEMP="$TMPDIR_TEST"

  # Fake skill-detector that produces deterministic output keyed on the input dir.
  cat > "$TMPDIR_TEST/skill-detector" <<'EOF'
#!/usr/bin/env bash
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
