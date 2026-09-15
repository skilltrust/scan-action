#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
command -v pwsh >/dev/null 2>&1 || { echo "SKIP: native pwsh unavailable"; exit 77; }

SCRATCH="$(mktemp -d '/tmp/report action ñ.XXXXXX')"
trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$SCRATCH/bin" "$SCRATCH/runner temp ñ"
export RUNNER_TEMP="$SCRATCH/runner temp ñ"
export GITHUB_STEP_SUMMARY="$SCRATCH/summary.md"
export INPUT_SCAN_JSON="$SCRATCH/scan.json"
export INPUT_PATH="agent path ñ"
export INPUT_REPORT_ONLY="true"
export INPUT_DELTA_ENABLED="false"
export GITHUB_EVENT_NAME="pull_request"
export SCAN_EXIT_CODE="2"

cat > "$INPUT_SCAN_JSON" <<'JSON'
{"findings":[{"rule_id":"SD-004","severity":"CRITICAL","effective_severity":"CRITICAL","file_path":"AGENTS.md","line":3,"diagnosis":"credential access","remediation":"remove it"}],"warnings":[],"files_scanned":1,"version":"0.10.0","axes":{"security":{"grade":"F"},"permission_hygiene":{"grade":"F"},"transparency":{"grade":"A"},"quality":{"grade":"D"}}}
JSON

pwsh -NoProfile -File "$ROOT/scripts/render-comment.ps1"
[ "$(head -n 1 "$RUNNER_TEMP/comment.md")" = '<!-- skilltrust:action:v1 -->' ]
grep -q 'Threshold reached — nonblocking' "$GITHUB_STEP_SUMMARY"
grep -q 'utm_content=pr_comment' "$RUNNER_TEMP/comment.md"
grep -q 'utm_content=job_summary' "$GITHUB_STEP_SUMMARY"

cp "$ROOT/tests/bats/fixtures/fake-gh.sh" "$SCRATCH/bin/gh"
chmod +x "$SCRATCH/bin/gh"
export PATH="$SCRATCH/bin:$PATH"
export FAKE_GH_LOG="$SCRATCH/gh.log"
export FAKE_GH_COMMENTS='[[{"id":777,"body":"<!-- skilltrust:action:v1 -->\nold"}]]'
export GH_TOKEN="test-token"
export INPUT_GITHUB_REPOSITORY="acme/widgets"
export INPUT_PULL_NUMBER="42"
export INPUT_HEAD_REPOSITORY="acme/widgets"
export INPUT_BASE_REPOSITORY="acme/widgets"
pwsh -NoProfile -File "$ROOT/scripts/report.ps1"
grep -q 'PATCH repos/acme/widgets/issues/comments/777' "$FAKE_GH_LOG"

: > "$FAKE_GH_LOG"
export INPUT_HEAD_REPOSITORY="fork/widgets"
printf '%s\n' '::error::hostile' > "$RUNNER_TEMP/comment.md"
pwsh -NoProfile -File "$ROOT/scripts/report.ps1" > "$SCRATCH/fork.log"
grep -q '^| ::error::hostile$' "$SCRATCH/fork.log"
[ ! -s "$FAKE_GH_LOG" ]

echo "exec-reporting-ps1: native render, update, and fork cases passed"
