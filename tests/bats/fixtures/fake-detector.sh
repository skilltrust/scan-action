#!/usr/bin/env bash
# Pretends to be `skill-detector`. Reads $FAKE_DETECTOR_EXIT for exit code
# and emits $FAKE_DETECTOR_JSON to stdout when scanning, or version info on
# `version`.
_default_json='{"findings":[],"axes":{},"files_scanned":0,"rules_applied":0}'
case "${1:-}" in
  version)
    echo "skill-detector version 0.3.0 (fake)"
    exit 0
    ;;
  scan)
    echo "${FAKE_DETECTOR_JSON:-$_default_json}"
    exit "${FAKE_DETECTOR_EXIT:-0}"
    ;;
  *)
    echo "fake-detector: unknown subcommand $1" >&2
    exit 2
    ;;
esac
