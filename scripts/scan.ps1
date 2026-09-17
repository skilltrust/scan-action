$ErrorActionPreference = "Stop"

$path        = if ($env:INPUT_PATH)       { $env:INPUT_PATH }       else { "." }
# Mirrors action.yml's `fail-on` default — keep in step with scan.sh.
$failOn      = if ($env:INPUT_FAIL_ON)    { $env:INPUT_FAIL_ON }    else { "critical" }
$strictMCP   = $env:INPUT_STRICT_MCP -eq "true"
$scanAll     = $env:INPUT_SCAN_ALL   -eq "true"

$out = Join-Path $env:RUNNER_TEMP "scan.json"
Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue

function Publish-Failure([int]$Code) {
  if ($env:GITHUB_ENV) { Add-Content -LiteralPath $env:GITHUB_ENV -Value "SCAN_EXIT_CODE=$Code" }
  if ($env:GITHUB_OUTPUT) { Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "result-valid=false" }
}

foreach ($value in @(
  $(if ($env:INPUT_STRICT_MCP) { $env:INPUT_STRICT_MCP } else { "false" }),
  $(if ($env:INPUT_SCAN_ALL) { $env:INPUT_SCAN_ALL } else { "false" })
)) {
  if ($value -notin @("true", "false")) {
    Write-Host "::error title=SkillTrust::boolean inputs must be the string 'true' or 'false'"
    Publish-Failure 3
    exit 0
  }
}

$args = @("scan", $path, "--format", "json", "--fail-on", $failOn)

if ($env:INPUT_FAIL_ON_AXIS) {
  foreach ($spec in ($env:INPUT_FAIL_ON_AXIS -split ',')) {
    $s = $spec.Trim()
    if ($s) { $args += @("--fail-on-axis", $s) }
  }
}
if ($strictMCP) { $args += "--strict-mcp" }
if ($scanAll)   { $args += "--scan-all" }

Write-Host "scan.ps1: running skill-detector $($args -join ' ')"
try {
  $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $processInfo.FileName = "skill-detector"
  $processInfo.UseShellExecute = $false
  $processInfo.RedirectStandardOutput = $true
  foreach ($argument in $args) { [void]$processInfo.ArgumentList.Add($argument) }
  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $processInfo
  [void]$process.Start()
  $file = [System.IO.File]::Create($out)
  try { $process.StandardOutput.BaseStream.CopyTo($file) } finally { $file.Dispose() }
  $process.WaitForExit()
  $exit = $process.ExitCode
  $process.Dispose()
} catch {
  $exit = 127
}

if ($exit -notin @(0, 1, 2)) {
  Publish-Failure $exit
  Write-Host "scan.ps1: detector failed with exit=$exit; no result outputs published"
  exit 0
}

try {
  if (!(Test-Path -LiteralPath $out) -or (Get-Item -LiteralPath $out).Length -eq 0) { throw "empty" }
  $result = Get-Content -LiteralPath $out -Raw | ConvertFrom-Json
  $names = @($result.PSObject.Properties.Name)
  if ("findings" -notin $names -or $result.findings -isnot [array]) { throw "findings" }
  foreach ($finding in $result.findings) {
    if ($finding -isnot [pscustomobject]) { throw "finding object" }
    $findingNames = @($finding.PSObject.Properties.Name)
    foreach ($field in @("rule_id", "severity", "effective_severity", "description", "file_path", "diagnosis", "remediation")) {
      if ($field -notin $findingNames -or $finding.$field -isnot [string]) { throw "finding field" }
    }
    if ($finding.severity -notmatch '^(CRITICAL|HIGH|MEDIUM|LOW|INFO)$' -or
        $finding.effective_severity -notmatch '^(CRITICAL|HIGH|MEDIUM|LOW|INFO)$' -or
        $finding.line -isnot [long] -or $finding.line -lt 0) { throw "finding value" }
  }
  $findings = @($result.findings).Count
  $hasNoSurface = "no_agent_surface" -in $names
  if ($hasNoSurface) {
    if ($result.no_agent_surface -isnot [bool] -or $result.no_agent_surface -ne $true) { throw "no surface flag" }
    if ($findings -ne 0 -or "axes" -in $names -or $exit -ne 0) { throw "no surface" }
    $noSurface = $true
    $grade = ""
  } else {
    if ("axes" -notin $names -or $result.axes -isnot [pscustomobject]) { throw "axes" }
    foreach ($axis in @("security", "permission_hygiene", "transparency", "quality")) {
      if ($axis -notin @($result.axes.PSObject.Properties.Name)) { throw "axis" }
      $axisResult = $result.axes.$axis
      if ($axisResult -isnot [pscustomobject]) { throw "axis" }
      $axisGrade = $axisResult.grade
      if ($axisGrade -isnot [string] -or $axisGrade -cnotmatch '^[ABCDF]$') { throw "axis" }
    }
    if (($exit -eq 0 -and $findings -ne 0) -or ($exit -ne 0 -and $findings -eq 0)) { throw "exit/result" }
    $noSurface = $false
    $grade = $result.axes.quality.grade
  }
} catch {
  Write-Host "::error title=SkillTrust::detector returned a missing, empty, malformed, or invalid scan result"
  Publish-Failure 3
  exit 0
}

if ($env:GITHUB_ENV) { Add-Content -LiteralPath $env:GITHUB_ENV -Value "SCAN_EXIT_CODE=$exit" }
if ($env:GITHUB_OUTPUT) {
  Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "result-valid=true"
  Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "scan-json-path=$out"
  Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "grade=$grade"
  Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "findings-count=$findings"
  Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "no-agent-surface=$($noSurface.ToString().ToLowerInvariant())"
}

Write-Host "scan.ps1: detector exit=$exit, scan json at $out"
