#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRATCH="$(mktemp -d '/tmp/scan action composite ñ.XXXXXX')"
trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$SCRATCH/bin" "$SCRATCH/difficult path ñ"

# This local harness executes the exact Linux step scripts in action.yml order.
# Hosted CI below is the authoritative `uses: ./` proof; these assertions keep
# the local equivalent tied to that composite instead of reimplementing policy.
mapfile -t wired < <(grep -o '\${{ github.action_path }}/scripts/[a-z0-9.-]*' "$ROOT/action.yml" | sed 's|.*/scripts/||')
for script in install.sh scan.sh delta.sh render-comment.sh report.sh telemetry.sh; do
  found=false
  for candidate in "${wired[@]}"; do [ "$candidate" != "$script" ] || found=true; done
  [ "$found" = true ]
done
awk '/name: Propagate exit code/{block=1} block && /if: always\(\)/{found=1} END{exit !found}' "$ROOT/action.yml"

cat > "$SCRATCH/bin/skill-detector" <<'EOF'
#!/usr/bin/env bash
set -u
printf '%s\0' "$@" > "$FAKE_ARGS"
axes='"axes":{"security":{"grade":"D"},"permission_hygiene":{"grade":"B"},"transparency":{"grade":"A"},"quality":{"grade":"C"}}'
finding='{"rule_id":"SD-004","severity":"CRITICAL","effective_severity":"CRITICAL","description":"private marker stays local","file_path":"difficult path ñ/SKILL.md","line":7,"diagnosis":"credential access","remediation":"remove it","future_detail":"complete"}'
case "$FAKE_CASE" in
  clean) printf "{%s,\"findings\":[],\"complete_marker\":\"kept\"}" "$axes"; exit 0 ;;
  below) printf "{%s,\"findings\":[%s],\"complete_marker\":\"kept\"}" "$axes" "$finding"; exit 1 ;;
  critical) printf "{%s,\"findings\":[%s],\"complete_marker\":\"kept\"}" "$axes" "$finding"; exit 2 ;;
  axis)
    case " $* " in *' --fail-on-axis security=C '*) code=2;; *) code=1;; esac
    printf "{%s,\"findings\":[%s],\"complete_marker\":\"kept\"}" "$axes" "$finding"; exit "$code" ;;
  empty) printf '{"findings":[],"no_agent_surface":true,"complete_marker":"kept"}'; exit 0 ;;
  tool) printf '{"error":"tool"}'; exit 3 ;;
  unknown) exit 42 ;;
esac
EOF
chmod +x "$SCRATCH/bin/skill-detector"
export PATH="$SCRATCH/bin:$PATH"
export FAKE_ARGS="$SCRATCH/args"
export GITHUB_EVENT_NAME=push
export GITHUB_REPOSITORY=private-owner/private-repo
export GITHUB_REPOSITORY_VISIBILITY=private
export GITHUB_SERVER_URL=https://github.com
export RUNNER_OS=Linux RUNNER_ARCH=X64

output_value() { sed -n "s/^$1=//p" "$GITHUB_OUTPUT" | tail -1; }

