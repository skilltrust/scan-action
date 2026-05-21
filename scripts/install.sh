#!/usr/bin/env bash
set -euo pipefail

# Required env from GitHub Actions runner:
#   RUNNER_OS         Linux | macOS | Windows
#   RUNNER_ARCH       X64 | ARM64
#   RUNNER_TEMP       Per-run scratch dir
# Required env from action inputs (set by action.yml):
#   INPUT_DETECTOR_VERSION   e.g. "v0.3.0" or "latest" (resolved to a real tag)
#
# Side effects: places `skill-detector` on $PATH for subsequent steps by
# writing the extracted dir to $GITHUB_PATH.

VERSION="${INPUT_DETECTOR_VERSION:-}"
if [ -z "$VERSION" ]; then
  echo "install.sh: INPUT_DETECTOR_VERSION must be set" >&2
  exit 1
fi

case "$RUNNER_OS" in
  Linux)   OS=linux  ;;
  macOS)   OS=darwin ;;
  *)       echo "install.sh: unsupported RUNNER_OS: $RUNNER_OS" >&2; exit 1 ;;
esac

case "$RUNNER_ARCH" in
  X64)   ARCH=amd64 ;;
  ARM64) ARCH=arm64 ;;
  *)     echo "install.sh: unsupported RUNNER_ARCH: $RUNNER_ARCH" >&2; exit 1 ;;
esac

BASE="https://github.com/velzepooz/skill-detector/releases/download/${VERSION}"
# GoReleaser asset name includes the version (without 'v' prefix), e.g.
# skill-detector_0.3.1_linux_amd64.tar.gz
ASSET="skill-detector_${VERSION#v}_${OS}_${ARCH}.tar.gz"
DEST="$RUNNER_TEMP/skill-detector-install"

mkdir -p "$DEST"
echo "install.sh: downloading $BASE/$ASSET"
curl -fsSL --retry 3 -o "$DEST/$ASSET"        "$BASE/$ASSET"
curl -fsSL --retry 3 -o "$DEST/checksums.txt" "$BASE/checksums.txt"

( cd "$DEST" && sha256sum --check --ignore-missing checksums.txt 2>/dev/null \
                 || shasum -a 256 --check --ignore-missing checksums.txt )

tar -xzf "$DEST/$ASSET" -C "$DEST"

# Append the extraction dir to PATH for subsequent steps in this job.
if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$DEST" >> "$GITHUB_PATH"
fi
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "SCAN_ACTION_DETECTOR_DIR=$DEST" >> "$GITHUB_ENV"
fi

echo "install.sh: skill-detector installed at $DEST"
