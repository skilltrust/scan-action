$ErrorActionPreference = "Stop"

$baseRef  = $env:INPUT_BASE_REF
$headJson = $env:INPUT_HEAD_SCAN_JSON
$scanPath = if ($env:INPUT_PATH) { $env:INPUT_PATH } else { "." }
$baseDir  = Join-Path $env:RUNNER_TEMP "skilltrust-base-worktree"

Write-Host "delta.ps1: fetching base $baseRef (depth=1)"
git fetch origin $baseRef --depth 1
Write-Host "delta.ps1: creating worktree at $baseDir"
git worktree add --detach $baseDir "origin/$baseRef" | Out-Null

$baseTarget = if ($scanPath -eq ".") { $baseDir } else { Join-Path $baseDir $scanPath }
$baseJson   = Join-Path $env:RUNNER_TEMP "base-scan.json"
Write-Host "delta.ps1: scanning base tree"
skill-detector scan $baseTarget --format json | Out-File -FilePath $baseJson -Encoding utf8

$deltaOut = Join-Path $env:RUNNER_TEMP "delta.json"
Write-Host "delta.ps1: computing delta"
skill-detector delta $baseJson $headJson --format json | Out-File -FilePath $deltaOut -Encoding utf8

if ($env:GITHUB_OUTPUT) { Add-Content -Path $env:GITHUB_OUTPUT -Value "delta-json-path=$deltaOut" }
if ($env:GITHUB_ENV)    { Add-Content -Path $env:GITHUB_ENV    -Value "SCAN_ACTION_DELTA_JSON=$deltaOut" }
Write-Host "delta.ps1: wrote $deltaOut"
