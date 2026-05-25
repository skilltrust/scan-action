# Fire-and-forget. Never throw.
try {
  $ingestUrl = if ($env:INPUT_TELEMETRY_URL) { $env:INPUT_TELEMETRY_URL } else { "https://skilltrust.app/api/telemetry/action-run" }
  $scan = $env:INPUT_SCAN_JSON
  if (-not $scan -or -not (Test-Path $scan)) { return }

  $data    = Get-Content $scan -Raw | ConvertFrom-Json
  $axes    = if ($data.axes) { $data.axes } else { @{} }
  $grades  = @($axes.PSObject.Properties.Value.grade) | Sort-Object
  $worst   = if ($grades) { $grades[-1] } else { "" }
  $count   = if ($data.findings) { $data.findings.Count } else { 0 }

  $repoUrl  = "{0}/{1}" -f $env:GITHUB_SERVER_URL, $env:GITHUB_REPOSITORY
  $sha256   = [System.Security.Cryptography.SHA256]::Create()
  $bytes    = [System.Text.Encoding]::UTF8.GetBytes($repoUrl)
  $hash     = -join (($sha256.ComputeHash($bytes)) | ForEach-Object { $_.ToString("x2") })

  $visibility = if ($env:GITHUB_REPOSITORY_VISIBILITY -and $env:GITHUB_REPOSITORY_VISIBILITY -ne "public") { "private" } else { "public" }

  $payload = @{
    action_version   = $env:INPUT_ACTION_VERSION
    detector_version = $env:INPUT_DETECTOR_VERSION
    runner_os        = $env:RUNNER_OS
    runner_arch      = $env:RUNNER_ARCH
    repo_visibility  = $visibility
    repo_hash        = $hash
    grade            = $worst
    finding_count    = $count
    trigger          = $env:GITHUB_EVENT_NAME
    delta_enabled    = ($env:INPUT_DELTA_ENABLED -eq "true")
  } | ConvertTo-Json -Compress

  Invoke-RestMethod -Uri $ingestUrl -Method Post -Body $payload -ContentType "application/json" -TimeoutSec 3 | Out-Null
} catch {
  # Swallow all errors — fire-and-forget.
}
