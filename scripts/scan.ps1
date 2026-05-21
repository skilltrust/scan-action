$ErrorActionPreference = "Stop"

$path        = if ($env:INPUT_PATH)       { $env:INPUT_PATH }       else { "." }
$failOn      = if ($env:INPUT_FAIL_ON)    { $env:INPUT_FAIL_ON }    else { "high" }
$strictMCP   = $env:INPUT_STRICT_MCP -eq "true"
$scanAll     = $env:INPUT_SCAN_ALL   -eq "true"

$args = @("scan", $path, "--format", "json", "--fail-on", $failOn)

if ($env:INPUT_FAIL_ON_AXIS) {
  foreach ($spec in ($env:INPUT_FAIL_ON_AXIS -split ',')) {
    $s = $spec.Trim()
    if ($s) { $args += @("--fail-on-axis", $s) }
  }
}
if ($strictMCP) { $args += "--strict-mcp" }
if ($scanAll)   { $args += "--scan-all" }

$out = Join-Path $env:RUNNER_TEMP "scan.json"
Write-Host "scan.ps1: running skill-detector $($args -join ' ')"
$proc = Start-Process -FilePath "skill-detector" -ArgumentList $args -NoNewWindow -PassThru -RedirectStandardOutput $out -Wait
$exit = $proc.ExitCode

if ($env:GITHUB_ENV) {
  Add-Content -Path $env:GITHUB_ENV -Value "SCAN_EXIT_CODE=$exit"
}
if ($env:GITHUB_OUTPUT) {
  Add-Content -Path $env:GITHUB_OUTPUT -Value "scan-json-path=$out"
  # jq is preinstalled on windows-latest as part of git for Windows? safer: skip outputs if missing.
  if (Get-Command jq -ErrorAction SilentlyContinue) {
    $grade    = (jq -r 'if .axes then (.axes | to_entries | map(.value.grade) | sort | last) // "" else "" end' $out)
    $findings = (jq -r '.findings | length // 0' $out)
    Add-Content -Path $env:GITHUB_OUTPUT -Value "grade=$grade"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "findings-count=$findings"
  }
}

Write-Host "scan.ps1: detector exit=$exit, scan json at $out"
