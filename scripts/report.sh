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

# C9 — the Action yields to the App. The two sticky markers differ by design
# (ADR-0004: the Action's marker is a wire contract and cannot change), so a
# repository running both would otherwise carry two grade comments in every
# pull request. The App is the authoritative one: it scans on our servers, has
# history and can triage.
APP_MARKER="<!-- skilltrust:bot:v1 -->"
APP_COMMENT_ID="$(gh api "repos/$REPO/issues/$PR/comments" \
  --jq '.[] | select(.body | startswith("'"$APP_MARKER"'")) | .id' | head -n 1 || true)"

if [ -n "$APP_COMMENT_ID" ]; then
  echo "report.sh: App comment present ($APP_COMMENT_ID); yielding"
  OURS="$(gh api "repos/$REPO/issues/$PR/comments" \
    --jq '.[] | select(.body | startswith("'"$MARKER"'")) | .id' | head -n 1 || true)"
  if [ -n "$OURS" ]; then
    # Leaving our last grade in place would read as a second, disagreeing bot.
    # Replacing it is the only outcome that is neither a duplicate nor a stale
    # verdict; deleting is irreversible and fails on a read-only token.
    {
      echo "$MARKER"
      echo "_Superseded by the SkillTrust GitHub App, which is commenting on this pull request. The Action is still running your checks; it just stopped duplicating the report._"
    } > "$RUNNER_TEMP/comment.md.superseded"
    gh api -X PATCH "repos/$REPO/issues/comments/$OURS" \
      -F body=@"$RUNNER_TEMP/comment.md.superseded" > /dev/null
    echo "report.sh: replaced our comment $OURS with a superseded note"
  fi
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
