$ErrorActionPreference = "Stop"

$commentFile = Join-Path $env:RUNNER_TEMP "comment.md"
$repo   = $env:INPUT_GITHUB_REPOSITORY
$pr     = $env:INPUT_PULL_NUMBER
$marker = "<!-- skilltrust:action:v1 -->"

if ($env:INPUT_IS_FORK_PR -eq "true") {
  Write-Host "report.ps1: fork PR detected; printing comment to log instead of posting"
  Write-Host "::group::SkillTrust comment (would-be)"
  Get-Content $commentFile | Write-Host
  Write-Host "::endgroup::"
  Write-Host "::warning title=SkillTrust::Trust Score commentary printed to job log (fork PR cannot post comments)"
  exit 0
}

# C9 — the Action yields to the App. See report.sh for the full reasoning;
# ADR-0002 requires this branch to exist in both scripts or Windows diverges.
$appMarker = "<!-- skilltrust:bot:v1 -->"
$appJq = '[.[] | select(.body | startswith("' + $appMarker + '"))][0].id'
$appComment = gh api "repos/$repo/issues/$pr/comments" --jq $appJq

if ($appComment -and $appComment -ne "null") {
  Write-Host "report.ps1: App comment present ($appComment); yielding"
  $oursJq = '[.[] | select(.body | startswith("' + $marker + '"))][0].id'
  $ours = gh api "repos/$repo/issues/$pr/comments" --jq $oursJq
  if ($ours -and $ours -ne "null") {
    $supersededFile = Join-Path $env:RUNNER_TEMP "comment.md.superseded"
    @(
      $marker
      "_Superseded by the SkillTrust GitHub App, which is commenting on this pull request. The Action is still running your checks; it just stopped duplicating the report._"
    ) | Set-Content -Path $supersededFile
    gh api -X PATCH "repos/$repo/issues/comments/$ours" -F "body=@$supersededFile" | Out-Null
    Write-Host "report.ps1: replaced our comment $ours with a superseded note"
  }
  exit 0
}

$existingJq = '[.[] | select(.body | startswith("' + $marker + '"))][0].id'
$existing = gh api "repos/$repo/issues/$pr/comments" --jq $existingJq

if ($existing -and $existing -ne "null") {
  Write-Host "report.ps1: PATCH existing comment $existing"
  gh api -X PATCH "repos/$repo/issues/comments/$existing" -F "body=@$commentFile" | Out-Null
} else {
  Write-Host "report.ps1: POST new comment"
  gh api "repos/$repo/issues/$pr/comments" -F "body=@$commentFile" | Out-Null
}
