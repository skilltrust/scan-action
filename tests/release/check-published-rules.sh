#!/usr/bin/env bash
set -euo pipefail

# Release-only provenance check. Runtime rendering never fetches the site.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BASE="${SKILLTRUST_SITE_URL:-https://skilltrust.app}"

while IFS= read -r id; do
  [[ "$id" =~ ^SD-0[0-9][0-9]$ ]] || continue
  url="$BASE/rules/${id,,}"
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$url")"
  if [ "$code" != 200 ]; then
    echo "$url returned HTTP $code; do not release links for an unpublished rule" >&2
    exit 1
  fi
done < "$ROOT/config/published-rule-ids.txt"

echo "published rule pages match the checked-in allowlist"
