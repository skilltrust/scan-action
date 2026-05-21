#!/usr/bin/env bash
set -euo pipefail

TEMPLATE_DIR="$(cd "$(dirname "$0")/.." && pwd)/templates"
SCAN="$INPUT_SCAN_JSON"
DELTA="${INPUT_DELTA_JSON:-}"
OUT="$RUNNER_TEMP/comment.md"

WORST_GRADE="$(jq -r '
  if (.axes // {}) | length > 0 then
    [.axes | to_entries[] | .value.grade] | sort | last
  else "—" end' "$SCAN")"
[ "$WORST_GRADE" = "null" ] && WORST_GRADE="—"

DETECTOR_VERSION="$(jq -r '.version // "unknown"' "$SCAN")"
[ "$DETECTOR_VERSION" = "null" ] && DETECTOR_VERSION="unknown"

GRADE_DELTA=""
WHY_BLOCK=""
RESOLVED_BLOCK=""

if [ -n "$DELTA" ] && [ -f "$DELTA" ]; then
  WORST_OLD="$(jq -r '
    if (.per_axis // {}) | length > 0 then
      [.per_axis | to_entries[] | .value.Old | select(. != "")] | sort | last
    else "" end' "$DELTA")"
  if [ -n "$WORST_OLD" ] && [ "$WORST_OLD" != "null" ]; then
    GRADE_DELTA=" (was $WORST_OLD)"
  fi

  AXIS_TABLE="| Axis | Grade | Δ |
|------|-------|---|
$(jq -r --slurpfile s "$SCAN" '
    (.per_axis // {}) | to_entries | sort_by(.key)
    | map(
        . as $row |
        ($s[0].axes[$row.key].grade // $row.value.New) as $g |
        (if $row.value.Direction == "same" or $row.value.Old == "" then "—"
         else (if $row.value.Direction == "up" then "↑" else "↓" end) + " " + $row.value.Old + " → " + $row.value.New end) as $delta |
        "| \($row.key) | \($g) | \($delta) |"
      ) | join("\n")' "$DELTA")"

  WHY="$(jq -r '
    (.axis_explanations // {}) | to_entries | sort_by(.key)
    | map("- **\(.key):** \(.value)") | join("\n")' "$DELTA")"
  if [ -n "$WHY" ] && [ "$WHY" != "null" ]; then
    WHY_BLOCK="**Why downgraded:**
$WHY"
  fi

  RESOLVED_COUNT="$(jq -r '.resolved_findings | length // 0' "$DELTA")"
  if [ "$RESOLVED_COUNT" -gt 0 ]; then
    RESOLVED_BLOCK="**Resolved ($RESOLVED_COUNT):**
$(jq -r '.resolved_findings | map("- ✅ `" + .rule_id + "` " + (.axis // "") + " — " + (.description // "")) | join("\n")' "$DELTA")"
  fi
else
  AXIS_TABLE="| Axis | Grade |
|------|-------|
$(jq -r '
    if (.axes // {}) | length > 0 then
      .axes | to_entries | sort_by(.key)
        | map("| \(.key) | \(.value.grade) |") | join("\n")
    else "| _no axes_ | — |" end' "$SCAN")"
fi

FINDING_COUNT="$(jq -r '.findings | length' "$SCAN")"
if [ "$FINDING_COUNT" -eq 0 ]; then
  FINDINGS_BLOCK="_No findings._"
else
  FINDINGS_BLOCK="**Findings ($FINDING_COUNT):**
$(jq -r '.findings | sort_by(.severity, .rule_id)[:10]
    | map("- `" + .rule_id + "` " + (.axis // "") + " · `" + (.file_path // "") + ":" + (.line | tostring) + "` — " + (.description // "")) | join("\n")' "$SCAN")"
fi

export WORST_GRADE AXIS_TABLE FINDINGS_BLOCK RESOLVED_BLOCK GRADE_DELTA WHY_BLOCK DETECTOR_VERSION

python3 -c "
import os, sys
src = open(sys.argv[1]).read()
out = (src
    .replace('__GRADE__',            os.environ['WORST_GRADE'])
    .replace('__GRADE_DELTA__',      os.environ['GRADE_DELTA'])
    .replace('__AXIS_TABLE__',       os.environ['AXIS_TABLE'])
    .replace('__WHY_BLOCK__',        os.environ['WHY_BLOCK'])
    .replace('__FINDINGS_BLOCK__',   os.environ['FINDINGS_BLOCK'])
    .replace('__RESOLVED_BLOCK__',   os.environ['RESOLVED_BLOCK'])
    .replace('__DETECTOR_VERSION__', os.environ['DETECTOR_VERSION']))
open(sys.argv[2], 'w').write(out)
" "$TEMPLATE_DIR/comment.md.tmpl" "$OUT"

echo "render-comment.sh: comment.md written to $OUT (delta=$([ -n "$DELTA" ] && echo yes || echo no))"
