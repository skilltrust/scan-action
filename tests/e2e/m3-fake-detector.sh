#!/usr/bin/env bash
set -u

if [ "${1:-}" = version ]; then
  echo "skill-detector version 0.10.0 (M3 composite fixture)"
  exit 0
fi

if [ "${M3_FAKE_EXIT:-0}" = axis ]; then
  case " $* " in
    *' --fail-on-axis security=C '*) M3_FAKE_EXIT=2 ;;
    *' --fail-on-axis security=D '*) M3_FAKE_EXIT=1 ;;
    *) M3_FAKE_EXIT=3 ;;
  esac
fi

if [ "${M3_FAKE_NO_SURFACE:-false}" = true ]; then
  printf '%s' '{"findings":[],"no_agent_surface":true,"complete_marker":"kept"}'
  exit "${M3_FAKE_EXIT:-0}"
fi

if [ "${M3_FAKE_EXIT:-0}" = 0 ]; then
  findings='[]'
else
  findings='[{"rule_id":"SD-004","severity":"CRITICAL","effective_severity":"CRITICAL","description":"fixture","file_path":"SKILL.md","line":1,"diagnosis":"fixture","remediation":"fixture","complete_detail":"kept"}]'
fi
printf '{"axes":{"security":{"grade":"D"},"permission_hygiene":{"grade":"B"},"transparency":{"grade":"A"},"quality":{"grade":"C"}},"findings":%s,"complete_marker":"kept"}' "$findings"
exit "${M3_FAKE_EXIT:-0}"
