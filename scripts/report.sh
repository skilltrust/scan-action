#!/usr/bin/env bash
set -euo pipefail

# Required env:
#   RUNNER_TEMP                  scratch dir; $RUNNER_TEMP/comment.md must exist
#   INPUT_GITHUB_REPOSITORY      "owner/repo"
#   INPUT_PULL_NUMBER            PR number
#   INPUT_HEAD_REPOSITORY        PR head repository full_name
#   INPUT_BASE_REPOSITORY        PR base repository full_name
# Optional: GH_TOKEN consumed by gh CLI for same-repository PRs only.

COMMENT_FILE="$RUNNER_TEMP/comment.md"
REPO="$INPUT_GITHUB_REPOSITORY"
PR="$INPUT_PULL_NUMBER"
MARKER="<!-- skilltrust:action:v1 -->"
APP_MARKER="<!-- skilltrust:bot:v1 -->"
COMMENTS="$RUNNER_TEMP/skilltrust-comments.json"

warn_delivery() {
  echo "::warning title=SkillTrust comment unavailable::$1; Job Summary and scan policy are unchanged"
}

if [ ! -f "$COMMENT_FILE" ]; then
  warn_delivery "rendered comment is unavailable"
  exit 0
fi
if ! [[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || ! [[ "$PR" =~ ^[0-9]+$ ]]; then
  warn_delivery "pull request coordinates are invalid"
  exit 0
fi

if [ -z "${INPUT_HEAD_REPOSITORY:-}" ] || [ -z "${INPUT_BASE_REPOSITORY:-}" ]; then
  warn_delivery "pull request repository identity is unavailable"
  exit 0
fi

if [ "$INPUT_HEAD_REPOSITORY" != "$INPUT_BASE_REPOSITORY" ]; then
  echo "report.sh: fork PR detected; printing comment to log instead of posting"
  echo "::group::SkillTrust comment (would-be)"
  sed 's/^/| /' "$COMMENT_FILE"
  echo "::endgroup::"
  warn_delivery "fork PRs receive App delivery only; Action report printed inertly above"
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  warn_delivery "GitHub CLI is unavailable"
  exit 0
fi
if [ -z "${GH_TOKEN:-}" ]; then
  warn_delivery "no writable GitHub token was provided"
  exit 0
fi

# One paginated lookup establishes both App stand-off and sticky update state.
# A failed or malformed lookup can never fall through to POST: that would risk
# duplicates. API diagnostics are intentionally not replayed into the log.
rm -f "$COMMENTS"
if ! gh api --paginate --slurp "repos/$REPO/issues/$PR/comments?per_page=100" > "$COMMENTS" 2>/dev/null; then
  warn_delivery "GitHub comment lookup failed"
  exit 0
fi
if ! jq -e 'type == "array" and all(.[]; type == "array")' "$COMMENTS" >/dev/null 2>&1; then
  warn_delivery "GitHub comment lookup returned an invalid response"
  exit 0
fi

APP_COMMENT_ID="$(jq -r --arg marker "$APP_MARKER" '[.[][] | select((.body | type) == "string" and (.body | startswith($marker)))][0].id // empty' "$COMMENTS")"
OURS="$(jq -r --arg marker "$MARKER" '[.[][] | select((.body | type) == "string" and (.body | startswith($marker)))][0].id // empty' "$COMMENTS")"
if { [ -n "$APP_COMMENT_ID" ] && ! [[ "$APP_COMMENT_ID" =~ ^[0-9]+$ ]]; } ||
   { [ -n "$OURS" ] && ! [[ "$OURS" =~ ^[0-9]+$ ]]; }; then
  warn_delivery "GitHub comment lookup returned an invalid identifier"
  exit 0
fi

if [ -n "$APP_COMMENT_ID" ]; then
  echo "report.sh: App comment present ($APP_COMMENT_ID); yielding"
  if [ -n "$OURS" ]; then
    # Leaving our last grade in place would read as a second, disagreeing bot.
    # Replacing it is the only outcome that is neither a duplicate nor a stale
    # verdict; deleting is irreversible and fails on a read-only token.
    {
      echo "$MARKER"
      echo "_Superseded by the SkillTrust GitHub App, which is commenting on this pull request. The Action is still running your checks; it just stopped duplicating the report._"
    } > "$RUNNER_TEMP/comment.md.superseded"
    if ! gh api -X PATCH "repos/$REPO/issues/comments/$OURS" \
      -F body=@"$RUNNER_TEMP/comment.md.superseded" > /dev/null 2>&1; then
      warn_delivery "GitHub comment update failed while yielding to the App"
      exit 0
    fi
    echo "report.sh: replaced our comment $OURS with a superseded note"
  fi
  exit 0
fi

if [ -n "$OURS" ]; then
  echo "report.sh: PATCH existing comment $OURS"
  if ! gh api -X PATCH "repos/$REPO/issues/comments/$OURS" \
    -F body=@"$COMMENT_FILE" > /dev/null 2>&1; then
    warn_delivery "GitHub comment update failed"
    exit 0
  fi
else
  echo "report.sh: POST new comment"
  if ! gh api "repos/$REPO/issues/$PR/comments" \
    -F body=@"$COMMENT_FILE" > /dev/null 2>&1; then
    warn_delivery "GitHub comment creation failed"
    exit 0
  fi
fi

echo "report.sh: done"
