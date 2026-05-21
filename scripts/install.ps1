$ErrorActionPreference = "Stop"

# Required env from runner: RUNNER_ARCH, RUNNER_TEMP, INPUT_DETECTOR_VERSION

$version = $env:INPUT_DETECTOR_VERSION
if (-not $version) { throw "install.ps1: INPUT_DETECTOR_VERSION must be set" }

switch ($env:RUNNER_ARCH) {
  "X64"   { $arch = "amd64" }
  "ARM64" { $arch = "arm64" }
  default { throw "install.ps1: unsupported RUNNER_ARCH: $($env:RUNNER_ARCH)" }
}

$base  = "https://github.com/velzepooz/skill-detector/releases/download/$version"
$asset = "skill-detector_windows_${arch}.zip"
$dest  = Join-Path $env:RUNNER_TEMP "skill-detector-install"

New-Item -ItemType Directory -Force -Path $dest | Out-Null

Write-Host "install.ps1: downloading $base/$asset"
Invoke-WebRequest -Uri "$base/$asset"        -OutFile (Join-Path $dest $asset)        -UseBasicParsing
Invoke-WebRequest -Uri "$base/checksums.txt" -OutFile (Join-Path $dest "checksums.txt") -UseBasicParsing

# Verify sha256
$expected = (Get-Content (Join-Path $dest "checksums.txt") |
             Where-Object { $_ -match [regex]::Escape($asset) }) -split '\s+' | Select-Object -First 1
if (-not $expected) { throw "install.ps1: $asset not found in checksums.txt" }
$actual = (Get-FileHash -Algorithm SHA256 (Join-Path $dest $asset)).Hash.ToLower()
if ($expected.ToLower() -ne $actual) { throw "install.ps1: checksum mismatch for $asset" }

Expand-Archive -Path (Join-Path $dest $asset) -DestinationPath $dest -Force

# Append the extraction dir to PATH for subsequent steps.
if ($env:GITHUB_PATH) { Add-Content -Path $env:GITHUB_PATH -Value $dest }
if ($env:GITHUB_ENV)  { Add-Content -Path $env:GITHUB_ENV  -Value "SCAN_ACTION_DETECTOR_DIR=$dest" }

Write-Host "install.ps1: skill-detector installed at $dest"
