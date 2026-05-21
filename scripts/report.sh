#!/usr/bin/env bash
set -euo pipefail

# Required env:
#   RUNNER_TEMP                  scratch dir; $RUNNER_TEMP/comment.md must exist
#   INPUT_GITHUB_REPOSITORY      "owner/repo"
#   INPUT_PULL_NUMBER            PR number
# Optional:
#   INPUT_IS_FORK_PR             "true" → skip API, print to log
#   GH_TOKEN / GITHUB_TOKEN      consumed by gh CLI

COMMENT_FILE="$RUNNER_TEMP/comment.md"
REPO="$INPUT_GITHUB_REPOSITORY"
PR="$INPUT_PULL_NUMBER"
MARKER="<!-- skilltrust:action:v1 -->"

if [ "${INPUT_IS_FORK_PR:-false}" = "true" ]; then
  echo "report.sh: fork PR detected; printing comment to log instead of posting"
  echo "::group::SkillTrust comment (would-be)"
  cat "$COMMENT_FILE"
  echo "::endgroup::"
  echo "::warning title=SkillTrust::Trust Score commentary printed to job log (fork PR cannot post comments)"
  exit 0
fi

# Find existing marker comment.
EXISTING_ID="$(gh api "repos/$REPO/issues/$PR/comments" \
  --jq '.[] | select(.body | startswith("'"$MARKER"'")) | .id' | head -n 1 || true)"

if [ -n "$EXISTING_ID" ]; then
  echo "report.sh: PATCH existing comment $EXISTING_ID"
  gh api -X PATCH "repos/$REPO/issues/comments/$EXISTING_ID" \
    -F body=@"$COMMENT_FILE" > /dev/null
else
  echo "report.sh: POST new comment"
  gh api "repos/$REPO/issues/$PR/comments" \
    -F body=@"$COMMENT_FILE" > /dev/null
fi

echo "report.sh: done"
