#!/usr/bin/env bash

# Shared test helpers. Sourced by .bats files via `load helpers`.

setup_tmpdir() {
  TMPDIR_TEST="$(mktemp -d)"
  export TMPDIR_TEST
}

teardown_tmpdir() {
  [ -n "${TMPDIR_TEST:-}" ] && rm -rf "$TMPDIR_TEST"
}

graded_scan_json() {
  local findings="${1:-[]}" quality="${2:-A}"
  jq -nc --argjson findings "$findings" --arg quality "$quality" '{
    findings: $findings,
    axes: {
      security: {grade:"A"}, permission_hygiene: {grade:"B"},
      transparency: {grade:"C"}, quality: {grade:$quality}
    }, files_scanned:1, rules_applied:24, version:"0.10.0"
  }'
}
