$ErrorActionPreference = "Stop"

# Required env from runner: RUNNER_ARCH, RUNNER_TEMP, INPUT_DETECTOR_VERSION

$version = $env:INPUT_DETECTOR_VERSION
if (-not $version) { throw "install.ps1: INPUT_DETECTOR_VERSION must be set" }

switch ($env:RUNNER_ARCH) {
  "X64"   { $arch = "amd64" }
  "ARM64" { $arch = "arm64" }
  default { throw "install.ps1: unsupported RUNNER_ARCH: $($env:RUNNER_ARCH)" }
}

$base  = "https://github.com/skilltrust/skill-detector/releases/download/$version"
# GoReleaser asset name includes the version (without 'v' prefix), e.g.
# skill-detector_0.4.0_windows_amd64.zip
$versionNoPrefix = $version.TrimStart('v')
$asset = "skill-detector_${versionNoPrefix}_windows_${arch}.zip"
$dest  = Join-Path $env:RUNNER_TEMP "skill-detector-install"

New-Item -ItemType Directory -Force -Path $dest | Out-Null

Write-Host "install.ps1: downloading $base/$asset"
Invoke-WebRequest -Uri "$base/$asset"        -OutFile (Join-Path $dest $asset)        -UseBasicParsing
Invoke-WebRequest -Uri "$base/checksums.txt" -OutFile (Join-Path $dest "checksums.txt") -UseBasicParsing

# Verify sha256
$checksumPattern = '^[0-9A-Fa-f]{64}\s+\*?' + [regex]::Escape($asset) + '\s*$'
$matchingChecksums = @(Get-Content (Join-Path $dest "checksums.txt") |
                       Where-Object { $_ -match $checksumPattern })
if ($matchingChecksums.Count -ne 1) { throw "install.ps1: $asset must appear exactly once in checksums.txt" }
$expected = ($matchingChecksums[0] -split '\s+')[0]
$actual = (Get-FileHash -Algorithm SHA256 (Join-Path $dest $asset)).Hash.ToLower()
if ($expected.ToLower() -ne $actual) { throw "install.ps1: checksum mismatch for $asset" }

Expand-Archive -Path (Join-Path $dest $asset) -DestinationPath $dest -Force

$binary = Join-Path $dest "skill-detector.exe"
if (!(Test-Path -LiteralPath $binary -PathType Leaf)) {
  throw "install.ps1: archive does not contain skill-detector.exe"
}
$installedVersionOutput = & $binary version 2>$null
$installedVersionExit = $LASTEXITCODE
$installedVersion = ($installedVersionOutput | Out-String).Trim()
if ($installedVersionExit -ne 0 -or $installedVersion -notmatch "version $([regex]::Escape($versionNoPrefix)) ") {
  throw "install.ps1: installed detector version does not match $version"
}

# Append the extraction dir to PATH for subsequent steps.
if ($env:GITHUB_PATH) { Add-Content -Path $env:GITHUB_PATH -Value $dest }
if ($env:GITHUB_ENV)  { Add-Content -Path $env:GITHUB_ENV  -Value "SCAN_ACTION_DETECTOR_DIR=$dest" }

Write-Host "install.ps1: skill-detector installed at $dest"
