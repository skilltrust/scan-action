#!/usr/bin/env bash

# Shared test helpers. Sourced by .bats files via `load helpers`.

setup_tmpdir() {
  TMPDIR_TEST="$(mktemp -d)"
  export TMPDIR_TEST
}

teardown_tmpdir() {
  [ -n "${TMPDIR_TEST:-}" ] && rm -rf "$TMPDIR_TEST"
}
