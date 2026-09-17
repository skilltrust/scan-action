$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$Scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("scan-action-telemetry-" + [guid]::NewGuid())
$script:Requests = @()
$script:FailRequest = $false

function Invoke-RestMethod {
  param([string]$Uri, [string]$Method, [string]$Body, [string]$ContentType, [int]$TimeoutSec)
  $script:Requests += [pscustomobject]@{ Uri=$Uri; Method=$Method; Body=$Body; ContentType=$ContentType; TimeoutSec=$TimeoutSec }
  if ($script:FailRequest) { throw "fixture timeout" }
  return @{}
}

try {
  New-Item -ItemType Directory -Force -Path $Scratch | Out-Null
  $scan = Join-Path $Scratch "scan.json"
  $summary = Join-Path $Scratch "summary.md"
  Set-Content -LiteralPath $summary -Value "summary survives"
  $env:GITHUB_STEP_SUMMARY = $summary
  Set-Content -LiteralPath $scan -NoNewline -Value '{"axes":{"security":{"grade":"B"},"quality":{"grade":"A"}},"findings":[{"private_marker":"DO_NOT_SEND","file_path":"secret/path"}]}'
  $before = (Get-FileHash -Algorithm SHA256 $scan).Hash
  $env:INPUT_SCAN_JSON = $scan
  $env:INPUT_ACTION_VERSION = "1.11.0"
  $env:INPUT_DETECTOR_VERSION = "v0.10.0"
  $env:INPUT_DELTA_ENABLED = "false"
  $env:INPUT_TELEMETRY_URL = "https://example.invalid/capture"
  $env:GITHUB_SERVER_URL = "https://github.com"
  $env:GITHUB_REPOSITORY = "private-owner/private-repo"
  $env:GITHUB_REPOSITORY_VISIBILITY = "private"
  $env:GITHUB_EVENT_NAME = "pull_request"
  $env:RUNNER_OS = "Windows"
  $env:RUNNER_ARCH = "X64"

  . (Join-Path $Root "scripts/telemetry.ps1")
  if ($script:Requests.Count -ne 1) { throw "expected one telemetry request" }
  $request = $script:Requests[0]
  if ($request.TimeoutSec -ne 3 -or $request.Method -ne "Post") { throw "timeout/method mismatch" }
  $payload = $request.Body | ConvertFrom-Json
  $keys = @($payload.PSObject.Properties.Name | Sort-Object)
  $expected = @("action_version","delta_enabled","detector_version","finding_count","grade","repo_hash","repo_visibility","runner_arch","runner_os","trigger") | Sort-Object
  if (Compare-Object $keys $expected) { throw "telemetry field set mismatch" }
  if ($payload.repo_hash -notmatch '^[0-9a-f]{64}$' -or $payload.repo_visibility -ne "private" -or $payload.finding_count -ne 1 -or $payload.delta_enabled -ne $false) { throw "telemetry value mismatch" }
  if ($request.Body -match 'private-owner|private-repo|DO_NOT_SEND|secret/path|utm_') { throw "private data leaked" }
  if ((Get-FileHash -Algorithm SHA256 $scan).Hash -ne $before) { throw "scan JSON changed" }

  $script:Requests = @()
  Set-Content -LiteralPath $scan -NoNewline -Value '{"findings":[],"no_agent_surface":true,"private_marker":"DO_NOT_SEND","file_path":"secret/path"}'
  . (Join-Path $Root "scripts/telemetry.ps1")
  if ($script:Requests.Count -ne 1) { throw "no-surface scan did not make exactly one request" }
  $payload = $script:Requests[0].Body | ConvertFrom-Json
  $keys = @($payload.PSObject.Properties.Name | Sort-Object)
  if (Compare-Object $keys $expected) { throw "no-surface telemetry field set mismatch" }
  if ($payload.grade -isnot [string] -or $payload.grade -ne "" -or $payload.finding_count -isnot [long] -or $payload.finding_count -ne 0) { throw "no-surface telemetry types or values mismatch" }
  if ($script:Requests[0].Body -match 'private-owner|private-repo|DO_NOT_SEND|secret/path|utm_|no_agent_surface') { throw "no-surface private data leaked" }

  $script:Requests = @()
  Set-Content -LiteralPath $scan -NoNewline -Value '{malformed'
  . (Join-Path $Root "scripts/telemetry.ps1")
  if ($script:Requests.Count -ne 0) { throw "malformed scan made a request" }

  Set-Content -LiteralPath $scan -NoNewline -Value '{"axes":{},"findings":[]}'
  $script:FailRequest = $true
  . (Join-Path $Root "scripts/telemetry.ps1")
  if ($script:Requests.Count -ne 1) { throw "timeout path was not attempted once" }
  if ((Get-Content -LiteralPath $summary -Raw).Trim() -ne "summary survives") { throw "Summary changed" }

  Write-Host "exec-telemetry-ps1: privacy, malformed, and timeout cases passed"
} finally {
  Remove-Item -LiteralPath $Scratch -Recurse -Force -ErrorAction SilentlyContinue
}
