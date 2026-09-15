$ErrorActionPreference = "Stop"

$commentFile = Join-Path $env:RUNNER_TEMP "comment.md"
$repo   = $env:INPUT_GITHUB_REPOSITORY
$pr     = $env:INPUT_PULL_NUMBER
$marker = "<!-- skilltrust:action:v1 -->"
$appMarker = "<!-- skilltrust:bot:v1 -->"
$commentsFile = Join-Path $env:RUNNER_TEMP "skilltrust-comments.json"

function Write-DeliveryWarning([string]$Reason) {
  Write-Host "::warning title=SkillTrust comment unavailable::$Reason; Job Summary and scan policy are unchanged"
}

if (!(Test-Path -LiteralPath $commentFile -PathType Leaf)) {
  Write-DeliveryWarning "rendered comment is unavailable"
  exit 0
}
if ($repo -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or $pr -notmatch '^\d+$') {
  Write-DeliveryWarning "pull request coordinates are invalid"
  exit 0
}

if (!$env:INPUT_HEAD_REPOSITORY -or !$env:INPUT_BASE_REPOSITORY) {
  Write-DeliveryWarning "pull request repository identity is unavailable"
  exit 0
}

if ($env:INPUT_HEAD_REPOSITORY -ne $env:INPUT_BASE_REPOSITORY) {
  Write-Host "report.ps1: fork PR detected; printing comment to log instead of posting"
  Write-Host "::group::SkillTrust comment (would-be)"
  Get-Content -LiteralPath $commentFile | ForEach-Object { Write-Host "| $_" }
  Write-Host "::endgroup::"
  Write-DeliveryWarning "fork PRs receive App delivery only; Action report printed inertly above"
  exit 0
}

if (!(Get-Command gh -ErrorAction SilentlyContinue)) {
  Write-DeliveryWarning "GitHub CLI is unavailable"
  exit 0
}
if (!$env:GH_TOKEN) {
  Write-DeliveryWarning "no writable GitHub token was provided"
  exit 0
}

Remove-Item -LiteralPath $commentsFile -Force -ErrorAction SilentlyContinue
try {
  & gh api --paginate --slurp "repos/$repo/issues/$pr/comments?per_page=100" > $commentsFile 2>$null
  if ($LASTEXITCODE -ne 0) { throw "lookup failed" }
  $document = [System.Text.Json.JsonDocument]::Parse((Get-Content -LiteralPath $commentsFile -Raw))
  try {
    if ($document.RootElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Array) { throw "invalid pages" }
    $appID = ""
    $oursID = ""
    foreach ($page in $document.RootElement.EnumerateArray()) {
      if ($page.ValueKind -ne [System.Text.Json.JsonValueKind]::Array) { throw "invalid page" }
      foreach ($comment in $page.EnumerateArray()) {
        if ($comment.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) { throw "invalid comment" }
        $bodyElement = [System.Text.Json.JsonElement]::new()
        $idElement = [System.Text.Json.JsonElement]::new()
        if (!$comment.TryGetProperty("body", [ref]$bodyElement) -or
            $bodyElement.ValueKind -ne [System.Text.Json.JsonValueKind]::String -or
            !$comment.TryGetProperty("id", [ref]$idElement)) { throw "invalid comment fields" }
        $id = 0L
        if (!$idElement.TryGetInt64([ref]$id) -or $id -le 0) { throw "invalid id" }
        $body = $bodyElement.GetString()
        if (!$appID -and $body.StartsWith($appMarker)) { $appID = [string]$id }
        if (!$oursID -and $body.StartsWith($marker)) { $oursID = [string]$id }
      }
    }
  } finally {
    $document.Dispose()
  }
} catch {
  Write-DeliveryWarning "GitHub comment lookup failed or returned an invalid response"
  exit 0
}

if ($appID) {
  Write-Host "report.ps1: App comment present ($appID); yielding"
  if ($oursID) {
    $supersededFile = Join-Path $env:RUNNER_TEMP "comment.md.superseded"
    @(
      $marker
      "_Superseded by the SkillTrust GitHub App, which is commenting on this pull request. The Action is still running your checks; it just stopped duplicating the report._"
    ) | Set-Content -LiteralPath $supersededFile
    try {
      & gh api -X PATCH "repos/$repo/issues/comments/$oursID" -F "body=@$supersededFile" > $null 2>$null
      if ($LASTEXITCODE -ne 0) { throw "patch failed" }
    } catch {
      Write-DeliveryWarning "GitHub comment update failed while yielding to the App"
      exit 0
    }
    Write-Host "report.ps1: replaced our comment $oursID with a superseded note"
  }
  exit 0
}

try {
  if ($oursID) {
    Write-Host "report.ps1: PATCH existing comment $oursID"
    & gh api -X PATCH "repos/$repo/issues/comments/$oursID" -F "body=@$commentFile" > $null 2>$null
  } else {
    Write-Host "report.ps1: POST new comment"
    & gh api "repos/$repo/issues/$pr/comments" -F "body=@$commentFile" > $null 2>$null
  }
  if ($LASTEXITCODE -ne 0) { throw "write failed" }
} catch {
  Write-DeliveryWarning "GitHub comment delivery failed"
  exit 0
}
