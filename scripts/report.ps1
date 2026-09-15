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
  $pages = Get-Content -LiteralPath $commentsFile -Raw | ConvertFrom-Json
  if ($pages -isnot [array]) { throw "invalid pages" }
  $comments = @($pages | ForEach-Object { @($_) })
  $appComment = @($comments | Where-Object { $_.body -is [string] -and $_.body.StartsWith($appMarker) } | Select-Object -First 1)[0]
  $oursComment = @($comments | Where-Object { $_.body -is [string] -and $_.body.StartsWith($marker) } | Select-Object -First 1)[0]
  $appID = if ($appComment) { [string]$appComment.id } else { "" }
  $oursID = if ($oursComment) { [string]$oursComment.id } else { "" }
  if (($appID -and $appID -notmatch '^\d+$') -or ($oursID -and $oursID -notmatch '^\d+$')) { throw "invalid id" }
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
