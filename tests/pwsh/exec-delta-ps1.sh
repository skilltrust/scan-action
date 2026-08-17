#!/usr/bin/env bash
# Executes scripts/delta.ps1 for real — not just [Parser]::ParseFile, which
# only proves the file is syntactically valid and says nothing about whether
# native-command argument passing (e.g. `skill-detector $scanArgs`) does what
# the bash sibling does. `report.ps1` shipped a ParserError for three releases
# because bats covers bash only and nothing ever executed the PowerShell half;
# this script exists so that class of bug has an execution check, not just a
# parse check.
#
# Two modes, same assertions:
#   direct — `pwsh` on PATH. The CI path (GitHub's ubuntu runners ship
#            PowerShell 7 preinstalled). No Docker.
#   docker — fallback via mcr.microsoft.com/powershell:latest. How this runs
#            on a dev Mac with no local pwsh.
# The chosen mode is printed, so a log shows whether the check really ran
# natively or fell back.
#
# Wired into ci.yml as the `pwsh-exec-delta` job. Note it covers delta.ps1
# only; render-comment.ps1 and report.ps1 still have parse coverage only —
# see docs/architecture.md.
#
# Usage: ./tests/pwsh/exec-delta-ps1.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

HARNESS="$(mktemp)"
trap 'rm -f "$HARNESS"' EXIT
cat > "$HARNESS" <<'HARNESS_EOF'
set -euo pipefail

# Caller-supplied, so the same body runs in a container or on the host:
#   HARNESS_ROOT     repo root holding scripts/delta.ps1
#   HARNESS_SCRATCH  writable scratch dir; must contain a space (see below)
: "${HARNESS_ROOT:?HARNESS_ROOT not set}"
: "${HARNESS_SCRATCH:?HARNESS_SCRATCH not set}"

# The space is load-bearing, not incidental: it is what catches wrong native
# argument splitting. Refuse to run a version of this test that has quietly
# lost it.
case "$HARNESS_SCRATCH" in
  *' '*) ;;
  *) echo "FAIL: HARNESS_SCRATCH must contain a space, got <$HARNESS_SCRATCH>" >&2; exit 1 ;;
esac

FAKEBIN="$HARNESS_SCRATCH/fakebin"
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
  local rtemp="$HARNESS_SCRATCH/rtemp-$label"
  rm -rf "$rtemp"
  mkdir -p "$rtemp"
  local args_log="$rtemp/skill-detector-args.log"
  : > "$args_log"
  echo '{"axes":{"security":{"grade":"B"}},"findings":[],"version":"0.3.1"}' > "$rtemp/scan.json"

  local status=0
  env -i PATH="$PATH" HOME="$HOME" \
    RUNNER_TEMP="$rtemp" \
    INPUT_BASE_REF="main" \
    INPUT_HEAD_SCAN_JSON="$rtemp/scan.json" \
    INPUT_STRICT_MCP="$strict" \
    INPUT_SCAN_ALL="$scanall" \
    ARGS_LOG="$args_log" \
    pwsh -NoProfile -File "$HARNESS_ROOT/scripts/delta.ps1" || status=$?

  echo "==== case $label (strict=$strict scan_all=$scanall) exit=$status ===="
  cat "$args_log"
  echo

  if [ "$status" -ne 0 ]; then
    echo "FAIL: $label delta.ps1 exited $status" >&2
    exit 1
  fi

  # scan call must be the first block and must contain --strict-mcp / --scan-all
  # as their own ARG[] line iff the matching input was "true", never otherwise.
  local scan_block
  scan_block="$(sed -n '1,/^---$/p' "$args_log")"
  if [ "$strict" = "true" ]; then
    grep -qxF -- 'ARG[4]=<--strict-mcp>' <<< "$scan_block" || { echo "FAIL: $label missing --strict-mcp as its own arg" >&2; exit 1; }
  else
    grep -qF -- '--strict-mcp' <<< "$scan_block" && { echo "FAIL: $label unexpectedly threaded --strict-mcp" >&2; exit 1; }
  fi
  if [ "$scanall" = "true" ]; then
    grep -qF -- '<--scan-all>' <<< "$scan_block" || { echo "FAIL: $label missing --scan-all as its own arg" >&2; exit 1; }
  else
    grep -qF -- '--scan-all' <<< "$scan_block" && { echo "FAIL: $label unexpectedly threaded --scan-all" >&2; exit 1; }
  fi
  # base target (ARG[1]) must survive as one argument despite the space.
  grep -qxF -- "ARG[1]=<$rtemp/skilltrust-base-worktree>" <<< "$scan_block" \
    || { echo "FAIL: $label base target did not survive as a single argument" >&2; exit 1; }
}

run_case "strict-mcp" "true" "false"
run_case "scan-all" "false" "true"
run_case "neither" "false" "false"

echo "ALL CASES PASSED"
HARNESS_EOF

if command -v pwsh > /dev/null 2>&1; then
  # Space in the scratch path is required by the harness body; keep the
  # directory name distinct so cleanup never touches an unrelated /tmp entry.
  SCRATCH="${TMPDIR:-/tmp}/scan-action pwsh"
  echo "exec-delta-ps1: mode=direct (pwsh on PATH at $(command -v pwsh))"
  pwsh --version
  echo "exec-delta-ps1: scratch=<$SCRATCH>"
  mkdir -p "$SCRATCH"
  HARNESS_ROOT="$ROOT" HARNESS_SCRATCH="$SCRATCH" bash "$HARNESS"
else
  echo "exec-delta-ps1: mode=docker (no pwsh on PATH; using mcr.microsoft.com/powershell:latest)"
  docker run --rm \
    -v "$ROOT:/w:ro" \
    -v "$HARNESS:/harness.sh:ro" \
    -e HARNESS_ROOT=/w \
    -e 'HARNESS_SCRATCH=/tmp/skil security' \
    mcr.microsoft.com/powershell:latest \
    bash /harness.sh
fi
