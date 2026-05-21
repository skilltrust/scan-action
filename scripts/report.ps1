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

$existing = gh api "repos/$repo/issues/$pr/comments" `
  --jq "[.[] | select(.body | startswith(\""+$marker+"\""))][0].id"

if ($existing -and $existing -ne "null") {
  Write-Host "report.ps1: PATCH existing comment $existing"
  gh api -X PATCH "repos/$repo/issues/comments/$existing" -F "body=@$commentFile" | Out-Null
} else {
  Write-Host "report.ps1: POST new comment"
  gh api "repos/$repo/issues/$pr/comments" -F "body=@$commentFile" | Out-Null
}
