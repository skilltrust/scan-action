#!/usr/bin/env bash
# Runs tests/pwsh/parse-all-ps1.ps1 over scripts/.
#
# Two modes, same check:
#   direct — `pwsh` on PATH. The CI path (GitHub's ubuntu runners ship
#            PowerShell 7 preinstalled). No Docker.
#   docker — fallback via mcr.microsoft.com/powershell:latest. How this runs
#            on a dev Mac with no local pwsh.
# The chosen mode is printed, so a log shows which one actually ran.
#
# Wired into ci.yml as the `pwsh-parse` job.
#
# Usage: ./tests/pwsh/parse-all-ps1.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if command -v pwsh > /dev/null 2>&1; then
  echo "parse-all-ps1: mode=direct (pwsh on PATH at $(command -v pwsh))"
  pwsh --version
  pwsh -NoProfile -File "$ROOT/tests/pwsh/parse-all-ps1.ps1" -Path "$ROOT/scripts"
else
  echo "parse-all-ps1: mode=docker (no pwsh on PATH; using mcr.microsoft.com/powershell:latest)"
  docker run --rm \
    -v "$ROOT:/w:ro" \
    mcr.microsoft.com/powershell:latest \
    pwsh -NoProfile -File /w/tests/pwsh/parse-all-ps1.ps1 -Path /w/scripts
fi
