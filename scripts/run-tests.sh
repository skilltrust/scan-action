#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BATS_DIR="$ROOT/.bats-tmp/bats-core"

if [ ! -d "$BATS_DIR" ]; then
  mkdir -p "$ROOT/.bats-tmp"
  git clone --depth 1 --branch v1.11.0 https://github.com/bats-core/bats-core.git "$BATS_DIR"
fi

"$BATS_DIR/bin/bats" "$ROOT/tests/bats/"
