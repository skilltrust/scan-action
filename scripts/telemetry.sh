#!/usr/bin/env bash
# Fire-and-forget anonymous install heartbeat. Never fails the action.
set +e

INGEST_URL="${INPUT_TELEMETRY_URL:-https://skilltrust.io/api/telemetry/action-run}"
SCAN="$INPUT_SCAN_JSON"

if [ -z "$SCAN" ] || [ ! -f "$SCAN" ]; then
  exit 0
fi

GRADE="$(jq -r '
  if .axes then [.axes | to_entries[] | .value.grade] | sort | last
  else "" end' "$SCAN")"
[ "$GRADE" = "null" ] && GRADE=""
FINDING_COUNT="$(jq -r '.findings | length // 0' "$SCAN")"

REPO_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-unknown/unknown}"
REPO_HASH="$(printf '%s' "$REPO_URL" | shasum -a 256 | awk '{print $1}')"

VISIBILITY="public"
if [ "${GITHUB_REPOSITORY_VISIBILITY:-public}" != "public" ]; then
  VISIBILITY="private"
fi

PAYLOAD="$(jq -nc \
  --arg av  "${INPUT_ACTION_VERSION:-unknown}" \
  --arg dv  "${INPUT_DETECTOR_VERSION:-unknown}" \
  --arg os  "${RUNNER_OS:-unknown}" \
  --arg ar  "${RUNNER_ARCH:-unknown}" \
  --arg vis "$VISIBILITY" \
  --arg rh  "$REPO_HASH" \
  --arg g   "$GRADE" \
  --argjson fc "$FINDING_COUNT" \
  --arg trg "${GITHUB_EVENT_NAME:-unknown}" \
  --argjson de "${INPUT_DELTA_ENABLED:-false}" \
  '{
    action_version:   $av,
    detector_version: $dv,
    runner_os:        $os,
    runner_arch:      $ar,
    repo_visibility:  $vis,
    repo_hash:        $rh,
    grade:            $g,
    finding_count:    $fc,
    trigger:          $trg,
    delta_enabled:    $de
  }')"

echo "telemetry.sh: POST $INGEST_URL"
curl -fsS --max-time 3 -H "Content-Type: application/json" -X POST --data "$PAYLOAD" "$INGEST_URL" >/dev/null 2>&1 || true

exit 0
