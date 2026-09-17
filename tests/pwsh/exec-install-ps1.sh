#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
command -v pwsh >/dev/null 2>&1 || { echo "SKIP: native pwsh unavailable"; exit 77; }
pwsh -NoLogo -NoProfile -File "$ROOT/tests/pwsh/exec-install-ps1.ps1"
