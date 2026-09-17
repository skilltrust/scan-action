$ErrorActionPreference = "Stop"

# Required env: RUNNER_TEMP, INPUT_SCAN_JSON. Optional metadata mirrors the
# POSIX wrapper. Both call the same renderer.
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $env:RUNNER_TEMP "comment.md"
Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue

$arguments = @(
  (Join-Path $root "scripts/render.py"),
  "--scan", $env:INPUT_SCAN_JSON,
  "--published", (Join-Path $root "config/published-rule-ids.txt"),
  "--comment", $out,
  "--scope", $(if ($env:INPUT_PATH) { $env:INPUT_PATH } else { "." }),
  "--event", $(if ($env:GITHUB_EVENT_NAME) { $env:GITHUB_EVENT_NAME } else { "unknown" }),
  "--exit-code", $(if ($env:SCAN_EXIT_CODE) { $env:SCAN_EXIT_CODE } else { "" }),
  "--report-only", $(if ($env:INPUT_REPORT_ONLY) { $env:INPUT_REPORT_ONLY } else { "false" }),
  "--warn-below", $(if ($env:INPUT_WARN_ON_BELOW_THRESHOLD) { $env:INPUT_WARN_ON_BELOW_THRESHOLD } else { "true" }),
  "--fail-no-surface", $(if ($env:INPUT_FAIL_ON_NO_AGENT_SURFACE) { $env:INPUT_FAIL_ON_NO_AGENT_SURFACE } else { "false" })
)
if ($env:GITHUB_STEP_SUMMARY) { $arguments += @("--summary", $env:GITHUB_STEP_SUMMARY) }
if ($env:INPUT_DELTA_ENABLED -eq "true") { $arguments += "--delta-enabled" }

try {
  & python @arguments
  if ($LASTEXITCODE -ne 0) { throw "renderer exited nonzero" }
} catch {
  @(
    "<!-- skilltrust:action:v1 -->"
    "## SkillTrust report unavailable"
    ""
    "The scan completed, but its report could not be rendered. The scan policy and validated JSON remain unchanged."
  ) | Set-Content -LiteralPath $out -Encoding utf8
  if ($env:GITHUB_STEP_SUMMARY) {
    try { Get-Content -LiteralPath $out | Select-Object -Skip 1 | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY } catch {}
  }
  Write-Host "::warning title=SkillTrust report unavailable::scan completed but safe rendering failed; scan policy is unchanged"
  exit 0
}

Write-Host "render-comment.ps1: safe report written"
