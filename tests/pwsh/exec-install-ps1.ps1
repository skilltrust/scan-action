$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$Scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("scan-action-install-" + [guid]::NewGuid())
$Release = Join-Path $Scratch "release"
$script:DownloadFailure = ""
$script:RequestLog = Join-Path $Scratch "requests.log"

function global:Invoke-WebRequest {
  param([string]$Uri, [string]$OutFile, [switch]$UseBasicParsing)
  Add-Content -LiteralPath $script:RequestLog -Value $Uri
  $name = [System.IO.Path]::GetFileName($Uri)
  if ($script:DownloadFailure -eq $name) { throw "fixture download failure" }
  Copy-Item -LiteralPath (Join-Path $Release $name) -Destination $OutFile
}

function New-Release([string]$Arch, [string]$ReportedVersion = "0.10.0") {
  Remove-Item -LiteralPath $Release -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path $Release | Out-Null
  $payload = Join-Path $Scratch "payload"
  Remove-Item -LiteralPath $payload -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path $payload | Out-Null
  $binary = Join-Path $payload "skill-detector.exe"
  if ($IsWindows) {
    throw "fixture generator is intended for native PowerShell on the local Linux verification host"
  }
  $source = Join-Path $payload "fixture.c"
  @"
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {
  if (argc == 2 && strcmp(argv[1], "version") == 0) {
    puts("skill-detector version $ReportedVersion (fixture)");
    return 0;
  }
  return 99;
}
"@ | Set-Content -LiteralPath $source -NoNewline
  & cc -o $binary $source
  if ($LASTEXITCODE -ne 0) { throw "fixture compilation failed" }
  $asset = "skill-detector_0.10.0_windows_$Arch.zip"
  Microsoft.PowerShell.Archive\Compress-Archive -Path $binary -DestinationPath (Join-Path $Release $asset)
  $hash = (Get-FileHash -Algorithm SHA256 (Join-Path $Release $asset)).Hash.ToLower()
  Set-Content -LiteralPath (Join-Path $Release "checksums.txt") -Value "$hash  $asset"
  return $asset
}

function Invoke-Installer([string]$RunnerArch) {
  function Expand-Archive {
    param([string]$Path, [string]$DestinationPath, [switch]$Force)
    Microsoft.PowerShell.Archive\Expand-Archive -Path $Path -DestinationPath $DestinationPath -Force:$Force
    if (-not $IsWindows) { & chmod +x (Join-Path $DestinationPath "skill-detector.exe") }
  }
  $env:RUNNER_ARCH = $RunnerArch
  $env:RUNNER_TEMP = Join-Path $Scratch "runner"
  $env:INPUT_DETECTOR_VERSION = "v0.10.0"
  $env:GITHUB_PATH = Join-Path $Scratch "github-path"
  $env:GITHUB_ENV = Join-Path $Scratch "github-env"
  Remove-Item -LiteralPath $env:RUNNER_TEMP -Recurse -Force -ErrorAction SilentlyContinue
  Set-Content -LiteralPath $script:RequestLog -Value "" -NoNewline
  Set-Content -LiteralPath $env:GITHUB_PATH -Value "" -NoNewline
  Set-Content -LiteralPath $env:GITHUB_ENV -Value "" -NoNewline
  . (Join-Path $Root "scripts/install.ps1")
}

function Assert-Throws([scriptblock]$Operation, [string]$Pattern) {
  try { & $Operation; throw "expected failure matching $Pattern" }
  catch {
    if ($_.Exception.Message -notmatch $Pattern) { throw }
  }
}

try {
  New-Item -ItemType Directory -Force -Path $Scratch | Out-Null
  foreach ($case in @(@("X64", "amd64"), @("ARM64", "arm64"))) {
    $asset = New-Release $case[1]
    Invoke-Installer $case[0]
    $requests = Get-Content -LiteralPath $script:RequestLog
    if ($requests -notcontains "https://github.com/skilltrust/skill-detector/releases/download/v0.10.0/$asset") { throw "asset URL mismatch" }
    if ($requests -notcontains "https://github.com/skilltrust/skill-detector/releases/download/v0.10.0/checksums.txt") { throw "checksum URL mismatch" }
    if ((& (Join-Path $env:RUNNER_TEMP "skill-detector-install/skill-detector.exe") version) -notmatch 'version 0\.10\.0 ') { throw "version gate mismatch" }
  }

  $asset = New-Release "amd64"
  Add-Content -LiteralPath (Join-Path $Release $asset) -Value "tamper"
  Assert-Throws { Invoke-Installer "X64" } "checksum mismatch"

  $asset = New-Release "amd64"
  Set-Content -LiteralPath (Join-Path $Release "checksums.txt") -Value (("0" * 64) + "  other.zip")
  Assert-Throws { Invoke-Installer "X64" } "must appear exactly once"

  $asset = New-Release "amd64"
  Add-Content -LiteralPath (Join-Path $Release "checksums.txt") -Value (Get-Content -LiteralPath (Join-Path $Release "checksums.txt"))
  Assert-Throws { Invoke-Installer "X64" } "must appear exactly once"

  $asset = New-Release "amd64"
  $script:DownloadFailure = "checksums.txt"
  Assert-Throws { Invoke-Installer "X64" } "fixture download failure"
  $script:DownloadFailure = ""

  $asset = New-Release "amd64" "0.9.9"
  Assert-Throws { Invoke-Installer "X64" } "version does not match"

  New-Release "amd64" | Out-Null
  Assert-Throws { Invoke-Installer "PowerPC" } "unsupported RUNNER_ARCH"
  if ((Get-Item -LiteralPath $script:RequestLog).Length -ne 0) { throw "unsupported arch made a request" }

  Write-Host "exec-install-ps1: exact Windows assets and adverse installer cases passed"
} finally {
  Remove-Item -LiteralPath $Scratch -Recurse -Force -ErrorAction SilentlyContinue
}
