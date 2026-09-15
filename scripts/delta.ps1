$ErrorActionPreference = "Stop"

# Required env: RUNNER_TEMP, INPUT_BASE_REF, INPUT_HEAD_SCAN_JSON.
# Optional env: INPUT_PATH, INPUT_STRICT_MCP, INPUT_SCAN_ALL, GITHUB_ENV,
# GITHUB_OUTPUT.

$baseRef = $env:INPUT_BASE_REF
$headJson = $env:INPUT_HEAD_SCAN_JSON
$scanPath = if ($env:INPUT_PATH) { $env:INPUT_PATH } else { "." }
$baseDir = Join-Path $env:RUNNER_TEMP "skilltrust-base-worktree"
$baseJson = Join-Path $env:RUNNER_TEMP "base-scan.json"
$deltaOut = Join-Path $env:RUNNER_TEMP "delta.json"
$worktreeAdded = $false

function Clear-Delta {
  Remove-Item -LiteralPath $baseJson, $deltaOut -Force -ErrorAction SilentlyContinue
  if ($env:GITHUB_ENV) { Add-Content -LiteralPath $env:GITHUB_ENV -Value "SCAN_ACTION_DELTA_JSON=" }
  if ($env:GITHUB_OUTPUT) { Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "delta-json-path=" }
}

function Stop-Unavailable([string]$Reason) {
  Remove-Item -LiteralPath $deltaOut -Force -ErrorAction SilentlyContinue
  if ($env:GITHUB_ENV) { Add-Content -LiteralPath $env:GITHUB_ENV -Value "SCAN_ACTION_DELTA_JSON=" }
  if ($env:GITHUB_OUTPUT) { Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "delta-json-path=" }
  Write-Host "::warning title=SkillTrust delta unavailable::$Reason; the head scan result and gate are unchanged"
  exit 0
}

function Test-ScanResult($Result) {
  $names = @($Result.PSObject.Properties.Name)
  if ("findings" -notin $names -or $Result.findings -isnot [array]) { return $false }
  if ("no_agent_surface" -in $names) {
    return $Result.no_agent_surface -eq $true -and @($Result.findings).Count -eq 0 -and "axes" -notin $names
  }
  if ("axes" -notin $names) { return $false }
  foreach ($axis in @("security", "permission_hygiene", "transparency", "quality")) {
    if ($axis -notin @($Result.axes.PSObject.Properties.Name) -or
        $Result.axes.$axis.grade -notmatch '^[ABCDF]$') { return $false }
  }
  return $true
}

Clear-Delta
try {
  foreach ($value in @(
    $(if ($env:INPUT_STRICT_MCP) { $env:INPUT_STRICT_MCP } else { "false" }),
    $(if ($env:INPUT_SCAN_ALL) { $env:INPUT_SCAN_ALL } else { "false" })
  )) {
    if ($value -notin @("true", "false")) { Stop-Unavailable "invalid boolean scope input" }
  }
  if (!$baseRef) { Stop-Unavailable "base ref is missing" }
  if (!$headJson -or !(Test-Path -LiteralPath $headJson) -or (Get-Item -LiteralPath $headJson).Length -eq 0) {
    Stop-Unavailable "head scan result is missing"
  }

  Write-Host "delta.ps1: fetching base $baseRef (depth=1)"
  & git fetch origin $baseRef --depth 1
  if ($LASTEXITCODE -ne 0) { Stop-Unavailable "base fetch failed" }
  $baseCommit = (& git rev-parse --verify 'FETCH_HEAD^{commit}')
  if ($LASTEXITCODE -ne 0 -or !$baseCommit) { Stop-Unavailable "fetched base commit could not be resolved" }

  Remove-Item -LiteralPath $baseDir -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host "delta.ps1: creating worktree at $baseDir from $baseCommit"
  & git worktree add --detach $baseDir $baseCommit | Out-Null
  if ($LASTEXITCODE -ne 0) { Stop-Unavailable "base worktree creation failed" }
  $worktreeAdded = $true

  $baseTarget = if ($scanPath -eq ".") { $baseDir } else { Join-Path $baseDir $scanPath }
  if (!(Test-Path -LiteralPath $baseTarget)) { Stop-Unavailable "path '$scanPath' is absent from the base commit" }

  $scanArgs = @("scan", $baseTarget, "--format", "json")
  if ($env:INPUT_STRICT_MCP -eq "true") { $scanArgs += "--strict-mcp" }
  if ($env:INPUT_SCAN_ALL -eq "true") { $scanArgs += "--scan-all" }

  Write-Host "delta.ps1: scanning base tree"
  & skill-detector @scanArgs > $baseJson
  $baseExit = $LASTEXITCODE
  if ($baseExit -notin @(0, 1, 2)) { Stop-Unavailable "base scan failed with exit $baseExit" }

  try {
    $baseResult = Get-Content -LiteralPath $baseJson -Raw | ConvertFrom-Json
    $headResult = Get-Content -LiteralPath $headJson -Raw | ConvertFrom-Json
  } catch { Stop-Unavailable "base or head scan result is malformed" }
  if (!(Test-ScanResult $baseResult)) { Stop-Unavailable "base scan result is missing, empty, malformed, or invalid" }
  $baseNoSurface = "no_agent_surface" -in @($baseResult.PSObject.Properties.Name)
  if (($baseNoSurface -and $baseExit -ne 0) -or
      (!$baseNoSurface -and $baseExit -eq 0 -and @($baseResult.findings).Count -ne 0) -or
      ($baseExit -ne 0 -and @($baseResult.findings).Count -eq 0)) {
    Stop-Unavailable "base scan exit and result disagree"
  }
  if (!(Test-ScanResult $headResult)) { Stop-Unavailable "head scan result is missing, empty, malformed, or invalid" }

  Write-Host "delta.ps1: computing delta"
  & skill-detector delta $baseJson $headJson --format json > $deltaOut
  if ($LASTEXITCODE -ne 0) { Stop-Unavailable "delta command failed with exit $LASTEXITCODE" }
  try { $delta = Get-Content -LiteralPath $deltaOut -Raw | ConvertFrom-Json } catch { Stop-Unavailable "delta result is malformed" }
  $deltaNames = @($delta.PSObject.Properties.Name)
  if (@("per_axis", "new_findings", "resolved_findings", "axis_explanations") |
      Where-Object { $_ -notin $deltaNames }) { Stop-Unavailable "delta result is missing required fields" }
  if ($delta.per_axis -isnot [pscustomobject] -or $delta.axis_explanations -isnot [pscustomobject] -or
      ($null -ne $delta.new_findings -and $delta.new_findings -isnot [array]) -or
      ($null -ne $delta.resolved_findings -and $delta.resolved_findings -isnot [array])) {
    Stop-Unavailable "delta result is invalid"
  }
  foreach ($axis in $delta.per_axis.PSObject.Properties.Value) {
    if ($axis.Old -isnot [string] -or $axis.New -isnot [string] -or
        $axis.Direction -notin @("up", "down", "same")) { Stop-Unavailable "delta result is invalid" }
  }

  if ($env:GITHUB_OUTPUT) { Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "delta-json-path=$deltaOut" }
  if ($env:GITHUB_ENV) { Add-Content -LiteralPath $env:GITHUB_ENV -Value "SCAN_ACTION_DELTA_JSON=$deltaOut" }
  Write-Host "delta.ps1: wrote $deltaOut"
} finally {
  if ($worktreeAdded) {
    & git worktree remove --force $baseDir 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Host "::warning title=SkillTrust::could not remove delta worktree $baseDir" }
  }
}
