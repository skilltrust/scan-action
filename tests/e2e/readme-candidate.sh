#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
CANDIDATE="$SCRATCH/skilltrust.yml"

awk '
  /^## Quickstart: report only$/ { section=1; next }
  section && /^```yaml$/ { fence=1; next }
  fence && /^```$/ { exit }
  fence { print }
' "$ROOT/README.md" > "$CANDIDATE"
[ -s "$CANDIDATE" ]

ruby -ryaml -e '
  workflow = YAML.safe_load(File.read(ARGV[0]), aliases: true)
  trigger = workflow["on"] || workflow[true]
  raise "missing push/PR triggers" unless trigger.key?("push") && trigger.key?("pull_request")
  steps = workflow.fetch("jobs").fetch("scan").fetch("steps")
  action = steps.find { |step| step["uses"] == "skilltrust/scan-action@v1" }
  raise "missing candidate Action" unless action
  raise "candidate must be report-only" unless action.dig("with", "report-only") == "true"
  raise "candidate must request delta" unless action.dig("with", "delta") == "true"
  raise "missing checkout history" unless steps.any? { |step| step["uses"] == "actions/checkout@v4" && step.dig("with", "fetch-depth") == 0 }
  checkout = steps.find { |step| step["uses"] == "actions/checkout@v4" }
  raise "candidate must scan PR head, not synthetic merge" unless checkout.dig("with", "ref") == "${{ github.event.pull_request.head.sha || github.sha }}"
' "$CANDIDATE"

ruby -ryaml -e '
  action = YAML.safe_load(File.read(ARGV[0]), aliases: true)
  expected_inputs = %w[path fail-on fail-on-axis strict-mcp scan-all comment warn-on-below-threshold fail-on-no-agent-surface report-only delta telemetry github-token detector-version].sort
  expected_outputs = %w[grade scan-json-path findings-count no-agent-surface].sort
  raise "input contract drift" unless action.fetch("inputs").keys.sort == expected_inputs
  raise "output contract drift" unless action.fetch("outputs").keys.sort == expected_outputs
  raise "report-only default drift" unless action.dig("inputs", "report-only", "default") == "false"
  raise "detector pin drift" unless action.dig("inputs", "detector-version", "default") == "v0.11.0"
  expected_outputs.each do |name|
    value = action.dig("outputs", name, "value")
    raise "unbridged output #{name}" unless value.include?("steps.scan.outputs.#{name} || steps.scan-win.outputs.#{name}")
  end
' "$ROOT/action.yml"

echo "readme-candidate: copied workflow YAML, report-only inputs, pin, and outputs passed"