run_case() {
  local label="$1" fake="$2" report_only="$3" warn="$4" no_surface_gate="$5" axis="${6:-}" expected="$7"
  export RUNNER_TEMP="$SCRATCH/run-$label"
  export GITHUB_ENV="$RUNNER_TEMP/env" GITHUB_OUTPUT="$RUNNER_TEMP/output" GITHUB_STEP_SUMMARY="$RUNNER_TEMP/summary"
  mkdir -p "$RUNNER_TEMP"; : > "$GITHUB_ENV"; : > "$GITHUB_OUTPUT"; : > "$GITHUB_STEP_SUMMARY"
  export FAKE_CASE="$fake"
  INPUT_PATH="$SCRATCH/difficult path ñ" INPUT_FAIL_ON=critical INPUT_FAIL_ON_AXIS="$axis" \
    INPUT_STRICT_MCP=true INPUT_SCAN_ALL=true bash "$ROOT/scripts/scan.sh"
  # Runner imports GITHUB_ENV before following steps.
  set -a; source "$GITHUB_ENV"; set +a
  if [ "$(output_value result-valid)" = true ]; then
    scan_path="$(output_value scan-json-path)"
    jq -e '.complete_marker == "kept"' "$scan_path" >/dev/null
    before="$(sha256sum "$scan_path")"
    INPUT_SCAN_JSON="$scan_path" INPUT_PATH="$SCRATCH/difficult path ñ" \
      INPUT_REPORT_ONLY="$report_only" INPUT_WARN_ON_BELOW_THRESHOLD="$warn" \
      INPUT_FAIL_ON_NO_AGENT_SURFACE="$no_surface_gate" INPUT_DELTA_ENABLED=false \
      bash "$ROOT/scripts/render-comment.sh"
    grep -q '<!-- skilltrust:action:v1 -->' "$RUNNER_TEMP/comment.md"
    [ -s "$GITHUB_STEP_SUMMARY" ]
    [ "$before" = "$(sha256sum "$scan_path")" ]
  else
    [ -z "$(output_value scan-json-path)" ]
    [ -z "$(output_value grade)" ]
  fi
  set +e
  INPUT_REPORT_ONLY="$report_only" INPUT_WARN_ON_BELOW_THRESHOLD="$warn" \
    INPUT_GRADE="$(output_value grade)" INPUT_FINDINGS_COUNT="$(output_value findings-count)" \
    INPUT_NO_AGENT_SURFACE="$(output_value no-agent-surface)" \
    INPUT_FAIL_ON_NO_AGENT_SURFACE="$no_surface_gate" bash "$ROOT/scripts/propagate-exit.sh"
  actual=$?
  set -e
  [ "$actual" -eq "$expected" ]
}

run_case clean clean false true false '' 0
[ "$(output_value grade)" = C ] && [ "$(output_value findings-count)" = 0 ] && [ "$(output_value no-agent-surface)" = false ]
mapfile -d '' -t args < "$FAKE_ARGS"; [ "${args[1]}" = "$SCRATCH/difficult path ñ" ]
run_case below-default below false true false '' 0
run_case below-legacy below false false false '' 1
run_case below-report below true false false '' 0
run_case critical-block critical false true false '' 2
run_case critical-report critical true true false '' 0
run_case axis-equal axis false true false security=D 0
run_case axis-strict-worse axis false true false security=C 2
run_case empty-warn empty false true false '' 0
run_case empty-gate empty true true true '' 2
run_case tool tool true true false '' 3
run_case unknown unknown true true false '' 42

# A second invocation in one runner temp cannot reuse the first validated JSON.
export RUNNER_TEMP="$SCRATCH/twice" GITHUB_ENV="$SCRATCH/twice/env" GITHUB_OUTPUT="$SCRATCH/twice/out"
mkdir -p "$RUNNER_TEMP"; : > "$GITHUB_ENV"; : > "$GITHUB_OUTPUT"
FAKE_CASE=clean INPUT_PATH=. INPUT_FAIL_ON=critical INPUT_STRICT_MCP=false INPUT_SCAN_ALL=false bash "$ROOT/scripts/scan.sh"
[ -s "$RUNNER_TEMP/scan.json" ]
: > "$GITHUB_ENV"; : > "$GITHUB_OUTPUT"
FAKE_CASE=unknown INPUT_PATH=. INPUT_FAIL_ON=critical INPUT_STRICT_MCP=false INPUT_SCAN_ALL=false bash "$ROOT/scripts/scan.sh"
[ ! -s "$RUNNER_TEMP/scan.json" ]
[ "$(output_value result-valid)" = false ]

echo "local-composite-equivalent: exits, policy, outputs, difficult paths, and repeat invocation passed"
