#!/usr/bin/env bash
set -euo pipefail

TEMPLATE_DIR="$(cd "$(dirname "$0")/.." && pwd)/templates"
SCAN="$INPUT_SCAN_JSON"
OUT="$RUNNER_TEMP/comment.md"

WORST_GRADE="$(jq -r '
  if (.axes // {}) | length > 0 then
    [.axes | to_entries[] | .value.grade] | sort | last
  else "—" end' "$SCAN")"
[ "$WORST_GRADE" = "null" ] && WORST_GRADE="—"

DETECTOR_VERSION="$(jq -r '.version // "unknown"' "$SCAN")"
[ "$DETECTOR_VERSION" = "null" ] && DETECTOR_VERSION="unknown"

AXIS_ROWS="$(jq -r '
  if (.axes // {}) | length > 0 then
    .axes | to_entries | sort_by(.key)
      | map("| \(.key) | \(.value.grade) |") | join("\n")
  else "| _no axes_ | — |" end' "$SCAN")"

FINDING_COUNT="$(jq -r '.findings | length' "$SCAN")"

if [ "$FINDING_COUNT" -eq 0 ]; then
  FINDINGS_BLOCK="_No findings._"
else
  FINDINGS_BLOCK="$(jq -r '
    "**Findings (" + (.findings | length | tostring) + "):**\n" +
    (.findings | sort_by(.severity, .rule_id)[:10]
      | map("- `" + .rule_id + "` " + (.axis // "") + " · `" + (.file_path // "") + ":" + (.line | tostring) + "` — " + (.description // "")) | join("\n"))
  ' "$SCAN")"
fi

export WORST_GRADE AXIS_ROWS FINDINGS_BLOCK DETECTOR_VERSION

python3 -c "
import os, sys
src = open(sys.argv[1]).read()
out = (src
    .replace('__GRADE__',            os.environ['WORST_GRADE'])
    .replace('__AXIS_ROWS__',        os.environ['AXIS_ROWS'])
    .replace('__FINDINGS_BLOCK__',   os.environ['FINDINGS_BLOCK'])
    .replace('__DETECTOR_VERSION__', os.environ['DETECTOR_VERSION']))
open(sys.argv[2], 'w').write(out)
" "$TEMPLATE_DIR/comment.md.tmpl" "$OUT"

echo "render-comment.sh: comment.md written to $OUT"
