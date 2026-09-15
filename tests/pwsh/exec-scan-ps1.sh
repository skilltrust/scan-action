#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
command -v pwsh >/dev/null 2>&1 || { echo "SKIP: native pwsh unavailable"; exit 77; }

SCRATCH="$(mktemp -d '/tmp/scan action ñ.XXXXXX')"
trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$SCRATCH/bin" "$SCRATCH/runner temp ñ"
cat > "$SCRATCH/bin/skill-detector" <<'EOF'
#!/usr/bin/env bash
printf '%s\0' "$@" > "$ARGS_LOG"
printf '%s' "$FAKE_JSON"
exit "$FAKE_EXIT"
EOF
chmod +x "$SCRATCH/bin/skill-detector"
export PATH="$SCRATCH/bin:$PATH"
export RUNNER_TEMP="$SCRATCH/runner temp ñ"
export ARGS_LOG="$SCRATCH/args"
export INPUT_PATH="$SCRATCH/target path ñ"
mkdir -p "$INPUT_PATH"

axes='"axes":{"security":{"grade":"F"},"permission_hygiene":{"grade":"D"},"transparency":{"grade":"C"},"quality":{"grade":"A"}}'

run_case() {
  local label="$1" code="$2" json="$3"
  export FAKE_EXIT="$code" FAKE_JSON="$json"
  export GITHUB_ENV="$SCRATCH/$label.env" GITHUB_OUTPUT="$SCRATCH/$label.out"
  : > "$GITHUB_ENV"; : > "$GITHUB_OUTPUT"
  pwsh -NoProfile -File "$ROOT/scripts/scan.ps1"
}

clean="{$axes,\"findings\":[]}"
run_case clean 0 "$clean"
grep -qx 'SCAN_EXIT_CODE=0' "$SCRATCH/clean.env"
grep -qx 'grade=A' "$SCRATCH/clean.out"
grep -qx 'findings-count=0' "$SCRATCH/clean.out"
grep -qx 'no-agent-surface=false' "$SCRATCH/clean.out"
cmp -s <(printf '%s' "$clean") "$RUNNER_TEMP/scan.json"
mapfile -d '' -t detector_args < "$ARGS_LOG"
[ "${detector_args[1]}" = "$INPUT_PATH" ]

finding="{$axes,\"findings\":[{\"rule_id\":\"SD-001\",\"severity\":\"CRITICAL\",\"effective_severity\":\"CRITICAL\",\"description\":\"credential access\",\"file_path\":\"AGENTS.md\",\"line\":3,\"diagnosis\":\"dangerous access\",\"remediation\":\"remove it\",\"future_field\":{\"accepted\":true}}]}"
run_case findings 2 "$finding"
grep -qx 'SCAN_EXIT_CODE=2' "$SCRATCH/findings.env"
grep -qx 'findings-count=1' "$SCRATCH/findings.out"
grep -qx 'scan-json-path=.*scan.json' "$SCRATCH/findings.out"
grep -qx 'result-valid=true' "$SCRATCH/findings.out"

run_case non-object-finding 1 "{$axes,\"findings\":[\"not-a-finding\"]}"
grep -qx 'SCAN_EXIT_CODE=3' "$SCRATCH/non-object-finding.env"
grep -qx 'result-valid=false' "$SCRATCH/non-object-finding.out"
! grep -q '^scan-json-path=' "$SCRATCH/non-object-finding.out"

run_case mistyped-finding 2 "{$axes,\"findings\":[{\"rule_id\":\"SD-001\",\"severity\":\"CRITICAL\",\"effective_severity\":\"CRITICAL\",\"description\":\"x\",\"file_path\":\"a\",\"line\":\"3\",\"diagnosis\":\"x\",\"remediation\":\"x\"}]}"
grep -qx 'SCAN_EXIT_CODE=3' "$SCRATCH/mistyped-finding.env"
grep -qx 'result-valid=false' "$SCRATCH/mistyped-finding.out"
! grep -q '^scan-json-path=' "$SCRATCH/mistyped-finding.out"

empty='{"findings":[],"no_agent_surface":true}'
run_case empty 0 "$empty"
grep -qx 'grade=' "$SCRATCH/empty.out"
grep -qx 'no-agent-surface=true' "$SCRATCH/empty.out"

run_case tool-error 3 "$clean"
grep -qx 'SCAN_EXIT_CODE=3' "$SCRATCH/tool-error.env"
! grep -q '^scan-json-path=' "$SCRATCH/tool-error.out"

run_case malformed 0 '{bad'
grep -qx 'SCAN_EXIT_CODE=3' "$SCRATCH/malformed.env"
grep -qx 'result-valid=false' "$SCRATCH/malformed.out"
! grep -q '^grade=' "$SCRATCH/malformed.out"

run_case second 127 ''
grep -qx 'SCAN_EXIT_CODE=127' "$SCRATCH/second.env"
! grep -q '^scan-json-path=' "$SCRATCH/second.out"
[ ! -s "$RUNNER_TEMP/scan.json" ]

echo "exec-scan-ps1: all native scan/result/output cases passed"
