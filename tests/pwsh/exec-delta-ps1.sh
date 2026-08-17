#!/usr/bin/env bash
# Executes scripts/delta.ps1 for real, inside the mcr.microsoft.com/powershell
# container — not just [Parser]::ParseFile, which only proves the file is
# syntactically valid and says nothing about whether native-command argument
# passing (e.g. `skill-detector $scanArgs`) does what the bash sibling does.
# `report.ps1` shipped a ParserError for three releases because bats covers
# bash only and nothing ever executed the PowerShell half; this script exists
# so that class of bug has an execution check, not just a parse check.
#
# Requires Docker. Not wired into ci.yml: CI has no job that runs delta.ps1
# on any OS today (the Windows smoke matrix only runs scan.ps1/report.ps1
# with comment:false, and delta only runs via smoke-pr-delta, which is
# ubuntu-only). Wiring this into CI is a separate decision — this script is
# for local/manual verification of scripts/delta.ps1 changes until someone
# makes that call.
#
# Usage: ./tests/pwsh/exec-delta-ps1.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

HARNESS="$(mktemp)"
cat > "$HARNESS" <<'HARNESS_EOF'
set -euo pipefail
FAKEBIN=/fakebin
mkdir -p "$FAKEBIN"

# Fake skill-detector: logs each argv element on its own line as ARG[i]=<...>,
# with a "---" separator per invocation, then emits canned JSON so delta.ps1's
# downstream steps (Out-File, the delta call) don't blow up. Per-argument,
# index-tagged logging is deliberate: it is the only way to tell "each flag
# arrived as its own argument" apart from "PowerShell collapsed the array
# into one string" from the outside.
cat > "$FAKEBIN/skill-detector" <<'EOF'
#!/usr/bin/env bash
i=0
for a in "$@"; do
  echo "ARG[$i]=<$a>" >> "$ARGS_LOG"
  i=$((i+1))
done
echo "---" >> "$ARGS_LOG"
case "$1" in
  scan)
    echo '{"axes":{"security":{"grade":"A"}},"findings":[],"version":"0.3.1"}'
    ;;
  delta)
    cat <<'JSON'
{"per_axis":{"security":{"Old":"A","New":"B","Direction":"down"}},"new_findings":[],"resolved_findings":[],"axis_explanations":{}}
JSON
    ;;
esac
EOF
chmod +x "$FAKEBIN/skill-detector"

# Fake git: same shape as tests/bats/delta.bats' setup().
cat > "$FAKEBIN/git" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  fetch)     exit 0 ;;
  worktree)  mkdir -p "$4"; echo "fixture base content" > "$4/marker"; exit 0 ;;
  rev-parse) echo "abc123" ;;
  *)         exit 0 ;;
esac
EOF
chmod +x "$FAKEBIN/git"

export PATH="$FAKEBIN:$PATH"

# RUNNER_TEMP deliberately contains a space: this repo is checked out under a
# directory named "skil security", so a space in RUNNER_TEMP is the normal
# case here, not a contrived one. If native-arg splitting is ever wrong, this
# is what catches it — $baseTarget would come out as two ARG[] entries
# instead of one.
run_case() {
  local label="$1" strict="$2" scanall="$3"
  local rtemp="/tmp/skil security/rtemp-$label"
  mkdir -p "$rtemp"
  local args_log="$rtemp/skill-detector-args.log"
  : > "$args_log"
  echo '{"axes":{"security":{"grade":"B"}},"findings":[],"version":"0.3.1"}' > "$rtemp/scan.json"

  env -i PATH="$PATH" HOME="$HOME" \
    RUNNER_TEMP="$rtemp" \
    INPUT_BASE_REF="main" \
    INPUT_HEAD_SCAN_JSON="$rtemp/scan.json" \
    INPUT_STRICT_MCP="$strict" \
    INPUT_SCAN_ALL="$scanall" \
    ARGS_LOG="$args_log" \
    pwsh -NoProfile -File "/w/scripts/delta.ps1"
  local status=$?

  echo "==== case $label (strict=$strict scan_all=$scanall) exit=$status ===="
  cat "$args_log"
  echo

  # scan call must be the first block and must contain --strict-mcp / --scan-all
  # as their own ARG[] line iff the matching input was "true", never otherwise.
  local scan_block
  scan_block="$(sed -n '1,/^---$/p' "$args_log")"
  if [ "$strict" = "true" ]; then
    grep -qxF -- 'ARG[4]=<--strict-mcp>' <<< "$scan_block" || { echo "FAIL: $label missing --strict-mcp as its own arg" >&2; exit 1; }
  else
    grep -q -- '--strict-mcp' <<< "$scan_block" && { echo "FAIL: $label unexpectedly threaded --strict-mcp" >&2; exit 1; }
  fi
  if [ "$scanall" = "true" ]; then
    grep -q -- '<--scan-all>' <<< "$scan_block" || { echo "FAIL: $label missing --scan-all as its own arg" >&2; exit 1; }
  else
    grep -q -- '--scan-all' <<< "$scan_block" && { echo "FAIL: $label unexpectedly threaded --scan-all" >&2; exit 1; }
  fi
  # base target (ARG[1]) must survive as one argument despite the space.
  grep -q -- "ARG\[1\]=</tmp/skil security/rtemp-$label/skilltrust-base-worktree>" <<< "$scan_block" \
    || { echo "FAIL: $label base target did not survive as a single argument" >&2; exit 1; }
}

run_case "strict-mcp" "true" "false"
run_case "scan-all" "false" "true"
run_case "neither" "false" "false"

echo "ALL CASES PASSED"
HARNESS_EOF

docker run --rm \
  -v "$ROOT:/w:ro" \
  -v "$HARNESS:/harness.sh:ro" \
  mcr.microsoft.com/powershell:latest \
  bash /harness.sh
