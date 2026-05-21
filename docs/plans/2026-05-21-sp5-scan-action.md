# SP-5 `skilltrust/scan-action@v1` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `skilltrust/scan-action@v1` — a composite GitHub Action that runs the `skill-detector` scanner inside the customer's CI runner, posts a sticky PR comment, sets a build status, and (optionally) shows delta-vs-base — while extracting the delta logic into a shared `skill-detector/pkg/delta` library and adding an install-counting telemetry endpoint to `skillmoss-go`.

**Architecture:** Composite shell action (bash + pwsh) downloads the pinned `skill-detector` binary, scans the checked-out tree, parses JSON, and reports via `gh api`. Delta logic lives in a new `skill-detector/pkg/delta` package (consumed by both the new `skill-detector delta` CLI sub-command AND `skillmoss-go/internal/prbot` after a zero-behavior-change refactor). Install counting via fire-and-forget POST to a new `skillmoss-go` endpoint.

**Tech Stack:** Go 1.26 (skill-detector + skillmoss-go), bash + pwsh (action scripts), bats-core (shell unit tests), GitHub Actions composite format, `gh` CLI for GitHub API, pgx (skillmoss-go DB).

**Reference spec:** `docs/superpowers/specs/2026-05-21-sp5-scan-action-design.md`

**Build order:** A → B → C → D → E. Each phase is independently committable; later phases depend on earlier ones.

| Phase | Repo(s) | Slice | Outcome |
|---|---|---|---|
| **A** | `scan-action/` (new) | S1 | Composite action scaffold; downloads + runs scanner; exit code propagates |
| **B** | `scan-action/` | S2 | Sticky PR comment via `gh api` (no delta yet) |
| **C** | `skill-detector/`, `skillmoss-go/` | S3 | `pkg/delta` library + CLI sub-command; skillmoss-go consumes library (zero-behavior-change) |
| **D** | `scan-action/` | S4 | Action `delta: true` input; comment shows ↑/↓ vs base |
| **E** | `skillmoss-go/`, `scan-action/` | S5 | Telemetry endpoint + opt-out POST; Windows runner; tag v1.0.0 + Marketplace submit |

---

## Pre-flight

Repos live at:

- `/Users/glibrulev/projects/saas/skil security/skill-detector/` — exists, current at v0.4.x (or wherever it is after SP-4)
- `/Users/glibrulev/projects/saas/skil security/skillmoss-go/` — exists, at v0.4.0
- `/Users/glibrulev/projects/saas/skil security/scan-action/` — **does not exist yet** (created in Phase A)

The project root (`skil security/`) is not a git repo. Each substrate repo is independent.

Test commands:

- `skill-detector`: `go test ./...`
- `skillmoss-go`: `go test ./... -p 1` with `TEST_DATABASE_URL=postgres://skillmoss:skillmoss@localhost:5432/skillmoss_test?sslmode=disable`
- `scan-action`: `bats tests/bats/` (after we add bats-core); end-to-end via Actions matrix CI

---

# Phase A — Action scaffold (Slice S1)

Goal: A composite action that downloads `skill-detector`, runs it against the checked-out tree, prints output to the job log, and exits with the detector's exit code. No comment, no delta, no telemetry.

## Task A1: Initialize the `scan-action` repo

**Files:**
- Create: `scan-action/.gitignore`
- Create: `scan-action/LICENSE`
- Create: `scan-action/README.md`
- Create: `scan-action/CHANGELOG.md`

- [ ] **Step 1: Create the directory and initialize git**

```bash
cd "/Users/glibrulev/projects/saas/skil security"
mkdir scan-action
cd scan-action
git init -b main
```

- [ ] **Step 2: Add `.gitignore`**

Create `scan-action/.gitignore`:

```
.DS_Store
*.log
tmp/
.bats-tmp/
```

- [ ] **Step 3: Add MIT LICENSE**

Create `scan-action/LICENSE` with the standard MIT license body, copyright holder `SkillTrust`, year `2026`.

- [ ] **Step 4: Add minimal README placeholder**

Create `scan-action/README.md`:

```markdown
# skilltrust/scan-action

GitHub Action that scans AI-agent configuration files (SKILL.md, CLAUDE.md, .claude/, .mcp.json) for security threats using [skill-detector](https://github.com/velzepooz/skill-detector).

**Status:** in development (pre-v1).

## Quickstart

Coming soon.
```

- [ ] **Step 5: Add CHANGELOG.md**

Create `scan-action/CHANGELOG.md`:

```markdown
# Changelog

## [Unreleased]
```

- [ ] **Step 6: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
git add .gitignore LICENSE README.md CHANGELOG.md
git commit -m "chore: initialize scan-action repo skeleton"
```

## Task A2: Add bats-core test harness

**Files:**
- Create: `scan-action/tests/bats/helpers.bash`
- Create: `scan-action/tests/bats/smoke.bats`
- Create: `scan-action/scripts/run-tests.sh`

- [ ] **Step 1: Write the failing smoke test**

Create `scan-action/tests/bats/smoke.bats`:

```bash
#!/usr/bin/env bats

@test "bats is wired" {
  run echo "hello"
  [ "$status" -eq 0 ]
  [ "$output" = "hello" ]
}
```

- [ ] **Step 2: Add helpers stub**

Create `scan-action/tests/bats/helpers.bash`:

```bash
#!/usr/bin/env bash

# Shared test helpers. Sourced by .bats files via `load helpers`.

setup_tmpdir() {
  TMPDIR_TEST="$(mktemp -d)"
  export TMPDIR_TEST
}

teardown_tmpdir() {
  [ -n "${TMPDIR_TEST:-}" ] && rm -rf "$TMPDIR_TEST"
}
```

- [ ] **Step 3: Add `run-tests.sh` that bootstraps bats-core if missing**

Create `scan-action/scripts/run-tests.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BATS_DIR="$ROOT/.bats-tmp/bats-core"

if [ ! -d "$BATS_DIR" ]; then
  mkdir -p "$ROOT/.bats-tmp"
  git clone --depth 1 --branch v1.11.0 https://github.com/bats-core/bats-core.git "$BATS_DIR"
fi

"$BATS_DIR/bin/bats" "$ROOT/tests/bats/"
```

```bash
chmod +x "/Users/glibrulev/projects/saas/skil security/scan-action/scripts/run-tests.sh"
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
./scripts/run-tests.sh
```

Expected: `1 test, 0 failures`.

- [ ] **Step 5: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
git add tests/bats/ scripts/run-tests.sh
git commit -m "test: add bats-core harness with smoke test"
```

## Task A3: `install.sh` — download + verify the skill-detector binary

**Files:**
- Create: `scan-action/scripts/install.sh`
- Create: `scan-action/tests/bats/install.bats`

- [ ] **Step 1: Write the failing test**

Create `scan-action/tests/bats/install.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() { setup_tmpdir; }
teardown() { teardown_tmpdir; }

@test "install.sh: rejects unknown RUNNER_OS" {
  RUNNER_OS=AmigaOS RUNNER_ARCH=X64 \
    RUNNER_TEMP="$TMPDIR_TEST" \
    INPUT_DETECTOR_VERSION=v0.2.1 \
    run bash "$BATS_TEST_DIRNAME/../../scripts/install.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported RUNNER_OS"* ]]
}

@test "install.sh: rejects unknown RUNNER_ARCH" {
  RUNNER_OS=Linux RUNNER_ARCH=PowerPC \
    RUNNER_TEMP="$TMPDIR_TEST" \
    INPUT_DETECTOR_VERSION=v0.2.1 \
    run bash "$BATS_TEST_DIRNAME/../../scripts/install.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported RUNNER_ARCH"* ]]
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
./scripts/run-tests.sh
```

Expected: both tests fail because `install.sh` does not exist yet.

- [ ] **Step 3: Write `install.sh`**

Create `scan-action/scripts/install.sh`:

```bash
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
ASSET="skill-detector_${OS}_${ARCH}.tar.gz"
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
echo "SCAN_ACTION_DETECTOR_DIR=$DEST" >> "${GITHUB_ENV:-/dev/null}"

echo "install.sh: skill-detector installed at $DEST"
```

```bash
chmod +x "/Users/glibrulev/projects/saas/skil security/scan-action/scripts/install.sh"
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
./scripts/run-tests.sh
```

Expected: both `install.sh` tests pass.

- [ ] **Step 5: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
git add scripts/install.sh tests/bats/install.bats
git commit -m "feat: install.sh downloads and verifies skill-detector binary"
```

## Task A4: `install.ps1` — Windows variant

**Files:**
- Create: `scan-action/scripts/install.ps1`

**Note:** PowerShell scripts run on `windows-latest` runners only and can't be unit-tested from bats on Linux. We rely on the matrix CI in Phase E to validate this. For now, write the script to mirror `install.sh` logic.

- [ ] **Step 1: Write `install.ps1`**

Create `scan-action/scripts/install.ps1`:

```powershell
$ErrorActionPreference = "Stop"

# Required env from runner: RUNNER_ARCH, RUNNER_TEMP, INPUT_DETECTOR_VERSION

$version = $env:INPUT_DETECTOR_VERSION
if (-not $version) { throw "install.ps1: INPUT_DETECTOR_VERSION must be set" }

switch ($env:RUNNER_ARCH) {
  "X64"   { $arch = "amd64" }
  "ARM64" { $arch = "arm64" }
  default { throw "install.ps1: unsupported RUNNER_ARCH: $($env:RUNNER_ARCH)" }
}

$base  = "https://github.com/velzepooz/skill-detector/releases/download/$version"
$asset = "skill-detector_windows_${arch}.zip"
$dest  = Join-Path $env:RUNNER_TEMP "skill-detector-install"

New-Item -ItemType Directory -Force -Path $dest | Out-Null

Write-Host "install.ps1: downloading $base/$asset"
Invoke-WebRequest -Uri "$base/$asset"        -OutFile (Join-Path $dest $asset)        -UseBasicParsing
Invoke-WebRequest -Uri "$base/checksums.txt" -OutFile (Join-Path $dest "checksums.txt") -UseBasicParsing

# Verify sha256
$expected = (Get-Content (Join-Path $dest "checksums.txt") |
             Where-Object { $_ -match [regex]::Escape($asset) }) -split '\s+' | Select-Object -First 1
if (-not $expected) { throw "install.ps1: $asset not found in checksums.txt" }
$actual = (Get-FileHash -Algorithm SHA256 (Join-Path $dest $asset)).Hash.ToLower()
if ($expected.ToLower() -ne $actual) { throw "install.ps1: checksum mismatch for $asset" }

Expand-Archive -Path (Join-Path $dest $asset) -DestinationPath $dest -Force

# Append the extraction dir to PATH for subsequent steps.
if ($env:GITHUB_PATH) { Add-Content -Path $env:GITHUB_PATH -Value $dest }
if ($env:GITHUB_ENV)  { Add-Content -Path $env:GITHUB_ENV  -Value "SCAN_ACTION_DETECTOR_DIR=$dest" }

Write-Host "install.ps1: skill-detector installed at $dest"
```

- [ ] **Step 2: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
git add scripts/install.ps1
git commit -m "feat: install.ps1 Windows variant of binary install"
```

## Task A5: `scan.sh` — invoke skill-detector and capture JSON

**Files:**
- Create: `scan-action/scripts/scan.sh`
- Create: `scan-action/tests/bats/scan.bats`
- Create: `scan-action/tests/bats/fixtures/fake-detector.sh`

- [ ] **Step 1: Write a fake detector for tests**

Create `scan-action/tests/bats/fixtures/fake-detector.sh`:

```bash
#!/usr/bin/env bash
# Pretends to be `skill-detector`. Reads $FAKE_DETECTOR_EXIT for exit code
# and emits $FAKE_DETECTOR_JSON to stdout when scanning, or version info on
# `version`.
case "${1:-}" in
  version)
    echo "skill-detector version 0.3.0 (fake)"
    exit 0
    ;;
  scan)
    cat <<EOF
${FAKE_DETECTOR_JSON:-{"findings":[],"axes":{},"files_scanned":0,"rules_applied":0}}
EOF
    exit "${FAKE_DETECTOR_EXIT:-0}"
    ;;
  *)
    echo "fake-detector: unknown subcommand $1" >&2
    exit 2
    ;;
esac
```

```bash
chmod +x "/Users/glibrulev/projects/saas/skil security/scan-action/tests/bats/fixtures/fake-detector.sh"
```

- [ ] **Step 2: Write the failing tests**

Create `scan-action/tests/bats/scan.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() {
  setup_tmpdir
  # Put fake-detector on PATH as `skill-detector`.
  cp "$BATS_TEST_DIRNAME/fixtures/fake-detector.sh" "$TMPDIR_TEST/skill-detector"
  chmod +x "$TMPDIR_TEST/skill-detector"
  export PATH="$TMPDIR_TEST:$PATH"
  export RUNNER_TEMP="$TMPDIR_TEST"
  : > "$TMPDIR_TEST/github_env"
  export GITHUB_ENV="$TMPDIR_TEST/github_env"
  : > "$TMPDIR_TEST/github_output"
  export GITHUB_OUTPUT="$TMPDIR_TEST/github_output"
}
teardown() { teardown_tmpdir; }

@test "scan.sh: writes scan.json to RUNNER_TEMP" {
  export FAKE_DETECTOR_JSON='{"findings":[],"axes":{"security":{"grade":"A","rationale":""}},"files_scanned":1,"rules_applied":21}'
  export INPUT_PATH="."
  export INPUT_FAIL_ON="high"
  export INPUT_FAIL_ON_AXIS=""
  export INPUT_STRICT_MCP="false"
  export INPUT_SCAN_ALL="false"
  run bash "$BATS_TEST_DIRNAME/../../scripts/scan.sh"
  [ "$status" -eq 0 ]
  [ -f "$RUNNER_TEMP/scan.json" ]
  grep -q '"files_scanned":1' "$RUNNER_TEMP/scan.json"
}

@test "scan.sh: captures non-zero detector exit code into GITHUB_ENV without failing the step" {
  export FAKE_DETECTOR_EXIT=2
  export FAKE_DETECTOR_JSON='{"findings":[{"rule_id":"SD-001"}],"axes":{},"files_scanned":1,"rules_applied":21}'
  export INPUT_PATH="."
  export INPUT_FAIL_ON="high"
  export INPUT_FAIL_ON_AXIS=""
  export INPUT_STRICT_MCP="false"
  export INPUT_SCAN_ALL="false"
  run bash "$BATS_TEST_DIRNAME/../../scripts/scan.sh"
  [ "$status" -eq 0 ]
  grep -q "SCAN_EXIT_CODE=2" "$GITHUB_ENV"
}

@test "scan.sh: threads --fail-on-axis when set" {
  export FAKE_DETECTOR_JSON='{"findings":[],"axes":{},"files_scanned":0,"rules_applied":0}'
  export INPUT_PATH="."
  export INPUT_FAIL_ON="high"
  export INPUT_FAIL_ON_AXIS="permission_hygiene=C,security=C"
  export INPUT_STRICT_MCP="true"
  export INPUT_SCAN_ALL="true"
  export FAKE_DETECTOR_ECHO_ARGS=1
  # Replace fake with arg-echoing variant
  cat > "$TMPDIR_TEST/skill-detector" <<'EOF'
#!/usr/bin/env bash
echo "ARGS: $*" >&2
echo "${FAKE_DETECTOR_JSON}"
EOF
  chmod +x "$TMPDIR_TEST/skill-detector"
  run bash "$BATS_TEST_DIRNAME/../../scripts/scan.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--fail-on-axis permission_hygiene=C"* ]]
  [[ "$output" == *"--fail-on-axis security=C"* ]]
  [[ "$output" == *"--strict-mcp"* ]]
  [[ "$output" == *"--scan-all"* ]]
}
```

- [ ] **Step 3: Run to verify they fail**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
./scripts/run-tests.sh
```

Expected: 3 new tests fail because `scan.sh` does not exist.

- [ ] **Step 4: Write `scan.sh`**

Create `scan-action/scripts/scan.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Required env:
#   RUNNER_TEMP                  scratch dir
#   GITHUB_ENV                   path appended-to to set step env
#   GITHUB_OUTPUT                path appended-to to set action outputs
# Action inputs (from action.yml):
#   INPUT_PATH                   scan target path
#   INPUT_FAIL_ON                severity threshold
#   INPUT_FAIL_ON_AXIS           comma-separated axis=grade specs (may be empty)
#   INPUT_STRICT_MCP             "true" | "false"
#   INPUT_SCAN_ALL               "true" | "false"

SCAN_PATH="${INPUT_PATH:-.}"
FAIL_ON="${INPUT_FAIL_ON:-high}"

ARGS=( "scan" "$SCAN_PATH" "--format" "json" "--fail-on" "$FAIL_ON" )

if [ -n "${INPUT_FAIL_ON_AXIS:-}" ]; then
  IFS=',' read -ra AXIS_SPECS <<< "$INPUT_FAIL_ON_AXIS"
  for spec in "${AXIS_SPECS[@]}"; do
    spec="$(echo "$spec" | xargs)"  # trim whitespace
    [ -n "$spec" ] && ARGS+=( "--fail-on-axis" "$spec" )
  done
fi

[ "${INPUT_STRICT_MCP:-false}" = "true" ] && ARGS+=( "--strict-mcp" )
[ "${INPUT_SCAN_ALL:-false}"   = "true" ] && ARGS+=( "--scan-all" )

OUT="$RUNNER_TEMP/scan.json"
echo "scan.sh: running skill-detector ${ARGS[*]}"
set +e
skill-detector "${ARGS[@]}" > "$OUT"
EXIT=$?
set -e

echo "SCAN_EXIT_CODE=$EXIT" >> "$GITHUB_ENV"
echo "scan-json-path=$OUT" >> "${GITHUB_OUTPUT:-/dev/null}"

# Extract grade + finding count from JSON (best-effort; absent fields render empty).
if command -v jq >/dev/null 2>&1; then
  GRADE="$(jq -r '
    if .axes then
      (.axes | to_entries | map(.value.grade) | sort | last) // ""
    else "" end' "$OUT")"
  FINDINGS="$(jq -r '.findings | length // 0' "$OUT")"
  echo "grade=$GRADE"          >> "${GITHUB_OUTPUT:-/dev/null}"
  echo "findings-count=$FINDINGS" >> "${GITHUB_OUTPUT:-/dev/null}"
fi

echo "scan.sh: detector exit=$EXIT, scan json at $OUT"
```

```bash
chmod +x "/Users/glibrulev/projects/saas/skil security/scan-action/scripts/scan.sh"
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
./scripts/run-tests.sh
```

Expected: all `scan.bats` tests pass.

- [ ] **Step 6: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
git add scripts/scan.sh tests/bats/scan.bats tests/bats/fixtures/fake-detector.sh
git commit -m "feat: scan.sh runs skill-detector with flag passthrough"
```

## Task A6: `scan.ps1` — Windows variant

**Files:**
- Create: `scan-action/scripts/scan.ps1`

- [ ] **Step 1: Write `scan.ps1`**

Create `scan-action/scripts/scan.ps1`:

```powershell
$ErrorActionPreference = "Stop"

$path        = if ($env:INPUT_PATH)       { $env:INPUT_PATH }       else { "." }
$failOn      = if ($env:INPUT_FAIL_ON)    { $env:INPUT_FAIL_ON }    else { "high" }
$strictMCP   = $env:INPUT_STRICT_MCP -eq "true"
$scanAll     = $env:INPUT_SCAN_ALL   -eq "true"

$args = @("scan", $path, "--format", "json", "--fail-on", $failOn)

if ($env:INPUT_FAIL_ON_AXIS) {
  foreach ($spec in ($env:INPUT_FAIL_ON_AXIS -split ',')) {
    $s = $spec.Trim()
    if ($s) { $args += @("--fail-on-axis", $s) }
  }
}
if ($strictMCP) { $args += "--strict-mcp" }
if ($scanAll)   { $args += "--scan-all" }

$out = Join-Path $env:RUNNER_TEMP "scan.json"
Write-Host "scan.ps1: running skill-detector $($args -join ' ')"
$proc = Start-Process -FilePath "skill-detector" -ArgumentList $args -NoNewWindow -PassThru -RedirectStandardOutput $out -Wait
$exit = $proc.ExitCode

if ($env:GITHUB_ENV) {
  Add-Content -Path $env:GITHUB_ENV -Value "SCAN_EXIT_CODE=$exit"
}
if ($env:GITHUB_OUTPUT) {
  Add-Content -Path $env:GITHUB_OUTPUT -Value "scan-json-path=$out"
  # jq is preinstalled on windows-latest as part of git for Windows? safer: skip outputs if missing.
  if (Get-Command jq -ErrorAction SilentlyContinue) {
    $grade    = (jq -r 'if .axes then (.axes | to_entries | map(.value.grade) | sort | last) // "" else "" end' $out)
    $findings = (jq -r '.findings | length // 0' $out)
    Add-Content -Path $env:GITHUB_OUTPUT -Value "grade=$grade"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "findings-count=$findings"
  }
}

Write-Host "scan.ps1: detector exit=$exit, scan json at $out"
```

- [ ] **Step 2: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
git add scripts/scan.ps1
git commit -m "feat: scan.ps1 Windows variant of detector invocation"
```

## Task A7: Minimal `action.yml` (S1 scope only)

**Files:**
- Create: `scan-action/action.yml`

- [ ] **Step 1: Write the minimal action.yml**

Create `scan-action/action.yml`:

```yaml
name: SkillTrust Scan
description: Scan AI-agent config (SKILL.md, CLAUDE.md, .claude/, .mcp.json) for security threats
author: SkillTrust
branding:
  icon: shield
  color: green

inputs:
  path:
    description: Path to scan (default = repo root)
    required: false
    default: '.'
  fail-on:
    description: 'Severity threshold for non-zero exit: critical|high|medium|low|info'
    required: false
    default: high
  fail-on-axis:
    description: 'Per-axis grade thresholds, comma-separated, e.g. "permission_hygiene=C,security=C"'
    required: false
    default: ''
  strict-mcp:
    description: Raise MCP external-domain rule severity from medium to high
    required: false
    default: 'false'
  scan-all:
    description: Disable scope tightening and .gitignore filtering
    required: false
    default: 'false'
  detector-version:
    description: Pin a specific skill-detector release. Default = version pinned to this action tag.
    required: false
    default: 'v0.2.1'

outputs:
  grade:
    description: 'Overall trust grade (worst axis): A|B|C|D|F'
    value: ${{ steps.scan.outputs.grade }}
  scan-json-path:
    description: Absolute path to the scan result JSON in the runner
    value: ${{ steps.scan.outputs.scan-json-path }}
  findings-count:
    description: Total finding count
    value: ${{ steps.scan.outputs.findings-count }}

runs:
  using: composite
  steps:
    - name: Install skill-detector
      shell: bash
      if: runner.os != 'Windows'
      env:
        INPUT_DETECTOR_VERSION: ${{ inputs.detector-version }}
      run: ${{ github.action_path }}/scripts/install.sh

    - name: Install skill-detector (Windows)
      shell: pwsh
      if: runner.os == 'Windows'
      env:
        INPUT_DETECTOR_VERSION: ${{ inputs.detector-version }}
      run: ${{ github.action_path }}/scripts/install.ps1

    - id: scan
      name: Run scan
      shell: bash
      if: runner.os != 'Windows'
      env:
        INPUT_PATH:         ${{ inputs.path }}
        INPUT_FAIL_ON:      ${{ inputs.fail-on }}
        INPUT_FAIL_ON_AXIS: ${{ inputs.fail-on-axis }}
        INPUT_STRICT_MCP:   ${{ inputs.strict-mcp }}
        INPUT_SCAN_ALL:     ${{ inputs.scan-all }}
      run: ${{ github.action_path }}/scripts/scan.sh

    - id: scan-win
      name: Run scan (Windows)
      shell: pwsh
      if: runner.os == 'Windows'
      env:
        INPUT_PATH:         ${{ inputs.path }}
        INPUT_FAIL_ON:      ${{ inputs.fail-on }}
        INPUT_FAIL_ON_AXIS: ${{ inputs.fail-on-axis }}
        INPUT_STRICT_MCP:   ${{ inputs.strict-mcp }}
        INPUT_SCAN_ALL:     ${{ inputs.scan-all }}
      run: ${{ github.action_path }}/scripts/scan.ps1

    - name: Propagate exit code
      shell: bash
      run: exit ${SCAN_EXIT_CODE:-0}
```

- [ ] **Step 2: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
git add action.yml
git commit -m "feat: action.yml v0 — install + scan + propagate exit code"
```

## Task A8: Set up matrix CI for the action repo itself

**Files:**
- Create: `scan-action/.github/workflows/ci.yml`
- Create: `scan-action/tests/fixtures/clean-repo/.gitkeep`
- Create: `scan-action/tests/fixtures/malicious-repo/.claude/settings.json`

- [ ] **Step 1: Create fixture repos in-tree**

Create empty file `scan-action/tests/fixtures/clean-repo/.gitkeep` so the dir is tracked.

Create `scan-action/tests/fixtures/malicious-repo/.claude/settings.json`:

```json
{
  "permissions": {
    "allow": ["Bash(curl *)"]
  }
}
```

This fixture triggers known rules (SD-014 wildcard bash permission family) so the action should exit non-zero.

- [ ] **Step 2: Write the CI workflow**

Create `scan-action/.github/workflows/ci.yml`:

```yaml
name: ci

on:
  pull_request:
  push:
    branches: [main]

jobs:
  bats:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/run-tests.sh

  smoke-clean:
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: ./
        with:
          path: tests/fixtures/clean-repo
          fail-on: high

  smoke-malicious:
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - id: action
        continue-on-error: true
        uses: ./
        with:
          path: tests/fixtures/malicious-repo
          fail-on: high
      - name: Assert action failed
        if: steps.action.outcome != 'failure'
        run: |
          echo "Expected action to fail on malicious fixture, got outcome=${{ steps.action.outcome }}" >&2
          exit 1
```

- [ ] **Step 3: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
git add .github/workflows/ci.yml tests/fixtures/
git commit -m "ci: matrix smoke tests for clean + malicious fixtures"
```

## Task A9: Phase A dogfood + push

**Files:**
- Create: `scan-action/docs/dogfood-2026-05-2X-sp5.md`

- [ ] **Step 1: Create the dogfood log header**

Create `scan-action/docs/dogfood-2026-05-2X-sp5.md`:

```markdown
# SP-5 scan-action dogfood log

Real-world verification of each tracer-bullet slice.

## S1 — Binary install + scan

**Date:** 2026-05-2X
**Target:** TBD after first remote push

_To be filled after first matrix run on GitHub-hosted runners._
```

- [ ] **Step 2: Push to remote**

The remote does not exist yet on github.com. Either the user creates the `skilltrust/scan-action` GitHub repo first and shares the URL, or this push is deferred. Document the state:

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
echo "Local commits ready. Awaiting remote URL for skilltrust/scan-action repo."
git log --oneline
```

- [ ] **Step 3: Commit the dogfood log placeholder**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
git add docs/dogfood-2026-05-2X-sp5.md
git commit -m "docs: dogfood log placeholder"
```

- [ ] **Step 4: Pause for human checkpoint**

Phase A complete. Confirm with user: matrix CI green on ubuntu-latest + macos-latest (deferred to first remote push; the user must create the GitHub repo). Move to Phase B only after Phase A commits are reviewed.

---

# Phase B — Sticky PR comment (Slice S2)

Goal: action posts a marker-tagged sticky comment on PR triggers. Re-runs update the existing comment in place. Fork PRs degrade gracefully.

## Task B1: Comment markdown template (head-only, no delta)

**Files:**
- Create: `scan-action/templates/comment.md.tmpl`
- Create: `scan-action/scripts/render-comment.sh`
- Create: `scan-action/tests/bats/render-comment.bats`

- [ ] **Step 1: Write the template**

Create `scan-action/templates/comment.md.tmpl`:

```
<!-- skilltrust:action:v1 -->
## 🛡 SkillTrust — Trust Score **__GRADE__**

| Axis | Grade |
|------|-------|
__AXIS_ROWS__

__FINDINGS_BLOCK__

---
_Posted by [skilltrust/scan-action@v1](https://github.com/skilltrust/scan-action) · Detector __DETECTOR_VERSION___
```

We use `__TOKEN__` placeholders (not `${VAR}`) so we can sed-replace without `envsubst` quoting issues with markdown's `$` characters.

- [ ] **Step 2: Write the failing test**

Create `scan-action/tests/bats/render-comment.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() {
  setup_tmpdir
  export RUNNER_TEMP="$TMPDIR_TEST"
}
teardown() { teardown_tmpdir; }

@test "render-comment.sh: renders head-only comment with axis rows" {
  cat > "$RUNNER_TEMP/scan.json" <<EOF
{
  "axes": {
    "security":           {"grade": "B"},
    "permission_hygiene": {"grade": "D"},
    "transparency":       {"grade": "C"},
    "quality":            {"grade": "A"}
  },
  "findings": [
    {"rule_id":"SD-014","severity":"high","axis":"permission_hygiene","file_path":".claude/settings.json","line":3,"description":"wildcard bash"}
  ],
  "version": "0.2.1"
}
EOF
  export INPUT_SCAN_JSON="$RUNNER_TEMP/scan.json"
  run bash "$BATS_TEST_DIRNAME/../../scripts/render-comment.sh"
  [ "$status" -eq 0 ]
  [ -f "$RUNNER_TEMP/comment.md" ]
  grep -q "<!-- skilltrust:action:v1 -->" "$RUNNER_TEMP/comment.md"
  grep -q "Trust Score \*\*D\*\*"        "$RUNNER_TEMP/comment.md"  # worst grade
  grep -q "SD-014"                       "$RUNNER_TEMP/comment.md"
  grep -q "permission_hygiene"           "$RUNNER_TEMP/comment.md"
}

@test "render-comment.sh: renders no-findings shape when findings empty" {
  cat > "$RUNNER_TEMP/scan.json" <<EOF
{"axes":{"security":{"grade":"A"}},"findings":[],"version":"0.2.1"}
EOF
  export INPUT_SCAN_JSON="$RUNNER_TEMP/scan.json"
  run bash "$BATS_TEST_DIRNAME/../../scripts/render-comment.sh"
  [ "$status" -eq 0 ]
  grep -q "_No findings._" "$RUNNER_TEMP/comment.md"
}
```

- [ ] **Step 3: Run to verify they fail**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
./scripts/run-tests.sh
```

Expected: 2 new tests fail (`render-comment.sh` not yet implemented).

- [ ] **Step 4: Write `render-comment.sh`**

Create `scan-action/scripts/render-comment.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Required env:
#   RUNNER_TEMP
#   INPUT_SCAN_JSON     path to skill-detector scan JSON
# Optional:
#   INPUT_DELTA_JSON    path to delta JSON (Phase D); empty = head-only render

TEMPLATE_DIR="$(cd "$(dirname "$0")/.." && pwd)/templates"
SCAN="$INPUT_SCAN_JSON"
OUT="$RUNNER_TEMP/comment.md"

# Worst grade across all axes (sort lexicographically; A < B < ... < F).
WORST_GRADE="$(jq -r '
  if .axes then
    [.axes | to_entries[] | .value.grade] | sort | last
  else "" end' "$SCAN")"
[ -z "$WORST_GRADE" ] || [ "$WORST_GRADE" = "null" ] && WORST_GRADE="—"

DETECTOR_VERSION="$(jq -r '.version // ""' "$SCAN")"
[ -z "$DETECTOR_VERSION" ] || [ "$DETECTOR_VERSION" = "null" ] && DETECTOR_VERSION="unknown"

# Axis rows: sorted by axis name for stability.
AXIS_ROWS="$(jq -r '
  if .axes then
    .axes | to_entries | sort_by(.key)
      | map("| \(.key) | \(.value.grade) |") | join("\n")
  else "" end' "$SCAN")"

FINDING_COUNT="$(jq -r '.findings | length // 0' "$SCAN")"

if [ "$FINDING_COUNT" -eq 0 ]; then
  FINDINGS_BLOCK="_No findings._"
else
  FINDINGS_BLOCK="$(jq -r '
    "**Findings (" + (.findings | length | tostring) + "):**\n" +
    (.findings | sort_by(.severity, .rule_id)[:10]
      | map("- `" + .rule_id + "` " + (.axis // "") + " · `" + .file_path + ":" + (.line | tostring) + "` — " + (.description // "")) | join("\n"))
  ' "$SCAN")"
fi

# sed substitution: write to a temp body, then sed -i is tricky cross-platform.
# Use awk replace approach.
python3 - "$TEMPLATE_DIR/comment.md.tmpl" "$OUT" <<EOF
import sys, os
src = open(sys.argv[1]).read()
out = (src
  .replace("__GRADE__", os.environ.get("WORST_GRADE", "—"))
  .replace("__AXIS_ROWS__", os.environ.get("AXIS_ROWS", ""))
  .replace("__FINDINGS_BLOCK__", os.environ.get("FINDINGS_BLOCK", ""))
  .replace("__DETECTOR_VERSION__", os.environ.get("DETECTOR_VERSION", "unknown")))
open(sys.argv[2], "w").write(out)
EOF
```

Wait — `python3` is preinstalled on GitHub-hosted runners (ubuntu, macos, windows). But mixing bash heredoc + python is awkward and the env vars need exporting. Rewrite cleaner:

Replace the script above with:

```bash
#!/usr/bin/env bash
set -euo pipefail

TEMPLATE_DIR="$(cd "$(dirname "$0")/.." && pwd)/templates"
SCAN="$INPUT_SCAN_JSON"
OUT="$RUNNER_TEMP/comment.md"

WORST_GRADE="$(jq -r '
  if (.axes // {}) | length > 0 then
    [.axes | to_entries[] | .value.grade] | sort | last
  else "—" end' "$SCAN")"
[ "$WORST_GRADE" = "null" ] && WORST_GRADE="—"

DETECTOR_VERSION="$(jq -r '.version // "unknown"' "$SCAN")"
[ "$DETECTOR_VERSION" = "null" ] && DETECTOR_VERSION="unknown"

AXIS_ROWS="$(jq -r '
  if (.axes // {}) | length > 0 then
    .axes | to_entries | sort_by(.key)
      | map("| \(.key) | \(.value.grade) |") | join("\n")
  else "| _no axes_ | — |" end' "$SCAN")"

FINDING_COUNT="$(jq -r '.findings | length' "$SCAN")"

if [ "$FINDING_COUNT" -eq 0 ]; then
  FINDINGS_BLOCK="_No findings._"
else
  FINDINGS_BLOCK="$(jq -r '
    "**Findings (" + (.findings | length | tostring) + "):**\n" +
    (.findings | sort_by(.severity, .rule_id)[:10]
      | map("- `" + .rule_id + "` " + (.axis // "") + " · `" + (.file_path // "") + ":" + (.line | tostring) + "` — " + (.description // "")) | join("\n"))
  ' "$SCAN")"
fi

export WORST_GRADE AXIS_ROWS FINDINGS_BLOCK DETECTOR_VERSION

python3 -c "
import os, sys
src = open(sys.argv[1]).read()
out = (src
    .replace('__GRADE__',            os.environ['WORST_GRADE'])
    .replace('__AXIS_ROWS__',        os.environ['AXIS_ROWS'])
    .replace('__FINDINGS_BLOCK__',   os.environ['FINDINGS_BLOCK'])
    .replace('__DETECTOR_VERSION__', os.environ['DETECTOR_VERSION']))
open(sys.argv[2], 'w').write(out)
" "$TEMPLATE_DIR/comment.md.tmpl" "$OUT"

echo "render-comment.sh: comment.md written to $OUT"
```

```bash
chmod +x "/Users/glibrulev/projects/saas/skil security/scan-action/scripts/render-comment.sh"
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
./scripts/run-tests.sh
```

Expected: `render-comment.bats` tests pass.

- [ ] **Step 6: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
git add templates/comment.md.tmpl scripts/render-comment.sh tests/bats/render-comment.bats
git commit -m "feat: render-comment.sh emits head-only marker-tagged markdown"
```

## Task B2: `report.sh` — sticky PR comment via gh api

**Files:**
- Create: `scan-action/scripts/report.sh`
- Create: `scan-action/tests/bats/report.bats`
- Create: `scan-action/tests/bats/fixtures/fake-gh.sh`

- [ ] **Step 1: Write a fake `gh` for tests**

Create `scan-action/tests/bats/fixtures/fake-gh.sh`:

```bash
#!/usr/bin/env bash
# Records invocations to $FAKE_GH_LOG; honors $FAKE_GH_LIST_OUTPUT to
# simulate `gh api .../comments` listing results.

echo "GH_ARGS: $*" >> "${FAKE_GH_LOG:-/dev/null}"

case "$1" in
  api)
    shift
    # Find subcommand. Simulated subset:
    #   gh api repos/$repo/issues/$pr/comments  → returns JSON list
    #   gh api -X PATCH repos/$repo/issues/comments/$id -F body=@file → 200
    #   gh api repos/$repo/issues/$pr/comments -F body=@file → 201
    while [ $# -gt 0 ]; do
      case "$1" in
        */issues/*/comments)
          # GET listing
          echo "${FAKE_GH_LIST_OUTPUT:-[]}"
          exit 0
          ;;
        */issues/comments/*)
          # PATCH
          echo '{"id":12345,"body":"(patched)"}'
          exit 0
          ;;
      esac
      shift
    done
    # Default POST new comment
    echo '{"id":12345,"body":"(created)"}'
    ;;
  *)
    echo "fake-gh: unknown subcommand $1" >&2
    exit 2
    ;;
esac
```

```bash
chmod +x "/Users/glibrulev/projects/saas/skil security/scan-action/tests/bats/fixtures/fake-gh.sh"
```

- [ ] **Step 2: Write the failing tests**

Create `scan-action/tests/bats/report.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() {
  setup_tmpdir
  cp "$BATS_TEST_DIRNAME/fixtures/fake-gh.sh" "$TMPDIR_TEST/gh"
  chmod +x "$TMPDIR_TEST/gh"
  export PATH="$TMPDIR_TEST:$PATH"
  export RUNNER_TEMP="$TMPDIR_TEST"
  export FAKE_GH_LOG="$TMPDIR_TEST/gh.log"
  : > "$FAKE_GH_LOG"
  echo "rendered body" > "$RUNNER_TEMP/comment.md"
  export INPUT_GITHUB_REPOSITORY="acme/widgets"
  export INPUT_PULL_NUMBER="42"
}
teardown() { teardown_tmpdir; }

@test "report.sh: creates a new comment when no marker comment exists" {
  export FAKE_GH_LIST_OUTPUT='[]'
  run bash "$BATS_TEST_DIRNAME/../../scripts/report.sh"
  [ "$status" -eq 0 ]
  grep -q "api repos/acme/widgets/issues/42/comments" "$FAKE_GH_LOG"
  ! grep -q "PATCH" "$FAKE_GH_LOG"
}

@test "report.sh: PATCHes existing marker comment when present" {
  export FAKE_GH_LIST_OUTPUT='[{"id":777,"body":"<!-- skilltrust:action:v1 -->\nold body"}]'
  run bash "$BATS_TEST_DIRNAME/../../scripts/report.sh"
  [ "$status" -eq 0 ]
  grep -q "PATCH repos/acme/widgets/issues/comments/777" "$FAKE_GH_LOG"
}

@test "report.sh: skips API call and logs warning when GITHUB_TOKEN is read-only (fork PR)" {
  export INPUT_IS_FORK_PR="true"
  run bash "$BATS_TEST_DIRNAME/../../scripts/report.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fork PR detected; printing comment to log"* ]]
  [ ! -s "$FAKE_GH_LOG" ]
}
```

- [ ] **Step 3: Run to verify they fail**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
./scripts/run-tests.sh
```

Expected: 3 new tests fail.

- [ ] **Step 4: Write `report.sh`**

Create `scan-action/scripts/report.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Required env:
#   RUNNER_TEMP                  scratch dir; $RUNNER_TEMP/comment.md must exist
#   INPUT_GITHUB_REPOSITORY      "owner/repo"
#   INPUT_PULL_NUMBER            PR number
# Optional:
#   INPUT_IS_FORK_PR             "true" → skip API, print to log
#   GH_TOKEN / GITHUB_TOKEN      consumed by gh CLI

COMMENT_FILE="$RUNNER_TEMP/comment.md"
REPO="$INPUT_GITHUB_REPOSITORY"
PR="$INPUT_PULL_NUMBER"
MARKER="<!-- skilltrust:action:v1 -->"

if [ "${INPUT_IS_FORK_PR:-false}" = "true" ]; then
  echo "report.sh: fork PR detected; printing comment to log instead of posting"
  echo "::group::SkillTrust comment (would-be)"
  cat "$COMMENT_FILE"
  echo "::endgroup::"
  echo "::warning title=SkillTrust::Trust Score commentary printed to job log (fork PR cannot post comments)"
  exit 0
fi

# Find existing marker comment.
EXISTING_ID="$(gh api "repos/$REPO/issues/$PR/comments" \
  --jq '.[] | select(.body | startswith("'"$MARKER"'")) | .id' | head -n 1 || true)"

if [ -n "$EXISTING_ID" ]; then
  echo "report.sh: PATCH existing comment $EXISTING_ID"
  gh api -X PATCH "repos/$REPO/issues/comments/$EXISTING_ID" \
    -F body=@"$COMMENT_FILE" > /dev/null
else
  echo "report.sh: POST new comment"
  gh api "repos/$REPO/issues/$PR/comments" \
    -F body=@"$COMMENT_FILE" > /dev/null
fi

echo "report.sh: done"
```

```bash
chmod +x "/Users/glibrulev/projects/saas/skil security/scan-action/scripts/report.sh"
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
./scripts/run-tests.sh
```

Expected: all `report.bats` tests pass.

- [ ] **Step 6: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
git add scripts/report.sh tests/bats/report.bats tests/bats/fixtures/fake-gh.sh
git commit -m "feat: report.sh sticky-comments via gh api with fork-PR fallback"
```

## Task B3: `report.ps1` — Windows variant

**Files:**
- Create: `scan-action/scripts/report.ps1`

- [ ] **Step 1: Write the script**

Create `scan-action/scripts/report.ps1`:

```powershell
$ErrorActionPreference = "Stop"

$commentFile = Join-Path $env:RUNNER_TEMP "comment.md"
$repo   = $env:INPUT_GITHUB_REPOSITORY
$pr     = $env:INPUT_PULL_NUMBER
$marker = "<!-- skilltrust:action:v1 -->"

if ($env:INPUT_IS_FORK_PR -eq "true") {
  Write-Host "report.ps1: fork PR detected; printing comment to log instead of posting"
  Write-Host "::group::SkillTrust comment (would-be)"
  Get-Content $commentFile | Write-Host
  Write-Host "::endgroup::"
  Write-Host "::warning title=SkillTrust::Trust Score commentary printed to job log (fork PR cannot post comments)"
  exit 0
}

$existing = gh api "repos/$repo/issues/$pr/comments" `
  --jq "[.[] | select(.body | startswith(\""+$marker+"\""))][0].id"

if ($existing -and $existing -ne "null") {
  Write-Host "report.ps1: PATCH existing comment $existing"
  gh api -X PATCH "repos/$repo/issues/comments/$existing" -F "body=@$commentFile" | Out-Null
} else {
  Write-Host "report.ps1: POST new comment"
  gh api "repos/$repo/issues/$pr/comments" -F "body=@$commentFile" | Out-Null
}
```

- [ ] **Step 2: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
git add scripts/report.ps1
git commit -m "feat: report.ps1 Windows variant of comment posting"
```

## Task B4: Wire render + report into `action.yml`

**Files:**
- Modify: `scan-action/action.yml`

- [ ] **Step 1: Add `comment` input + steps**

Edit `scan-action/action.yml` (the existing file from Task A7).

After the existing `scan-all` input, add:

```yaml
  comment:
    description: Post sticky PR comment (PR triggers only)
    required: false
    default: 'true'
  github-token:
    description: Token for posting PR comments. Default = workflow GITHUB_TOKEN.
    required: false
    default: ${{ github.token }}
```

Replace the existing `Propagate exit code` step with the following block (inserted before the propagate step):

```yaml
    - name: Render comment
      shell: bash
      if: github.event_name == 'pull_request' && inputs.comment == 'true' && runner.os != 'Windows'
      env:
        INPUT_SCAN_JSON: ${{ steps.scan.outputs.scan-json-path }}
      run: ${{ github.action_path }}/scripts/render-comment.sh

    - name: Render comment (Windows)
      shell: pwsh
      if: github.event_name == 'pull_request' && inputs.comment == 'true' && runner.os == 'Windows'
      env:
        INPUT_SCAN_JSON: ${{ steps.scan-win.outputs.scan-json-path }}
      run: ${{ github.action_path }}/scripts/render-comment.ps1

    - name: Post sticky comment
      shell: bash
      if: github.event_name == 'pull_request' && inputs.comment == 'true' && runner.os != 'Windows'
      env:
        GH_TOKEN: ${{ inputs.github-token }}
        INPUT_GITHUB_REPOSITORY: ${{ github.repository }}
        INPUT_PULL_NUMBER: ${{ github.event.pull_request.number }}
        INPUT_IS_FORK_PR: ${{ github.event.pull_request.head.repo.fork }}
      run: ${{ github.action_path }}/scripts/report.sh

    - name: Post sticky comment (Windows)
      shell: pwsh
      if: github.event_name == 'pull_request' && inputs.comment == 'true' && runner.os == 'Windows'
      env:
        GH_TOKEN: ${{ inputs.github-token }}
        INPUT_GITHUB_REPOSITORY: ${{ github.repository }}
        INPUT_PULL_NUMBER: ${{ github.event.pull_request.number }}
        INPUT_IS_FORK_PR: ${{ github.event.pull_request.head.repo.fork }}
      run: ${{ github.action_path }}/scripts/report.ps1

    - name: Propagate exit code
      shell: bash
      run: exit ${SCAN_EXIT_CODE:-0}
```

- [ ] **Step 2: Add a `render-comment.ps1` stub for Windows**

Create `scan-action/scripts/render-comment.ps1`:

```powershell
$ErrorActionPreference = "Stop"

$templateDir = Join-Path (Split-Path -Parent $PSScriptRoot) "templates"
$scan = $env:INPUT_SCAN_JSON
$out  = Join-Path $env:RUNNER_TEMP "comment.md"

# Re-use python (preinstalled on windows-latest) for parity with bash variant.
$py = @"
import json, os, sys
data = json.load(open(sys.argv[1]))
axes = data.get('axes') or {}
grades = sorted([v.get('grade','') for v in axes.values()]) if axes else []
worst = grades[-1] if grades else '—'
findings = data.get('findings') or []
detector_version = data.get('version') or 'unknown'

axis_rows = '\n'.join(
    f'| {k} | {v.get("grade","")} |' for k, v in sorted(axes.items())
) if axes else '| _no axes_ | — |'

if not findings:
    findings_block = '_No findings._'
else:
    rows = []
    for f in sorted(findings, key=lambda x: (x.get('severity',''), x.get('rule_id','')))[:10]:
        rows.append(f"- `{f.get('rule_id','')}` {f.get('axis','')} · `{f.get('file_path','')}:{f.get('line',0)}` — {f.get('description','')}")
    findings_block = f"**Findings ({len(findings)}):**\n" + '\n'.join(rows)

src = open(sys.argv[2]).read()
out = (src
    .replace('__GRADE__', worst)
    .replace('__AXIS_ROWS__', axis_rows)
    .replace('__FINDINGS_BLOCK__', findings_block)
    .replace('__DETECTOR_VERSION__', detector_version))
open(sys.argv[3], 'w', encoding='utf-8').write(out)
"@
python -c $py $scan (Join-Path $templateDir 'comment.md.tmpl') $out
Write-Host "render-comment.ps1: comment.md written to $out"
```

- [ ] **Step 3: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
git add action.yml scripts/render-comment.ps1
git commit -m "feat: action.yml wires render + report steps with fork-PR detection"
```

## Task B5: PR-event smoke fixture in CI

**Files:**
- Modify: `scan-action/.github/workflows/ci.yml`

- [ ] **Step 1: Add a self-hosted PR smoke job**

Append to `scan-action/.github/workflows/ci.yml`:

```yaml
  smoke-pr-comment:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@v4
      - uses: ./
        with:
          path: tests/fixtures/malicious-repo
          fail-on: high
          comment: 'true'
        continue-on-error: true
      - name: Assert sticky comment exists
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          count=$(gh api "repos/${{ github.repository }}/issues/${{ github.event.pull_request.number }}/comments" \
            --jq '[.[] | select(.body | startswith("<!-- skilltrust:action:v1 -->"))] | length')
          if [ "$count" -ne 1 ]; then
            echo "Expected exactly 1 marker comment, got $count" >&2
            exit 1
          fi
```

- [ ] **Step 2: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
git add .github/workflows/ci.yml
git commit -m "ci: self-PR smoke validates sticky comment posts on malicious fixture"
```

## Task B6: Update Phase A dogfood log + checkpoint

**Files:**
- Modify: `scan-action/docs/dogfood-2026-05-2X-sp5.md`

- [ ] **Step 1: Append the S2 entry placeholder**

Edit the dogfood log: append after the S1 section.

```markdown
## S2 — Sticky PR comment

**Date:** 2026-05-2X

_To be filled after opening a PR on the scan-action repo itself; expect a sticky comment with the worst axis grade D (from `malicious-repo` fixture)._
```

- [ ] **Step 2: Commit + checkpoint**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
git add docs/dogfood-2026-05-2X-sp5.md
git commit -m "docs: dogfood log entry placeholder for S2"
```

Phase B done. Confirm with user: open a self-PR on scan-action repo and verify a marker comment appears. Then continue to Phase C.

---

# Phase C — `pkg/delta` extraction (Slice S3)

Goal: extract delta logic into `skill-detector/pkg/delta`, add `skill-detector delta` CLI sub-command, switch `skillmoss-go/internal/prbot.ComputeDelta` to consume the library. **Golden snapshots in skillmoss-go must remain byte-identical** — that's how we prove zero-behavior-change.

## Task C1: Create the `pkg/delta` package skeleton

**Files:**
- Create: `skill-detector/pkg/delta/delta.go`
- Create: `skill-detector/pkg/delta/doc.go`

- [ ] **Step 1: Add the doc.go**

Create `skill-detector/pkg/delta/doc.go`:

```go
// Package delta computes per-axis grade movement + finding diff between two
// scan results. Pure functions over pkg/model.ScanResult; no IO. Consumed by
// the `skill-detector delta` CLI sub-command and (via wrapper) by the
// skillmoss-go PR-comment bot.
package delta
```

- [ ] **Step 2: Add the types**

Create `skill-detector/pkg/delta/delta.go`:

```go
package delta

import (
	"crypto/sha1"
	"encoding/hex"
	"fmt"

	"github.com/velzepooz/skill-detector/pkg/axes"
	"github.com/velzepooz/skill-detector/pkg/model"
)

// GradeDelta represents per-axis grade movement.
type GradeDelta struct {
	Old, New  axes.Grade
	Direction string // "up" | "down" | "same"
}

// Delta is the diff between two ScanResults.
type Delta struct {
	PerAxis          map[axes.Axis]GradeDelta
	NewFindings      []model.Finding
	ResolvedFindings []model.Finding
	AxisExplanations map[axes.Axis]string // one-line WHY per downgraded axis
}

// findingKey identifies a finding stably across runs.
// Whitespace-only edits should not change the key.
func findingKey(f model.Finding) string {
	h := sha1.Sum([]byte(f.Description))
	return fmt.Sprintf("%s|%s|%d|%s", f.RuleID, f.FilePath, f.Line, hex.EncodeToString(h[:6]))
}

// gradeRank returns higher-is-better integer rank. Returns -1 for unknown.
// Accepts "A", "A+", "A-", through "F".
func gradeRank(g axes.Grade) int {
	if g == "" {
		return -1
	}
	s := string(g)
	tier := map[byte]int{'A': 4, 'B': 3, 'C': 2, 'D': 1, 'F': 0}
	t, ok := tier[s[0]]
	if !ok {
		return -1
	}
	base := t * 3
	if len(s) > 1 {
		switch s[1] {
		case '+':
			base++
		case '-':
			base--
		}
	}
	return base
}

// GradeArrow renders a delta as "↑ B → A" or "↓ B → D".
func GradeArrow(d GradeDelta) string {
	arrow := "↓"
	if d.Direction == "up" {
		arrow = "↑"
	}
	return fmt.Sprintf("%s %s → %s", arrow, d.Old, d.New)
}

// Compute produces a Delta between base and head. base may be nil (caller
// should detect and skip delta rendering). Direction is "same" when grades
// equal OR when base lacks the axis (best-effort — don't pretend an axis
// appeared).
func Compute(base, head *model.ScanResult) Delta {
	d := Delta{
		PerAxis:          map[axes.Axis]GradeDelta{},
		AxisExplanations: map[axes.Axis]string{},
	}

	baseAxes := map[axes.Axis]axes.Grade{}
	if base != nil {
		for k, v := range base.Axes {
			baseAxes[k] = v.Grade
		}
	}
	if head != nil {
		for k, v := range head.Axes {
			old := baseAxes[k]
			dir := "same"
			if old != "" {
				rank := gradeRank(v.Grade) - gradeRank(old)
				if rank > 0 {
					dir = "up"
				} else if rank < 0 {
					dir = "down"
				}
			}
			d.PerAxis[k] = GradeDelta{Old: old, New: v.Grade, Direction: dir}
		}
	}

	baseKeys := map[string]model.Finding{}
	if base != nil {
		for _, f := range base.Findings {
			baseKeys[findingKey(f)] = f
		}
	}
	headKeys := map[string]model.Finding{}
	if head != nil {
		for _, f := range head.Findings {
			headKeys[findingKey(f)] = f
		}
	}
	for k, f := range headKeys {
		if _, ok := baseKeys[k]; !ok {
			d.NewFindings = append(d.NewFindings, f)
		}
	}
	for k, f := range baseKeys {
		if _, ok := headKeys[k]; !ok {
			d.ResolvedFindings = append(d.ResolvedFindings, f)
		}
	}

	for axis, gd := range d.PerAxis {
		if gd.Direction != "down" {
			continue
		}
		for _, f := range d.NewFindings {
			if f.Axis == axis {
				d.AxisExplanations[axis] = fmt.Sprintf("%s — %s _(%s, %s:%d)_",
					GradeArrow(gd), f.Description, f.RuleID, f.FilePath, f.Line)
				break
			}
		}
	}
	return d
}
```

- [ ] **Step 3: Compile-check**

```bash
cd "/Users/glibrulev/projects/saas/skil security/skill-detector"
go build ./pkg/delta/...
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/skill-detector"
git add pkg/delta/
git commit -m "feat(delta): add pkg/delta with Compute over model.ScanResult"
```

## Task C2: Port skillmoss-go's delta tests to `pkg/delta`

**Files:**
- Create: `skill-detector/pkg/delta/delta_test.go`

- [ ] **Step 1: Write tests mirroring the skillmoss-go cases**

Create `skill-detector/pkg/delta/delta_test.go`:

```go
package delta_test

import (
	"strings"
	"testing"

	"github.com/velzepooz/skill-detector/pkg/axes"
	"github.com/velzepooz/skill-detector/pkg/delta"
	"github.com/velzepooz/skill-detector/pkg/model"
)

func sr(grades map[axes.Axis]axes.Grade, findings ...model.Finding) *model.ScanResult {
	r := &model.ScanResult{
		Axes:     map[axes.Axis]model.AxisResult{},
		Findings: findings,
	}
	for k, v := range grades {
		r.Axes[k] = model.AxisResult{Grade: v}
	}
	return r
}

func TestCompute_GradeMovement(t *testing.T) {
	base := sr(map[axes.Axis]axes.Grade{
		axes.PermissionHygiene: axes.GradeB,
		axes.Security:          axes.GradeA,
	})
	head := sr(map[axes.Axis]axes.Grade{
		axes.PermissionHygiene: axes.GradeD,
		axes.Security:          axes.GradeA,
	})
	d := delta.Compute(base, head)
	if d.PerAxis[axes.PermissionHygiene].Direction != "down" {
		t.Errorf("permission_hygiene direction=%q", d.PerAxis[axes.PermissionHygiene].Direction)
	}
	if d.PerAxis[axes.Security].Direction != "same" {
		t.Errorf("security direction=%q", d.PerAxis[axes.Security].Direction)
	}
}

func TestCompute_FindingDiff(t *testing.T) {
	base := sr(nil,
		model.Finding{RuleID: "SD-001", FilePath: "a.go", Line: 1, Description: "old", Axis: axes.PermissionHygiene},
	)
	head := sr(nil,
		model.Finding{RuleID: "SD-002", FilePath: "b.go", Line: 5, Description: "new", Axis: axes.PermissionHygiene},
	)
	d := delta.Compute(base, head)
	if len(d.NewFindings) != 1 || d.NewFindings[0].RuleID != "SD-002" {
		t.Errorf("new=%v", d.NewFindings)
	}
	if len(d.ResolvedFindings) != 1 || d.ResolvedFindings[0].RuleID != "SD-001" {
		t.Errorf("resolved=%v", d.ResolvedFindings)
	}
}

func TestCompute_StableMatchKey(t *testing.T) {
	f := model.Finding{RuleID: "X", FilePath: "x.go", Line: 10, Description: "msg", Axis: axes.PermissionHygiene}
	r := sr(nil, f)
	d := delta.Compute(r, r)
	if len(d.NewFindings) != 0 || len(d.ResolvedFindings) != 0 {
		t.Errorf("identical scans should have empty diff; new=%v resolved=%v", d.NewFindings, d.ResolvedFindings)
	}
}

func TestCompute_AxisExplanationOnDowngrade(t *testing.T) {
	base := sr(map[axes.Axis]axes.Grade{axes.PermissionHygiene: axes.GradeB})
	head := sr(map[axes.Axis]axes.Grade{axes.PermissionHygiene: axes.GradeD},
		model.Finding{RuleID: "SD-014", Axis: axes.PermissionHygiene, FilePath: ".claude/settings.json", Line: 42, Description: "wildcard"},
	)
	d := delta.Compute(base, head)
	exp := d.AxisExplanations[axes.PermissionHygiene]
	if exp == "" {
		t.Fatalf("expected explanation for permission_hygiene downgrade; got: %v", d.AxisExplanations)
	}
	if !strings.Contains(exp, "SD-014") || !strings.Contains(exp, ".claude/settings.json:42") {
		t.Errorf("explanation lacks expected rule/path/line; got %q", exp)
	}
}

func TestCompute_AxisOnlyInHead(t *testing.T) {
	base := sr(nil)
	head := sr(map[axes.Axis]axes.Grade{axes.Security: axes.GradeB})
	d := delta.Compute(base, head)
	gd := d.PerAxis[axes.Security]
	if gd.New != axes.GradeB || gd.Old != "" || gd.Direction != "same" {
		t.Errorf("axis-only-in-head should report new grade with empty old + same direction; got %+v", gd)
	}
}

func TestCompute_NilBase(t *testing.T) {
	head := sr(map[axes.Axis]axes.Grade{axes.Security: axes.GradeC})
	d := delta.Compute(nil, head)
	if d.PerAxis[axes.Security].New != axes.GradeC {
		t.Errorf("nil base: head grade not surfaced")
	}
	if d.PerAxis[axes.Security].Direction != "same" {
		t.Errorf("nil base: direction should be same, got %q", d.PerAxis[axes.Security].Direction)
	}
}
```

- [ ] **Step 2: Run tests**

```bash
cd "/Users/glibrulev/projects/saas/skil security/skill-detector"
go test ./pkg/delta/...
```

Expected: all pass.

- [ ] **Step 3: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/skill-detector"
git add pkg/delta/delta_test.go
git commit -m "test(delta): port skillmoss-go delta cases to pkg/delta"
```

## Task C3: Add `skill-detector delta` CLI sub-command

**Files:**
- Create: `skill-detector/cmd/skill-detector/delta.go`
- Create: `skill-detector/cmd/skill-detector/delta_test.go`
- Modify: `skill-detector/cmd/skill-detector/main.go`

- [ ] **Step 1: Write the failing test**

Create `skill-detector/cmd/skill-detector/delta_test.go`:

```go
package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func writeJSON(t *testing.T, path string, body any) {
	t.Helper()
	raw, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, raw, 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestDeltaCmd_JSONOutput_HasPerAxis(t *testing.T) {
	dir := t.TempDir()
	base := filepath.Join(dir, "base.json")
	head := filepath.Join(dir, "head.json")
	writeJSON(t, base, map[string]any{
		"axes":     map[string]any{"security": map[string]string{"grade": "B"}},
		"findings": []any{},
	})
	writeJSON(t, head, map[string]any{
		"axes":     map[string]any{"security": map[string]string{"grade": "A"}},
		"findings": []any{},
	})

	cmd := newRootCmd()
	cmd.SetArgs([]string{"delta", base, head, "--format", "json"})
	var stdout bytes.Buffer
	cmd.SetOut(&stdout)
	if err := cmd.Execute(); err != nil {
		t.Fatalf("execute: %v", err)
	}
	var got map[string]any
	if err := json.Unmarshal(stdout.Bytes(), &got); err != nil {
		t.Fatalf("unmarshal: %v\nout=%s", err, stdout.String())
	}
	if _, ok := got["per_axis"]; !ok {
		t.Errorf("expected per_axis key; got %v", got)
	}
}

func TestDeltaCmd_MarkdownOutput_HasArrow(t *testing.T) {
	dir := t.TempDir()
	base := filepath.Join(dir, "base.json")
	head := filepath.Join(dir, "head.json")
	writeJSON(t, base, map[string]any{
		"axes":     map[string]any{"permission_hygiene": map[string]string{"grade": "B"}},
		"findings": []any{},
	})
	writeJSON(t, head, map[string]any{
		"axes":     map[string]any{"permission_hygiene": map[string]string{"grade": "D"}},
		"findings": []any{map[string]any{
			"rule_id":   "SD-014",
			"axis":      "permission_hygiene",
			"file_path": ".claude/settings.json",
			"line":      42.0,
			"description": "wildcard",
		}},
	})

	cmd := newRootCmd()
	cmd.SetArgs([]string{"delta", base, head, "--format", "markdown"})
	var stdout bytes.Buffer
	cmd.SetOut(&stdout)
	if err := cmd.Execute(); err != nil {
		t.Fatalf("execute: %v", err)
	}
	if !bytes.Contains(stdout.Bytes(), []byte("↓ B → D")) {
		t.Errorf("expected downgrade arrow B→D in output; got: %s", stdout.String())
	}
}
```

- [ ] **Step 2: Run to verify fail**

```bash
cd "/Users/glibrulev/projects/saas/skil security/skill-detector"
go test ./cmd/skill-detector/ -run TestDeltaCmd
```

Expected: tests fail (sub-command not registered).

- [ ] **Step 3: Implement `delta.go`**

Create `skill-detector/cmd/skill-detector/delta.go`:

```go
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"sort"

	"github.com/spf13/cobra"
	"github.com/velzepooz/skill-detector/pkg/axes"
	"github.com/velzepooz/skill-detector/pkg/delta"
	"github.com/velzepooz/skill-detector/pkg/model"
)

func newDeltaCmd() *cobra.Command {
	var format string

	cmd := &cobra.Command{
		Use:   "delta <base.json> <head.json>",
		Short: "Compute the trust-score delta between two scan result JSON files",
		Long: "Reads two `skill-detector scan --format json` output files (base + head) " +
			"and emits the per-axis grade movement + finding diff. Pure function — no IO " +
			"besides reading the two input files.",
		Args: cobra.ExactArgs(2),
		RunE: func(cmd *cobra.Command, args []string) error {
			cmd.SilenceUsage = true
			base, err := loadScan(args[0])
			if err != nil {
				return fmt.Errorf("delta: base: %w", err)
			}
			head, err := loadScan(args[1])
			if err != nil {
				return fmt.Errorf("delta: head: %w", err)
			}
			d := delta.Compute(base, head)
			switch format {
			case "json":
				return writeDeltaJSON(cmd.OutOrStdout(), d)
			case "markdown":
				return writeDeltaMarkdown(cmd.OutOrStdout(), d)
			default:
				return fmt.Errorf("delta: unsupported --format %q (want json or markdown)", format)
			}
		},
	}
	cmd.Flags().StringVar(&format, "format", "json", "Output format: json | markdown")
	return cmd
}

func loadScan(path string) (*model.ScanResult, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var r model.ScanResult
	if err := json.Unmarshal(raw, &r); err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	return &r, nil
}

// writeDeltaJSON emits a stable, sorted JSON shape.
func writeDeltaJSON(w interface{ Write(p []byte) (int, error) }, d delta.Delta) error {
	type gd struct {
		Old, New, Direction string
	}
	out := map[string]any{
		"per_axis":          map[string]gd{},
		"new_findings":      d.NewFindings,
		"resolved_findings": d.ResolvedFindings,
		"axis_explanations": map[string]string{},
	}
	for axis, x := range d.PerAxis {
		out["per_axis"].(map[string]gd)[string(axis)] = gd{
			Old: string(x.Old), New: string(x.New), Direction: x.Direction,
		}
	}
	for axis, exp := range d.AxisExplanations {
		out["axis_explanations"].(map[string]string)[string(axis)] = exp
	}
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	return enc.Encode(out)
}

// writeDeltaMarkdown emits a human-readable delta block. Stable axis order.
func writeDeltaMarkdown(w interface{ Write(p []byte) (int, error) }, d delta.Delta) error {
	axesSorted := make([]axes.Axis, 0, len(d.PerAxis))
	for a := range d.PerAxis {
		axesSorted = append(axesSorted, a)
	}
	sort.Slice(axesSorted, func(i, j int) bool { return string(axesSorted[i]) < string(axesSorted[j]) })

	var lines []string
	lines = append(lines, "| Axis | Grade | Δ |", "|------|-------|---|")
	for _, a := range axesSorted {
		x := d.PerAxis[a]
		mark := "—"
		if x.Direction != "same" && x.Old != "" {
			mark = delta.GradeArrow(x)
		}
		lines = append(lines, fmt.Sprintf("| %s | %s | %s |", a, x.New, mark))
	}
	if len(d.AxisExplanations) > 0 {
		lines = append(lines, "", "**Why downgraded:**")
		expKeys := make([]axes.Axis, 0, len(d.AxisExplanations))
		for a := range d.AxisExplanations {
			expKeys = append(expKeys, a)
		}
		sort.Slice(expKeys, func(i, j int) bool { return string(expKeys[i]) < string(expKeys[j]) })
		for _, a := range expKeys {
			lines = append(lines, fmt.Sprintf("- **%s:** %s", a, d.AxisExplanations[a]))
		}
	}
	out := ""
	for _, l := range lines {
		out += l + "\n"
	}
	_, err := w.Write([]byte(out))
	return err
}
```

- [ ] **Step 4: Wire the sub-command in `main.go`**

Edit `skill-detector/cmd/skill-detector/main.go::newRootCmd`. After `rootCmd.AddCommand(newScanCmd())`, add:

```go
	rootCmd.AddCommand(newDeltaCmd())
```

- [ ] **Step 5: Run tests + full suite**

```bash
cd "/Users/glibrulev/projects/saas/skil security/skill-detector"
go test ./...
```

Expected: all tests (including new delta-cmd tests) pass.

- [ ] **Step 6: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/skill-detector"
git add cmd/skill-detector/delta.go cmd/skill-detector/delta_test.go cmd/skill-detector/main.go
git commit -m "feat(cli): add 'skill-detector delta' sub-command (json + markdown)"
```

## Task C4: Tag skill-detector v0.3.0

**Files:**
- Modify: `skill-detector/CHANGELOG.md`

- [ ] **Step 1: Add a CHANGELOG entry**

Edit `skill-detector/CHANGELOG.md` — add an entry at the top following the existing convention:

```markdown
## v0.3.0 — 2026-05-2X

### Added
- `pkg/delta` package — pure-function trust-score delta computation over two `model.ScanResult`s. Returns per-axis grade movement, finding diff, and axis-downgrade explanations.
- `skill-detector delta <base.json> <head.json>` CLI sub-command emitting JSON or markdown.

### Why
- Powers the new `skilltrust/scan-action@v1` GitHub Action's optional `delta: true` mode.
- Single source of truth for delta semantics shared by the Action and the skillmoss-go PR-comment bot (SP-4).
```

- [ ] **Step 2: Commit + tag**

```bash
cd "/Users/glibrulev/projects/saas/skil security/skill-detector"
git add CHANGELOG.md
git commit -m "release: v0.3.0 — pkg/delta + 'skill-detector delta' sub-command"
git tag v0.3.0
```

- [ ] **Step 3: User pushes + GoReleaser**

Confirm with the user before pushing — staged push per the project's release convention. Expect GoReleaser CI to cut release binaries + checksums + Homebrew tap update.

```bash
cd "/Users/glibrulev/projects/saas/skil security/skill-detector"
# User runs:
#   git push origin main
#   (wait for CI green)
#   git push origin v0.3.0
```

Do NOT execute these pushes from the plan-runner; wait for explicit user instruction.

## Task C5: Switch skillmoss-go to consume the library

**Files:**
- Modify: `skillmoss-go/internal/prbot/delta.go`
- Modify: `skillmoss-go/go.mod` (if needed — `skill-detector` already a dep, just bump version)

- [ ] **Step 1: Bump skill-detector dependency in skillmoss-go**

```bash
cd "/Users/glibrulev/projects/saas/skil security/skillmoss-go"
go get github.com/velzepooz/skill-detector@v0.3.0
go mod tidy
```

(If GoReleaser/tag push from C4 hasn't finished, the user must wait. Document this as a checkpoint.)

- [ ] **Step 2: Replace `internal/prbot/delta.go` with a library adapter**

The file currently contains `ComputeDelta`, `GradeDelta`, `Delta`, `findingKey`, `gradeRank`, `gradeArrow`. Replace it entirely with a thin adapter that converts store types → model types, calls `delta.Compute`, and converts back.

Overwrite `skillmoss-go/internal/prbot/delta.go`:

```go
package prbot

import (
	"github.com/velzepooz/skill-detector/pkg/axes"
	"github.com/velzepooz/skill-detector/pkg/delta"
	"github.com/velzepooz/skill-detector/pkg/model"
	"github.com/velzepooz/skillmoss-go/internal/store"
)

// GradeDelta + Delta retain their existing shapes so callers (render.go) stay
// untouched. The underlying computation now flows through skill-detector/pkg/delta.
type GradeDelta struct {
	Old, New  string
	Direction string
}

type Delta struct {
	PerAxis          map[string]GradeDelta
	NewFindings      []store.Finding
	ResolvedFindings []store.Finding
	AxisExplanations map[string]string
}

// ComputeDelta is the unchanged public API. Internally it converts to
// pkg/model.ScanResult, calls delta.Compute, then maps back to store-typed
// findings so render.go's existing format strings still apply.
func ComputeDelta(base, head *store.Scan, baseFindings, headFindings []store.Finding) Delta {
	libBase := toModel(base, baseFindings)
	libHead := toModel(head, headFindings)
	d := delta.Compute(libBase, libHead)

	out := Delta{
		PerAxis:          map[string]GradeDelta{},
		AxisExplanations: map[string]string{},
	}
	for a, gd := range d.PerAxis {
		out.PerAxis[string(a)] = GradeDelta{
			Old:       string(gd.Old),
			New:       string(gd.New),
			Direction: gd.Direction,
		}
	}
	for a, exp := range d.AxisExplanations {
		out.AxisExplanations[string(a)] = exp
	}

	baseByKey := indexByStoreKey(baseFindings)
	headByKey := indexByStoreKey(headFindings)
	for _, f := range d.NewFindings {
		if orig, ok := headByKey[modelKey(f)]; ok {
			out.NewFindings = append(out.NewFindings, orig)
		}
	}
	for _, f := range d.ResolvedFindings {
		if orig, ok := baseByKey[modelKey(f)]; ok {
			out.ResolvedFindings = append(out.ResolvedFindings, orig)
		}
	}
	return out
}

// gradeArrow keeps the old package-private helper so render.go compiles unchanged.
func gradeArrow(g GradeDelta) string {
	return delta.GradeArrow(delta.GradeDelta{
		Old:       axes.Grade(g.Old),
		New:       axes.Grade(g.New),
		Direction: g.Direction,
	})
}

func toModel(s *store.Scan, findings []store.Finding) *model.ScanResult {
	if s == nil && len(findings) == 0 {
		return nil
	}
	r := &model.ScanResult{
		Axes:     map[axes.Axis]model.AxisResult{},
		Findings: make([]model.Finding, 0, len(findings)),
	}
	if s != nil {
		for k, v := range s.AxisGrades {
			r.Axes[axes.Axis(k)] = model.AxisResult{
				Grade:     axes.Grade(v.Grade),
				Rationale: v.Rationale,
			}
		}
	}
	for _, f := range findings {
		r.Findings = append(r.Findings, model.Finding{
			RuleID:      f.Rule,
			FilePath:    f.Path,
			Line:        f.Line,
			Description: f.Message,
			Axis:        axes.Axis(f.Axis),
		})
	}
	return r
}

// modelKey + indexByStoreKey let us map the library's diff results back to
// the original store.Finding rows that callers expect.
func modelKey(f model.Finding) string {
	// Mirror the library's keying: rule_id|file_path|line|sha1(description)[:6]
	// We don't import the library's private helper; reproduce inline.
	return f.RuleID + "|" + f.FilePath + "|" + sprintfInt(f.Line) + "|" + sha1Short(f.Description)
}

func indexByStoreKey(fs []store.Finding) map[string]store.Finding {
	out := make(map[string]store.Finding, len(fs))
	for _, f := range fs {
		out[storeFindingKey(f)] = f
	}
	return out
}

func storeFindingKey(f store.Finding) string {
	return f.Rule + "|" + f.Path + "|" + sprintfInt(f.Line) + "|" + sha1Short(f.Message)
}
```

Add helper functions at the bottom of the same file:

```go
import (
	"crypto/sha1"
	"encoding/hex"
	"strconv"
)

func sprintfInt(n int) string {
	return strconv.Itoa(n)
}

func sha1Short(s string) string {
	h := sha1.Sum([]byte(s))
	return hex.EncodeToString(h[:6])
}
```

(Reconcile imports — final file has one `import` block with `crypto/sha1`, `encoding/hex`, `strconv`, the three skill-detector packages, and the store package.)

- [ ] **Step 3: Run the prbot test suite**

```bash
cd "/Users/glibrulev/projects/saas/skil security/skillmoss-go"
TEST_DATABASE_URL=postgres://skillmoss:skillmoss@localhost:5432/skillmoss_test?sslmode=disable \
  go test ./internal/prbot/... -p 1
```

Expected: all 5 existing `TestComputeDelta_*` cases + render tests pass.

- [ ] **Step 4: Full skillmoss-go test pass to verify golden snapshots**

```bash
cd "/Users/glibrulev/projects/saas/skil security/skillmoss-go"
TEST_DATABASE_URL=postgres://skillmoss:skillmoss@localhost:5432/skillmoss_test?sslmode=disable \
  go test ./... -p 1
```

Expected: full suite green. Golden-file render snapshots must be byte-identical (no `-update` allowed).

If render snapshots differ, the adapter is wrong. Common pitfalls:
- Sorting order changed (library uses Go map iteration; render.go re-sorts)
- `gradeArrow` produces different string (verify library matches `↑ B → A` exactly)

Fix until snapshots match.

- [ ] **Step 5: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/skillmoss-go"
git add internal/prbot/delta.go go.mod go.sum
git commit -m "refactor(prbot): delegate ComputeDelta to skill-detector/pkg/delta

Zero-behavior-change: golden snapshots byte-identical pre/post.
Library is now the single source of truth for delta semantics
(shared with skilltrust/scan-action@v1)."
```

## Task C6: Phase C dogfood + checkpoint

**Files:**
- Modify: `skillmoss-go/docs/dogfood-2026-05-2X-sp5.md` (create if missing)

- [ ] **Step 1: Capture the refactor verification**

Create or append `skillmoss-go/docs/dogfood-2026-05-2X-sp5.md`:

```markdown
# SP-5 skillmoss-go dogfood log

## S3 — pkg/delta extraction

**Date:** 2026-05-2X
**skill-detector tag:** v0.3.0

- `go test ./internal/prbot/... -p 1` → all green
- Render golden snapshots in `internal/prbot/testdata/` byte-identical pre/post (confirmed via `git diff --stat HEAD~1 testdata/`)
- Open PR on velzepooz/blog#X to confirm SP-4 still renders comments identically
- _[Fill in after dogfood PR result]_
```

- [ ] **Step 2: Commit + checkpoint**

```bash
cd "/Users/glibrulev/projects/saas/skil security/skillmoss-go"
git add docs/dogfood-2026-05-2X-sp5.md
git commit -m "docs: dogfood log entry for S3 (pkg/delta extraction)"
```

Phase C done. Confirm with user: skill-detector v0.3.0 tagged + skillmoss-go consumes library + golden snapshots intact. **Stop and verify the SP-4 PR-bot still renders identically on a real PR before continuing to Phase D.**

---

# Phase D — Action delta input (Slice S4)

Goal: `with: delta: true` triggers a second scan against the base branch, calls `skill-detector delta`, and the comment renders ↑/↓ + WHY block.

## Task D1: Update comment template + render-comment for delta

**Files:**
- Modify: `scan-action/templates/comment.md.tmpl`
- Modify: `scan-action/scripts/render-comment.sh`
- Modify: `scan-action/scripts/render-comment.ps1`
- Modify: `scan-action/tests/bats/render-comment.bats`

- [ ] **Step 1: Update the template to a 4-token delta layout**

Replace `scan-action/templates/comment.md.tmpl` with:

```
<!-- skilltrust:action:v1 -->
## 🛡 SkillTrust — Trust Score **__GRADE__**__GRADE_DELTA__

__AXIS_TABLE__

__WHY_BLOCK__

__FINDINGS_BLOCK__

__RESOLVED_BLOCK__

---
_Posted by [skilltrust/scan-action@v1](https://github.com/skilltrust/scan-action) · Detector __DETECTOR_VERSION___
```

The render scripts now compose `__AXIS_TABLE__` (with or without Δ column), `__GRADE_DELTA__` (e.g. ` (was A)`), `__WHY_BLOCK__`, and `__RESOLVED_BLOCK__` (empty when no delta).

- [ ] **Step 2: Update the failing test**

Edit `scan-action/tests/bats/render-comment.bats` — add a delta test case:

```bash
@test "render-comment.sh: renders delta column when INPUT_DELTA_JSON present" {
  cat > "$RUNNER_TEMP/scan.json" <<EOF
{
  "axes": {
    "security": {"grade": "B"},
    "permission_hygiene": {"grade": "D"}
  },
  "findings": [
    {"rule_id":"SD-014","severity":"high","axis":"permission_hygiene","file_path":".claude/settings.json","line":3,"description":"wildcard bash"}
  ],
  "version": "0.3.0"
}
EOF
  cat > "$RUNNER_TEMP/delta.json" <<EOF
{
  "per_axis": {
    "security":           {"Old":"B","New":"B","Direction":"same"},
    "permission_hygiene": {"Old":"B","New":"D","Direction":"down"}
  },
  "new_findings": [
    {"rule_id":"SD-014","axis":"permission_hygiene","file_path":".claude/settings.json","line":3,"description":"wildcard bash"}
  ],
  "resolved_findings": [],
  "axis_explanations": {
    "permission_hygiene": "↓ B → D — wildcard _(SD-014, .claude/settings.json:3)_"
  }
}
EOF
  export INPUT_SCAN_JSON="$RUNNER_TEMP/scan.json"
  export INPUT_DELTA_JSON="$RUNNER_TEMP/delta.json"
  run bash "$BATS_TEST_DIRNAME/../../scripts/render-comment.sh"
  [ "$status" -eq 0 ]
  grep -q "↓ B → D"       "$RUNNER_TEMP/comment.md"
  grep -q "Why downgraded" "$RUNNER_TEMP/comment.md"
  grep -q "permission_hygiene" "$RUNNER_TEMP/comment.md"
}
```

- [ ] **Step 3: Run test, expect fail**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
./scripts/run-tests.sh
```

Expected: the new delta test fails (current render-comment doesn't read INPUT_DELTA_JSON).

- [ ] **Step 4: Update `render-comment.sh` to consume delta**

Replace `scan-action/scripts/render-comment.sh` (overwrite):

```bash
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

# AXIS_TABLE
if [ -n "$DELTA" ] && [ -f "$DELTA" ]; then
  WORST_OLD="$(jq -r '
    if (.per_axis // {}) | length > 0 then
      [.per_axis | to_entries[] | .value.Old | select(. != "")] | sort | last
    else "" end' "$DELTA")"
  [ -n "$WORST_OLD" ] && [ "$WORST_OLD" != "null" ] && GRADE_DELTA=" (was $WORST_OLD)"

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
```

- [ ] **Step 5: Update `render-comment.ps1` to mirror**

Edit `scan-action/scripts/render-comment.ps1` — replace the python inline with one that reads `$env:INPUT_DELTA_JSON` (when set), producing the same 6 substitution tokens. Mirror the bash logic line-for-line.

```powershell
$ErrorActionPreference = "Stop"

$templateDir = Join-Path (Split-Path -Parent $PSScriptRoot) "templates"
$scan  = $env:INPUT_SCAN_JSON
$delta = $env:INPUT_DELTA_JSON
$out   = Join-Path $env:RUNNER_TEMP "comment.md"

$py = @"
import json, os, sys
scan = json.load(open(sys.argv[1]))
delta = json.load(open(sys.argv[2])) if sys.argv[2] and os.path.exists(sys.argv[2]) else None

axes = scan.get('axes') or {}
grades = sorted([v.get('grade','') for v in axes.values()]) if axes else []
worst = grades[-1] if grades else '—'
findings = scan.get('findings') or []
detector_version = scan.get('version') or 'unknown'

grade_delta = ''
why_block = ''
resolved_block = ''

if delta:
    per_axis = delta.get('per_axis') or {}
    olds = sorted([v.get('Old','') for v in per_axis.values() if v.get('Old')])
    if olds:
        grade_delta = f' (was {olds[-1]})'
    rows = []
    for k in sorted(per_axis):
        v = per_axis[k]
        head_grade = (axes.get(k) or {}).get('grade', v.get('New',''))
        if v.get('Direction') == 'same' or not v.get('Old'):
            d = '—'
        else:
            arrow = '↑' if v.get('Direction') == 'up' else '↓'
            d = f"{arrow} {v.get('Old')} → {v.get('New')}"
        rows.append(f'| {k} | {head_grade} | {d} |')
    axis_table = '| Axis | Grade | Δ |\n|------|-------|---|\n' + '\n'.join(rows)
    expl = delta.get('axis_explanations') or {}
    if expl:
        why_block = '**Why downgraded:**\n' + '\n'.join(f'- **{k}:** {expl[k]}' for k in sorted(expl))
    resolved = delta.get('resolved_findings') or []
    if resolved:
        resolved_block = f'**Resolved ({len(resolved)}):**\n' + '\n'.join(
            f"- ✅ `{r.get('rule_id','')}` {r.get('axis','')} — {r.get('description','')}" for r in resolved)
else:
    rows = [f'| {k} | {v.get(\"grade\",\"\")} |' for k, v in sorted(axes.items())]
    axis_table = '| Axis | Grade |\n|------|-------|\n' + ('\n'.join(rows) if rows else '| _no axes_ | — |')

if not findings:
    findings_block = '_No findings._'
else:
    rows = []
    for f in sorted(findings, key=lambda x: (x.get('severity',''), x.get('rule_id','')))[:10]:
        rows.append(f"- `{f.get('rule_id','')}` {f.get('axis','')} · `{f.get('file_path','')}:{f.get('line',0)}` — {f.get('description','')}")
    findings_block = f'**Findings ({len(findings)}):**\n' + '\n'.join(rows)

src = open(sys.argv[3]).read()
out = (src
    .replace('__GRADE__', worst)
    .replace('__GRADE_DELTA__', grade_delta)
    .replace('__AXIS_TABLE__', axis_table)
    .replace('__WHY_BLOCK__', why_block)
    .replace('__FINDINGS_BLOCK__', findings_block)
    .replace('__RESOLVED_BLOCK__', resolved_block)
    .replace('__DETECTOR_VERSION__', detector_version))
open(sys.argv[4], 'w', encoding='utf-8').write(out)
"@
python -c $py $scan ($delta -as [string]) (Join-Path $templateDir 'comment.md.tmpl') $out
Write-Host "render-comment.ps1: comment.md written to $out"
```

- [ ] **Step 6: Run tests**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
./scripts/run-tests.sh
```

Expected: all render-comment tests (head-only, no-findings, delta) pass.

- [ ] **Step 7: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
git add templates/comment.md.tmpl scripts/render-comment.sh scripts/render-comment.ps1 tests/bats/render-comment.bats
git commit -m "feat: render-comment consumes INPUT_DELTA_JSON for ↑/↓ + WHY block"
```

## Task D2: `delta.sh` — fetch base, scan it, invoke `skill-detector delta`

**Files:**
- Create: `scan-action/scripts/delta.sh`
- Create: `scan-action/scripts/delta.ps1`
- Create: `scan-action/tests/bats/delta.bats`

- [ ] **Step 1: Write the failing test**

Create `scan-action/tests/bats/delta.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() {
  setup_tmpdir
  export RUNNER_TEMP="$TMPDIR_TEST"

  # Fake skill-detector that produces deterministic output keyed on the input dir.
  cat > "$TMPDIR_TEST/skill-detector" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  scan)
    if [[ "$2" == *base* ]]; then
      echo '{"axes":{"security":{"grade":"A"}},"findings":[],"version":"0.3.0"}'
    else
      echo '{"axes":{"security":{"grade":"B"}},"findings":[],"version":"0.3.0"}'
    fi
    ;;
  delta)
    # Reads two JSON files; emits a delta JSON. Use jq if available; here just emit fixed output.
    cat <<JSON
{
  "per_axis": {"security": {"Old":"A","New":"B","Direction":"down"}},
  "new_findings": [],
  "resolved_findings": [],
  "axis_explanations": {}
}
JSON
    ;;
esac
EOF
  chmod +x "$TMPDIR_TEST/skill-detector"
  export PATH="$TMPDIR_TEST:$PATH"

  # Fake git that simulates fetch + worktree add.
  mkdir -p "$TMPDIR_TEST/fake-bin"
  cat > "$TMPDIR_TEST/fake-bin/git" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  fetch)        exit 0 ;;
  worktree)     mkdir -p "$4" ; echo "fixture base content" > "$4/marker"; exit 0 ;;
  rev-parse)    echo "abc123" ;;
  *)            command /usr/bin/git "$@" 2>/dev/null || exit 0 ;;
esac
EOF
  chmod +x "$TMPDIR_TEST/fake-bin/git"
  export PATH="$TMPDIR_TEST/fake-bin:$PATH"

  : > "$TMPDIR_TEST/github_env"
  export GITHUB_ENV="$TMPDIR_TEST/github_env"
}
teardown() { teardown_tmpdir; }

@test "delta.sh: produces delta.json with per_axis content" {
  export INPUT_BASE_REF="main"
  export INPUT_HEAD_SCAN_JSON="$RUNNER_TEMP/scan.json"
  # Pre-create head scan
  echo '{"axes":{"security":{"grade":"B"}},"findings":[],"version":"0.3.0"}' > "$INPUT_HEAD_SCAN_JSON"
  run bash "$BATS_TEST_DIRNAME/../../scripts/delta.sh"
  [ "$status" -eq 0 ]
  [ -f "$RUNNER_TEMP/delta.json" ]
  grep -q '"per_axis"' "$RUNNER_TEMP/delta.json"
}
```

- [ ] **Step 2: Run, expect fail**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
./scripts/run-tests.sh
```

Expected: delta test fails.

- [ ] **Step 3: Write `delta.sh`**

Create `scan-action/scripts/delta.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Required env:
#   RUNNER_TEMP
#   INPUT_BASE_REF           base branch name (e.g. "main")
#   INPUT_HEAD_SCAN_JSON     path to existing head scan JSON (from scan.sh)
#   INPUT_PATH               relative scan path within repo (default ".")

BASE_REF="$INPUT_BASE_REF"
HEAD_JSON="$INPUT_HEAD_SCAN_JSON"
SCAN_PATH="${INPUT_PATH:-.}"
BASE_DIR="$RUNNER_TEMP/skilltrust-base-worktree"

echo "delta.sh: fetching base $BASE_REF (depth=1)"
git fetch origin "$BASE_REF" --depth 1

echo "delta.sh: creating worktree at $BASE_DIR"
git worktree add --detach "$BASE_DIR" "origin/$BASE_REF" >/dev/null

BASE_TARGET="$BASE_DIR"
if [ "$SCAN_PATH" != "." ]; then
  BASE_TARGET="$BASE_DIR/$SCAN_PATH"
fi

BASE_JSON="$RUNNER_TEMP/base-scan.json"
echo "delta.sh: scanning base tree"
skill-detector scan "$BASE_TARGET" --format json > "$BASE_JSON" || true

DELTA_OUT="$RUNNER_TEMP/delta.json"
echo "delta.sh: computing delta"
skill-detector delta "$BASE_JSON" "$HEAD_JSON" --format json > "$DELTA_OUT"

echo "delta-json-path=$DELTA_OUT" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "SCAN_ACTION_DELTA_JSON=$DELTA_OUT" >> "${GITHUB_ENV:-/dev/null}"
echo "delta.sh: wrote $DELTA_OUT"
```

```bash
chmod +x "/Users/glibrulev/projects/saas/skil security/scan-action/scripts/delta.sh"
```

- [ ] **Step 4: Mirror in `delta.ps1`**

Create `scan-action/scripts/delta.ps1`:

```powershell
$ErrorActionPreference = "Stop"

$baseRef  = $env:INPUT_BASE_REF
$headJson = $env:INPUT_HEAD_SCAN_JSON
$scanPath = if ($env:INPUT_PATH) { $env:INPUT_PATH } else { "." }
$baseDir  = Join-Path $env:RUNNER_TEMP "skilltrust-base-worktree"

Write-Host "delta.ps1: fetching base $baseRef (depth=1)"
git fetch origin $baseRef --depth 1
Write-Host "delta.ps1: creating worktree at $baseDir"
git worktree add --detach $baseDir "origin/$baseRef" | Out-Null

$baseTarget = if ($scanPath -eq ".") { $baseDir } else { Join-Path $baseDir $scanPath }
$baseJson   = Join-Path $env:RUNNER_TEMP "base-scan.json"
Write-Host "delta.ps1: scanning base tree"
skill-detector scan $baseTarget --format json | Out-File -FilePath $baseJson -Encoding utf8

$deltaOut = Join-Path $env:RUNNER_TEMP "delta.json"
Write-Host "delta.ps1: computing delta"
skill-detector delta $baseJson $headJson --format json | Out-File -FilePath $deltaOut -Encoding utf8

if ($env:GITHUB_OUTPUT) { Add-Content -Path $env:GITHUB_OUTPUT -Value "delta-json-path=$deltaOut" }
if ($env:GITHUB_ENV)    { Add-Content -Path $env:GITHUB_ENV    -Value "SCAN_ACTION_DELTA_JSON=$deltaOut" }
Write-Host "delta.ps1: wrote $deltaOut"
```

- [ ] **Step 5: Run tests**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
./scripts/run-tests.sh
```

Expected: delta.sh test passes.

- [ ] **Step 6: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
git add scripts/delta.sh scripts/delta.ps1 tests/bats/delta.bats
git commit -m "feat: delta.sh scans base tree and invokes 'skill-detector delta'"
```

## Task D3: Wire delta into `action.yml`

**Files:**
- Modify: `scan-action/action.yml`

- [ ] **Step 1: Add `delta` input + steps**

Edit `scan-action/action.yml`. After the `comment:` input add:

```yaml
  delta:
    description: Compute delta vs base branch (PR triggers only). Doubles runtime.
    required: false
    default: 'false'
```

Insert these steps between `Run scan (Windows)` and `Render comment`:

```yaml
    - id: delta
      name: Compute delta
      shell: bash
      if: inputs.delta == 'true' && github.event_name == 'pull_request' && runner.os != 'Windows'
      env:
        INPUT_BASE_REF:        ${{ github.event.pull_request.base.ref }}
        INPUT_HEAD_SCAN_JSON:  ${{ steps.scan.outputs.scan-json-path }}
        INPUT_PATH:            ${{ inputs.path }}
      run: ${{ github.action_path }}/scripts/delta.sh

    - id: delta-win
      name: Compute delta (Windows)
      shell: pwsh
      if: inputs.delta == 'true' && github.event_name == 'pull_request' && runner.os == 'Windows'
      env:
        INPUT_BASE_REF:        ${{ github.event.pull_request.base.ref }}
        INPUT_HEAD_SCAN_JSON:  ${{ steps.scan-win.outputs.scan-json-path }}
        INPUT_PATH:            ${{ inputs.path }}
      run: ${{ github.action_path }}/scripts/delta.ps1
```

Update the two `Render comment` steps to pass `INPUT_DELTA_JSON`:

```yaml
    - name: Render comment
      shell: bash
      if: github.event_name == 'pull_request' && inputs.comment == 'true' && runner.os != 'Windows'
      env:
        INPUT_SCAN_JSON:  ${{ steps.scan.outputs.scan-json-path }}
        INPUT_DELTA_JSON: ${{ env.SCAN_ACTION_DELTA_JSON }}
      run: ${{ github.action_path }}/scripts/render-comment.sh

    - name: Render comment (Windows)
      shell: pwsh
      if: github.event_name == 'pull_request' && inputs.comment == 'true' && runner.os == 'Windows'
      env:
        INPUT_SCAN_JSON:  ${{ steps.scan-win.outputs.scan-json-path }}
        INPUT_DELTA_JSON: ${{ env.SCAN_ACTION_DELTA_JSON }}
      run: ${{ github.action_path }}/scripts/render-comment.ps1
```

Also bump default `detector-version` to `v0.3.0` so the `delta` sub-command exists:

```yaml
  detector-version:
    description: Pin a specific skill-detector release. Default = version pinned to this action tag.
    required: false
    default: 'v0.3.0'
```

- [ ] **Step 2: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
git add action.yml
git commit -m "feat: action.yml threads delta input through compute + render steps"
```

## Task D4: PR-event smoke matrix for delta

**Files:**
- Modify: `scan-action/.github/workflows/ci.yml`

- [ ] **Step 1: Add a delta smoke job**

Append to `scan-action/.github/workflows/ci.yml`:

```yaml
  smoke-pr-delta:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - id: action
        continue-on-error: true
        uses: ./
        with:
          path: tests/fixtures/malicious-repo
          fail-on: high
          delta: 'true'
          comment: 'true'
      - name: Assert delta comment posted
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          body=$(gh api "repos/${{ github.repository }}/issues/${{ github.event.pull_request.number }}/comments" \
            --jq '.[] | select(.body | startswith("<!-- skilltrust:action:v1 -->")) | .body' | head -1)
          # If base is identical to head's scope, delta will be empty — at minimum,
          # the marker must be present.
          if [ -z "$body" ]; then
            echo "Expected marker comment, got none" >&2; exit 1
          fi
```

- [ ] **Step 2: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
git add .github/workflows/ci.yml
git commit -m "ci: PR-event delta smoke job"
```

## Task D5: Phase D dogfood entry + checkpoint

- [ ] **Step 1: Append S4 dogfood log entry**

Edit `scan-action/docs/dogfood-2026-05-2X-sp5.md`:

```markdown
## S4 — Action delta input

**Date:** 2026-05-2X

_To be filled after opening a PR that intentionally downgrades an axis (e.g. add a wildcard bash perm). Verify comment shows ↓ B → D and a "Why downgraded:" line._
```

- [ ] **Step 2: Commit + checkpoint**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
git add docs/dogfood-2026-05-2X-sp5.md
git commit -m "docs: dogfood log placeholder for S4 (delta)"
```

Phase D done. Confirm with user: open a PR with an axis downgrade and verify the delta comment renders. Continue to Phase E only after confirmation.

---

# Phase E — Telemetry + multi-OS + release (Slice S5)

Goal: skillmoss-go gets a telemetry endpoint; the Action POSTs a coarse heartbeat by default; Windows matrix green; tag v1.0.0 + v1; submit Marketplace listing.

## Task E1: skillmoss-go migration for telemetry table

**Files:**
- Create: `skillmoss-go/internal/store/migrations/0008_action_telemetry.sql`

- [ ] **Step 1: Write the migration**

Create `skillmoss-go/internal/store/migrations/0008_action_telemetry.sql`:

```sql
CREATE TABLE action_telemetry_pings (
  id           BIGSERIAL PRIMARY KEY,
  received_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  src_ip_hash  BYTEA NOT NULL,
  payload      JSONB NOT NULL
);

CREATE INDEX action_telemetry_pings_received
  ON action_telemetry_pings (received_at DESC);

CREATE INDEX action_telemetry_pings_repo_hash
  ON action_telemetry_pings ((payload->>'repo_hash'));
```

- [ ] **Step 2: Run migration test**

```bash
cd "/Users/glibrulev/projects/saas/skil security/skillmoss-go"
TEST_DATABASE_URL=postgres://skillmoss:skillmoss@localhost:5432/skillmoss_test?sslmode=disable \
  go test ./internal/store/ -run TestMigrate -p 1
```

Expected: migration applies cleanly.

- [ ] **Step 3: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/skillmoss-go"
git add internal/store/migrations/0008_action_telemetry.sql
git commit -m "feat(store): migration 0008 — action_telemetry_pings"
```

## Task E2: skillmoss-go store helper for telemetry inserts

**Files:**
- Create: `skillmoss-go/internal/store/action_telemetry.go`
- Create: `skillmoss-go/internal/store/action_telemetry_test.go`

- [ ] **Step 1: Write the failing test**

Create `skillmoss-go/internal/store/action_telemetry_test.go`:

```go
package store_test

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/velzepooz/skillmoss-go/internal/store"
)

func TestInsertActionTelemetry(t *testing.T) {
	st := openTestStore(t) // existing helper used by other store tests
	ctx := context.Background()

	payload, _ := json.Marshal(map[string]any{
		"action_version":   "1.0.0",
		"detector_version": "0.3.0",
		"runner_os":        "Linux",
		"runner_arch":      "X64",
		"repo_visibility":  "public",
		"repo_hash":        "abc123",
		"grade":            "B",
		"finding_count":    4,
		"trigger":          "pull_request",
		"delta_enabled":    false,
	})

	if err := st.InsertActionTelemetry(ctx, []byte("hashed-ip-bytes"), payload); err != nil {
		t.Fatalf("insert: %v", err)
	}

	var count int
	if err := st.Pool.QueryRow(ctx,
		`SELECT count(*) FROM action_telemetry_pings WHERE payload->>'repo_hash' = $1`,
		"abc123",
	).Scan(&count); err != nil {
		t.Fatal(err)
	}
	if count != 1 {
		t.Errorf("expected 1 row, got %d", count)
	}
}
```

(Reuse the existing `openTestStore` helper — pattern visible in `internal/store/scans_test.go` or wherever it lives.)

- [ ] **Step 2: Run, expect fail**

```bash
cd "/Users/glibrulev/projects/saas/skil security/skillmoss-go"
TEST_DATABASE_URL=postgres://skillmoss:skillmoss@localhost:5432/skillmoss_test?sslmode=disable \
  go test ./internal/store/ -run TestInsertActionTelemetry -p 1
```

Expected: undefined `InsertActionTelemetry`.

- [ ] **Step 3: Implement the helper**

Create `skillmoss-go/internal/store/action_telemetry.go`:

```go
package store

import "context"

// InsertActionTelemetry persists one telemetry ping from skilltrust/scan-action.
// payload is the raw JSON body from the Action — validated by the HTTP handler
// before reaching here.
func (s *Store) InsertActionTelemetry(ctx context.Context, srcIPHash []byte, payload []byte) error {
	_, err := s.Pool.Exec(ctx, `
		INSERT INTO action_telemetry_pings (src_ip_hash, payload)
		VALUES ($1, $2::jsonb)
	`, srcIPHash, payload)
	return err
}
```

- [ ] **Step 4: Run test, expect pass**

```bash
cd "/Users/glibrulev/projects/saas/skil security/skillmoss-go"
TEST_DATABASE_URL=postgres://skillmoss:skillmoss@localhost:5432/skillmoss_test?sslmode=disable \
  go test ./internal/store/ -run TestInsertActionTelemetry -p 1
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/skillmoss-go"
git add internal/store/action_telemetry.go internal/store/action_telemetry_test.go
git commit -m "feat(store): InsertActionTelemetry helper"
```

## Task E3: skillmoss-go HTTP handler for `POST /api/telemetry/action-run`

**Files:**
- Create: `skillmoss-go/internal/web/handlers_telemetry.go`
- Create: `skillmoss-go/internal/web/handlers_telemetry_test.go`
- Modify: `skillmoss-go/internal/web/routes.go`

- [ ] **Step 1: Write the failing test**

Create `skillmoss-go/internal/web/handlers_telemetry_test.go`:

```go
package web_test

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestPostActionTelemetry_Accepts(t *testing.T) {
	srv := newTestServer(t) // existing helper that wires the Server with deps
	body := strings.NewReader(`{
		"action_version":"1.0.0",
		"detector_version":"0.3.0",
		"runner_os":"Linux",
		"runner_arch":"X64",
		"repo_visibility":"public",
		"repo_hash":"abc",
		"grade":"B",
		"finding_count":4,
		"trigger":"pull_request",
		"delta_enabled":false
	}`)
	req := httptest.NewRequest(http.MethodPost, "/api/telemetry/action-run", body)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	srv.Handler().ServeHTTP(rec, req)
	if rec.Code != http.StatusAccepted {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
}

func TestPostActionTelemetry_RejectsOversized(t *testing.T) {
	srv := newTestServer(t)
	big := bytes.Repeat([]byte("a"), 8*1024)
	req := httptest.NewRequest(http.MethodPost, "/api/telemetry/action-run", bytes.NewReader(big))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	srv.Handler().ServeHTTP(rec, req)
	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("expected 413; got %d", rec.Code)
	}
}

func TestPostActionTelemetry_RejectsInvalidJSON(t *testing.T) {
	srv := newTestServer(t)
	req := httptest.NewRequest(http.MethodPost, "/api/telemetry/action-run",
		strings.NewReader(`not json`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	srv.Handler().ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400; got %d", rec.Code)
	}
}
```

(Use the existing `newTestServer(t)` test helper pattern — search the package for `newTestServer` to confirm the signature.)

- [ ] **Step 2: Run, expect fail**

```bash
cd "/Users/glibrulev/projects/saas/skil security/skillmoss-go"
TEST_DATABASE_URL=postgres://skillmoss:skillmoss@localhost:5432/skillmoss_test?sslmode=disable \
  go test ./internal/web/ -run TestPostActionTelemetry -p 1
```

Expected: 404 (route not registered) → tests fail.

- [ ] **Step 3: Write the handler**

Create `skillmoss-go/internal/web/handlers_telemetry.go`:

```go
package web

import (
	"crypto/sha256"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"strings"
)

const maxTelemetryBytes = 4 * 1024

type actionTelemetryPayload struct {
	ActionVersion   string `json:"action_version"`
	DetectorVersion string `json:"detector_version"`
	RunnerOS        string `json:"runner_os"`
	RunnerArch      string `json:"runner_arch"`
	RepoVisibility  string `json:"repo_visibility"`
	RepoHash        string `json:"repo_hash"`
	Grade           string `json:"grade"`
	FindingCount    int    `json:"finding_count"`
	Trigger         string `json:"trigger"`
	DeltaEnabled    bool   `json:"delta_enabled"`
}

func (s *Server) handlePostActionTelemetry(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, maxTelemetryBytes+1)
	raw, err := io.ReadAll(r.Body)
	if err != nil {
		if _, ok := err.(*http.MaxBytesError); ok || strings.Contains(err.Error(), "too large") {
			http.Error(w, "body too large", http.StatusRequestEntityTooLarge)
			return
		}
		http.Error(w, "read error", http.StatusBadRequest)
		return
	}
	if len(raw) > maxTelemetryBytes {
		http.Error(w, "body too large", http.StatusRequestEntityTooLarge)
		return
	}

	// Validate JSON shape (reject unknown fields).
	var p actionTelemetryPayload
	dec := json.NewDecoder(strings.NewReader(string(raw)))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&p); err != nil {
		http.Error(w, "invalid JSON: "+err.Error(), http.StatusBadRequest)
		return
	}
	// Cheap field validation; reject anything that looks bogus.
	if p.ActionVersion == "" || p.RepoHash == "" || p.RunnerOS == "" {
		http.Error(w, "missing required fields", http.StatusBadRequest)
		return
	}

	// Rate-limit per IP bucket (60/min).
	ip := clientIP(r)
	ipHash := sha256.Sum256([]byte(ip))
	if s.deps.RateLimiter != nil {
		ok, err := s.deps.RateLimiter.Allow(r.Context(), "telemetry:"+ip, r.Context().Value(timeNowKey{}).(time.Time))
		if err == nil && !ok {
			http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
			return
		}
	}

	if err := s.deps.Store.InsertActionTelemetry(r.Context(), ipHash[:], raw); err != nil {
		http.Error(w, "store error", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusAccepted)
}

func clientIP(r *http.Request) string {
	if fwd := r.Header.Get("X-Forwarded-For"); fwd != "" {
		if idx := strings.Index(fwd, ","); idx > 0 {
			return strings.TrimSpace(fwd[:idx])
		}
		return strings.TrimSpace(fwd)
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil {
		return host
	}
	return r.RemoteAddr
}
```

**Note:** The rate-limiter integration depends on the existing `web.Server` shape — `s.deps.RateLimiter` may not exist. Inspect `internal/web/server.go` and `internal/web/middleware.go` before this task and adjust: if the project already wraps mux handlers in a per-route rate limiter, use that pattern instead. **Do not add a new rate-limit field if one already exists.** This is the only spot where the plan defers to local conventions.

If the rate-limit block above doesn't compile (`s.deps.RateLimiter` doesn't exist), replace it with a TODO-free inline implementation:

```go
	// Allow at most 60 req/min/IP using the existing IncrCount store helper.
	now := time.Now()
	bucket := "telemetry:" + ip + ":" + now.Truncate(time.Minute).Format("2006-01-02T15:04")
	n, err := s.deps.Store.IncrCount(r.Context(), bucket, now.Truncate(time.Minute))
	if err == nil && n > 60 {
		http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
		return
	}
```

(Remove the unused `timeNowKey` ref + the s.deps.RateLimiter branch.)

- [ ] **Step 4: Register the route**

Edit `skillmoss-go/internal/web/routes.go`. Add inside the `routes()` method:

```go
	// SP-5: Action telemetry ingestion (unauthenticated, rate-limited)
	s.mux.HandleFunc("POST /api/telemetry/action-run", s.handlePostActionTelemetry)
```

- [ ] **Step 5: Run the handler tests**

```bash
cd "/Users/glibrulev/projects/saas/skil security/skillmoss-go"
TEST_DATABASE_URL=postgres://skillmoss:skillmoss@localhost:5432/skillmoss_test?sslmode=disable \
  go test ./internal/web/ -run TestPostActionTelemetry -p 1
```

Expected: all three pass.

- [ ] **Step 6: Full suite green**

```bash
cd "/Users/glibrulev/projects/saas/skil security/skillmoss-go"
TEST_DATABASE_URL=postgres://skillmoss:skillmoss@localhost:5432/skillmoss_test?sslmode=disable \
  go test ./... -p 1
```

Expected: full skillmoss-go suite green.

- [ ] **Step 7: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/skillmoss-go"
git add internal/web/handlers_telemetry.go internal/web/handlers_telemetry_test.go internal/web/routes.go
git commit -m "feat(web): POST /api/telemetry/action-run ingests scan-action heartbeats"
```

## Task E4: Surface telemetry counts on `/internal/metrics`

**Files:**
- Modify: `skillmoss-go/internal/store/metrics.go`

- [ ] **Step 1: Inspect the existing metrics shape**

Read `skillmoss-go/internal/store/metrics.go` to see the existing `CollectMetrics` return struct.

- [ ] **Step 2: Add new fields**

Add to the `Metrics` struct (or whatever the return type is named) two fields:

```go
	ActionInstallsUnique7d int `json:"action_installs_unique_7d"`
	ActionRuns24h          int `json:"action_runs_24h"`
```

Add to the `CollectMetrics` implementation two queries:

```go
	if err := s.Pool.QueryRow(ctx, `
		SELECT count(DISTINCT payload->>'repo_hash')
		  FROM action_telemetry_pings
		 WHERE received_at >= now() - interval '7 days'
	`).Scan(&m.ActionInstallsUnique7d); err != nil {
		return nil, err
	}
	if err := s.Pool.QueryRow(ctx, `
		SELECT count(*)
		  FROM action_telemetry_pings
		 WHERE received_at >= now() - interval '24 hours'
	`).Scan(&m.ActionRuns24h); err != nil {
		return nil, err
	}
```

- [ ] **Step 3: Run the metrics test**

```bash
cd "/Users/glibrulev/projects/saas/skil security/skillmoss-go"
TEST_DATABASE_URL=postgres://skillmoss:skillmoss@localhost:5432/skillmoss_test?sslmode=disable \
  go test ./internal/store/ -run TestCollectMetrics -p 1 || \
  go test ./internal/store/ -p 1
```

Expected: green. (Extend existing test if it asserts a fixed key list.)

- [ ] **Step 4: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/skillmoss-go"
git add internal/store/metrics.go
git commit -m "feat(metrics): surface action_installs_unique_7d + action_runs_24h"
```

## Task E5: Action `telemetry.sh` — fire-and-forget POST

**Files:**
- Create: `scan-action/scripts/telemetry.sh`
- Create: `scan-action/scripts/telemetry.ps1`
- Create: `scan-action/tests/bats/telemetry.bats`

- [ ] **Step 1: Write the failing test**

Create `scan-action/tests/bats/telemetry.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() {
  setup_tmpdir
  export RUNNER_TEMP="$TMPDIR_TEST"
  echo '{"version":"0.3.0","axes":{"security":{"grade":"B"}},"findings":[]}' > "$RUNNER_TEMP/scan.json"

  # Fake curl that records POST body to $FAKE_CURL_BODY.
  cat > "$TMPDIR_TEST/curl" <<'EOF'
#!/usr/bin/env bash
LAST=""
while [ $# -gt 0 ]; do
  case "$1" in
    -d|--data)        LAST="$2"; shift 2 ;;
    --data-binary)    LAST="$2"; shift 2 ;;
    *) shift ;;
  esac
done
# Strip leading @file: marker — fake-curl interprets it as a file path.
if [[ "$LAST" == @* ]]; then
  cat "${LAST:1}" > "${FAKE_CURL_BODY:-/dev/null}"
else
  echo -n "$LAST" > "${FAKE_CURL_BODY:-/dev/null}"
fi
echo "OK"
EOF
  chmod +x "$TMPDIR_TEST/curl"
  export PATH="$TMPDIR_TEST:$PATH"
  export FAKE_CURL_BODY="$TMPDIR_TEST/curl-body.txt"
  : > "$FAKE_CURL_BODY"

  export GITHUB_SERVER_URL="https://github.com"
  export GITHUB_REPOSITORY="acme/widgets"
  export GITHUB_EVENT_NAME="pull_request"
  export RUNNER_OS="Linux"
  export RUNNER_ARCH="X64"
  export INPUT_SCAN_JSON="$RUNNER_TEMP/scan.json"
  export INPUT_ACTION_VERSION="1.0.0"
  export INPUT_DETECTOR_VERSION="v0.3.0"
}
teardown() { teardown_tmpdir; }

@test "telemetry.sh: POSTs payload with hashed repo identifier" {
  run bash "$BATS_TEST_DIRNAME/../../scripts/telemetry.sh"
  [ "$status" -eq 0 ]
  body="$(cat "$FAKE_CURL_BODY")"
  [[ "$body" == *'"action_version":"1.0.0"'* ]]
  [[ "$body" == *'"detector_version":"v0.3.0"'* ]]
  [[ "$body" == *'"runner_os":"Linux"'* ]]
  [[ "$body" == *'"repo_hash":'* ]]
  # No raw repo URL or findings
  [[ "$body" != *"acme/widgets"* ]]
}

@test "telemetry.sh: succeeds even if curl fails (fire-and-forget)" {
  cat > "$TMPDIR_TEST/curl" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
  chmod +x "$TMPDIR_TEST/curl"
  run bash "$BATS_TEST_DIRNAME/../../scripts/telemetry.sh"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run, expect fail**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
./scripts/run-tests.sh
```

Expected: telemetry tests fail.

- [ ] **Step 3: Write `telemetry.sh`**

Create `scan-action/scripts/telemetry.sh`:

```bash
#!/usr/bin/env bash
# Fire-and-forget anonymous install heartbeat. Never fails the action.
set +e

INGEST_URL="${INPUT_TELEMETRY_URL:-https://skilltrust.io/api/telemetry/action-run}"
SCAN="$INPUT_SCAN_JSON"

if [ -z "$SCAN" ] || [ ! -f "$SCAN" ]; then
  exit 0
fi

GRADE="$(jq -r '
  if .axes then [.axes | to_entries[] | .value.grade] | sort | last
  else "" end' "$SCAN")"
[ "$GRADE" = "null" ] && GRADE=""
FINDING_COUNT="$(jq -r '.findings | length // 0' "$SCAN")"

REPO_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-unknown/unknown}"
REPO_HASH="$(printf '%s' "$REPO_URL" | shasum -a 256 | awk '{print $1}')"

VISIBILITY="public"
if [ "${GITHUB_REPOSITORY_VISIBILITY:-public}" != "public" ]; then
  VISIBILITY="private"
fi

PAYLOAD="$(jq -nc \
  --arg av  "${INPUT_ACTION_VERSION:-unknown}" \
  --arg dv  "${INPUT_DETECTOR_VERSION:-unknown}" \
  --arg os  "${RUNNER_OS:-unknown}" \
  --arg ar  "${RUNNER_ARCH:-unknown}" \
  --arg vis "$VISIBILITY" \
  --arg rh  "$REPO_HASH" \
  --arg g   "$GRADE" \
  --argjson fc "$FINDING_COUNT" \
  --arg trg "${GITHUB_EVENT_NAME:-unknown}" \
  --argjson de "${INPUT_DELTA_ENABLED:-false}" \
  '{
    action_version:   $av,
    detector_version: $dv,
    runner_os:        $os,
    runner_arch:      $ar,
    repo_visibility:  $vis,
    repo_hash:        $rh,
    grade:            $g,
    finding_count:    $fc,
    trigger:          $trg,
    delta_enabled:    $de
  }')"

echo "telemetry.sh: POST $INGEST_URL"
curl -fsS --max-time 3 -H "Content-Type: application/json" -X POST --data "$PAYLOAD" "$INGEST_URL" >/dev/null 2>&1 || true

exit 0
```

```bash
chmod +x "/Users/glibrulev/projects/saas/skil security/scan-action/scripts/telemetry.sh"
```

- [ ] **Step 4: Mirror in `telemetry.ps1`**

Create `scan-action/scripts/telemetry.ps1`:

```powershell
# Fire-and-forget. Never throw.
try {
  $ingestUrl = if ($env:INPUT_TELEMETRY_URL) { $env:INPUT_TELEMETRY_URL } else { "https://skilltrust.io/api/telemetry/action-run" }
  $scan = $env:INPUT_SCAN_JSON
  if (-not $scan -or -not (Test-Path $scan)) { return }

  $data    = Get-Content $scan -Raw | ConvertFrom-Json
  $axes    = if ($data.axes) { $data.axes } else { @{} }
  $grades  = @($axes.PSObject.Properties.Value.grade) | Sort-Object
  $worst   = if ($grades) { $grades[-1] } else { "" }
  $count   = if ($data.findings) { $data.findings.Count } else { 0 }

  $repoUrl  = "{0}/{1}" -f $env:GITHUB_SERVER_URL, $env:GITHUB_REPOSITORY
  $sha256   = [System.Security.Cryptography.SHA256]::Create()
  $bytes    = [System.Text.Encoding]::UTF8.GetBytes($repoUrl)
  $hash     = -join (($sha256.ComputeHash($bytes)) | ForEach-Object { $_.ToString("x2") })

  $visibility = if ($env:GITHUB_REPOSITORY_VISIBILITY -and $env:GITHUB_REPOSITORY_VISIBILITY -ne "public") { "private" } else { "public" }

  $payload = @{
    action_version   = $env:INPUT_ACTION_VERSION
    detector_version = $env:INPUT_DETECTOR_VERSION
    runner_os        = $env:RUNNER_OS
    runner_arch      = $env:RUNNER_ARCH
    repo_visibility  = $visibility
    repo_hash        = $hash
    grade            = $worst
    finding_count    = $count
    trigger          = $env:GITHUB_EVENT_NAME
    delta_enabled    = ($env:INPUT_DELTA_ENABLED -eq "true")
  } | ConvertTo-Json -Compress

  Invoke-RestMethod -Uri $ingestUrl -Method Post -Body $payload -ContentType "application/json" -TimeoutSec 3 | Out-Null
} catch {
  # Swallow all errors — fire-and-forget.
}
```

- [ ] **Step 5: Run tests**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
./scripts/run-tests.sh
```

Expected: telemetry tests pass.

- [ ] **Step 6: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
git add scripts/telemetry.sh scripts/telemetry.ps1 tests/bats/telemetry.bats
git commit -m "feat: telemetry.sh fire-and-forget POST with hashed repo identifier"
```

## Task E6: Wire telemetry into `action.yml`

**Files:**
- Modify: `scan-action/action.yml`

- [ ] **Step 1: Add `telemetry` input + steps**

Edit `scan-action/action.yml`. After the `comment:` input add:

```yaml
  telemetry:
    description: Send anonymous install heartbeat to skilltrust.io (no findings, no paths)
    required: false
    default: 'true'
```

Insert these steps before `Propagate exit code`:

```yaml
    - name: Send telemetry
      shell: bash
      if: inputs.telemetry == 'true' && runner.os != 'Windows'
      env:
        INPUT_SCAN_JSON:        ${{ steps.scan.outputs.scan-json-path }}
        INPUT_ACTION_VERSION:   1.0.0
        INPUT_DETECTOR_VERSION: ${{ inputs.detector-version }}
        INPUT_DELTA_ENABLED:    ${{ inputs.delta }}
      run: ${{ github.action_path }}/scripts/telemetry.sh

    - name: Send telemetry (Windows)
      shell: pwsh
      if: inputs.telemetry == 'true' && runner.os == 'Windows'
      env:
        INPUT_SCAN_JSON:        ${{ steps.scan-win.outputs.scan-json-path }}
        INPUT_ACTION_VERSION:   1.0.0
        INPUT_DETECTOR_VERSION: ${{ inputs.detector-version }}
        INPUT_DELTA_ENABLED:    ${{ inputs.delta }}
      run: ${{ github.action_path }}/scripts/telemetry.ps1
```

- [ ] **Step 2: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
git add action.yml
git commit -m "feat: action.yml wires telemetry step (opt-out via with: telemetry: false)"
```

## Task E7: Add Windows runner to matrix CI

**Files:**
- Modify: `scan-action/.github/workflows/ci.yml`

- [ ] **Step 1: Add `windows-latest` to the matrix**

Edit `scan-action/.github/workflows/ci.yml`. For both `smoke-clean` and `smoke-malicious` jobs, change `os: [ubuntu-latest, macos-latest]` to:

```yaml
        os: [ubuntu-latest, macos-latest, windows-latest]
```

- [ ] **Step 2: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
git add .github/workflows/ci.yml
git commit -m "ci: add windows-latest to smoke matrix"
```

## Task E8: README + Marketplace metadata

**Files:**
- Modify: `scan-action/README.md`
- Modify: `scan-action/action.yml`

- [ ] **Step 1: Write the README**

Replace `scan-action/README.md` with:

```markdown
# skilltrust/scan-action

GitHub Action that scans AI-agent configuration files (`SKILL.md`, `CLAUDE.md`, `.claude/`, `.mcp.json`, `.codex/`, `.opencode/`) for security threats using [skill-detector](https://github.com/velzepooz/skill-detector). Posts a sticky PR comment with a four-axis trust score and a build status driven by configurable thresholds.

## Quickstart

Add `.github/workflows/skilltrust.yml` to your repo:

```yaml
name: skilltrust
on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read
  pull-requests: write

jobs:
  skilltrust:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0   # required for delta vs base branch
      - uses: skilltrust/scan-action@v1
        with:
          delta: true
```

That's it. Open a PR; you'll get a sticky comment with the four-axis grade.

## Inputs

| Input | Default | Description |
|---|---|---|
| `path` | `.` | Path to scan |
| `fail-on` | `high` | Severity threshold: `critical`/`high`/`medium`/`low`/`info` |
| `fail-on-axis` | `''` | Per-axis grades, e.g. `permission_hygiene=C,security=C` |
| `strict-mcp` | `false` | Raise MCP external-domain rule severity from medium to high |
| `scan-all` | `false` | Disable scope tightening and `.gitignore` filtering |
| `delta` | `false` | Compute delta vs base branch (PR triggers only). Doubles runtime. |
| `comment` | `true` | Post sticky PR comment |
| `detector-version` | `v0.3.0` | Pin a specific `skill-detector` release |
| `telemetry` | `true` | Send anonymous install heartbeat. See **Telemetry** below. |
| `skilltrust-token` | `''` | Optional SaaS uplink token for cross-PR delta + team dashboards |
| `github-token` | `${{ github.token }}` | Token used to post PR comments |

## Outputs

| Output | Description |
|---|---|
| `grade` | Overall trust grade (worst axis): `A`/`B`/`C`/`D`/`F` |
| `scan-json-path` | Absolute path to scan result JSON in the runner |
| `findings-count` | Total finding count |

## Pinning

Recommended:

```yaml
- uses: skilltrust/scan-action@v1     # moves with minor/patch in v1.x
```

Supply-chain-strict:

```yaml
- uses: skilltrust/scan-action@<full-sha>
```

## Permissions

```yaml
permissions:
  contents: read         # checkout
  pull-requests: write   # post sticky comment
```

No `actions: write`, no `id-token: write`, no `packages: write`.

## Fork PRs

GitHub gives fork-origin PRs a read-only `GITHUB_TOKEN`, so the action cannot post a comment. The Action detects this and falls back to printing the comment markdown to the job log + emitting a `::warning::` annotation. Maintainers see the result in the job summary; the PR itself stays comment-free.

If you want comments on fork PRs, the `pull_request_target` event grants write tokens — at the documented cost of running against the base tree by default. We do not ship a `pull_request_target` workflow template because the safe pattern requires explicit checkout of `${{ github.event.pull_request.head.sha }}`, which reintroduces the supply-chain risk that `pull_request` exists to prevent.

## Telemetry

By default the Action sends a 1KB JSON heartbeat to `https://skilltrust.io/api/telemetry/action-run` once per run:

```json
{
  "action_version":   "1.0.0",
  "detector_version": "0.3.0",
  "runner_os":        "Linux",
  "runner_arch":      "X64",
  "repo_visibility":  "public",
  "repo_hash":        "<sha256(GITHUB_SERVER_URL + GITHUB_REPOSITORY)>",
  "grade":            "B",
  "finding_count":    4,
  "trigger":          "pull_request",
  "delta_enabled":    false
}
```

No commit SHAs. No branch names. No file paths. No finding details. No tokens. Just a coarse heartbeat so we know the install count.

Opt out by setting `telemetry: false`.

## License

MIT. See `LICENSE`.
```

- [ ] **Step 2: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
git add README.md
git commit -m "docs: full quickstart README with inputs, outputs, permissions, telemetry"
```

## Task E9: Tag scan-action v1.0.0 + v1

**Files:**
- Modify: `scan-action/CHANGELOG.md`
- Create: `scan-action/.github/workflows/release.yml`

- [ ] **Step 1: Fill in CHANGELOG**

Replace `scan-action/CHANGELOG.md`:

```markdown
# Changelog

## v1.0.0 — 2026-05-2X

Initial public release.

### Added
- Composite GitHub Action that downloads + verifies the `skill-detector` binary, scans the checked-out tree, and posts a sticky PR comment with a four-axis trust score.
- `delta: true` opt-in mode that fetches the base branch and shows ↑/↓ per axis + a "Why downgraded:" block.
- Multi-OS: `ubuntu-latest`, `macos-latest`, `windows-latest`.
- Fire-and-forget anonymous telemetry to `skilltrust.io` (opt-out via `telemetry: false`).
- Fork-PR graceful degradation (prints comment to job log + emits annotation).
```

- [ ] **Step 2: Add the release workflow**

Create `scan-action/.github/workflows/release.yml`:

```yaml
name: release

on:
  push:
    tags: ['v1.*']

jobs:
  move-major-tag:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Move v1 tag to current commit
        run: |
          git tag -f v1
          git push -f origin v1
```

- [ ] **Step 3: Commit + tag**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
git add CHANGELOG.md .github/workflows/release.yml
git commit -m "release: v1.0.0 — composite action with delta + telemetry"
git tag v1.0.0
```

- [ ] **Step 4: User pushes**

Do NOT push from the plan-runner. Confirm with the user and let them stage the push:

```bash
# User runs:
#   git push origin main
#   (wait for CI green on ubuntu + macos + windows)
#   git push origin v1.0.0
#   (release.yml moves v1 tag automatically)
```

## Task E10: Marketplace submission (manual user step)

The Marketplace listing is a human-driven flow on github.com. Document in the dogfood log:

- [ ] **Step 1: Append Marketplace step in dogfood log**

Edit `scan-action/docs/dogfood-2026-05-2X-sp5.md`. Append:

```markdown
## S5 — Telemetry + Windows + release

**Date:** 2026-05-2X

- skill-detector v0.3.0 tagged and binaries published
- skillmoss-go v0.5.0 deployed with `POST /api/telemetry/action-run` live
- Action tagged v1.0.0 + v1
- Matrix CI green on ubuntu-latest, macos-latest, windows-latest
- Telemetry POST verified end-to-end: open a self-PR on `skilltrust/scan-action`, then check `/internal/metrics` on skillmoss-go for an incremented `action_runs_24h`
- Action installed on `skill-detector` repo: confirm a real PR shows a SkillTrust comment + green check
- Action installed on `skillmoss-go` repo (optional, given the bot's own coverage)
- Marketplace listing submitted at https://github.com/marketplace/actions/skilltrust-scan (manual step in GitHub UI; verification can take days)
```

- [ ] **Step 2: Commit**

```bash
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
git add docs/dogfood-2026-05-2X-sp5.md
git commit -m "docs: dogfood log entry for S5 (release + Marketplace submit)"
```

## Task E11: Final checkpoint

Phase E complete. With the user, walk through the SP-5 Definition of Done (spec §11):

- [ ] `skilltrust/scan-action` repo public, tagged `v1.0.0` + moving `v1`.
- [ ] `action.yml` published with full input/output surface.
- [ ] Matrix CI green on ubuntu / macOS / windows × clean / malicious fixtures.
- [ ] `skill-detector v0.3.0` cut with `pkg/delta` + `skill-detector delta` sub-command. GoReleaser release published with checksums.
- [ ] `skillmoss-go` updated to consume `pkg/delta`; render snapshots byte-identical.
- [ ] `skillmoss-go` exposes `POST /api/telemetry/action-run` with rate-limit, schema validation, and `action_telemetry_pings` table.
- [ ] README with quickstart, perms, pinning, telemetry opt-out, fork-PR caveat.
- [ ] Marketplace listing submitted (verified badge follows after GitHub review).
- [ ] Action installed on `skill-detector` repo; real PR comment + green check screenshot captured.
- [ ] Dogfood log committed.

If any item is not met, file a follow-up in the dogfood log and decide with the user whether to ship v1.0.0 as-is + open SP-5.1 hotfix tickets, or block on it.

---

# Self-review against the spec

**Spec coverage check (mapped section → task):**

| Spec section | Implementation tasks |
|---|---|
| §2.1 Composite format | A7, A8 |
| §2.2 Repo layout | A1, A2 |
| §2.3 Cross-repo deliverables | C1–C5, E1–E4 |
| §3 Standalone vs SaaS-coupled | A7 (action.yml inputs), E5 (telemetry default), Phase B (gh api standalone) |
| §4 Scan execution | A3, A4, A5, A6, A7 |
| §4.1 Install detail | A3, A4 |
| §5.1 Delta flow | D2 |
| §5.2 pkg/delta extraction | C1, C2 |
| §5.3 CLI delta sub-command | C3, C4 |
| §5.4 skillmoss-go consumes library | C5 |
| §6.1 Sticky comment | B1, B2, B3, B4 |
| §6.2 Job-conclusion check | A5 (SCAN_EXIT_CODE) + A7 (Propagate step) |
| §6.3 Fork PRs | B2 (fork detection branch) |
| §7 action.yml | A7, B4, D3, E6 (incremental builds) |
| §8 Distribution + versioning | E9 |
| §9 Telemetry | E1, E2, E3, E4, E5, E6 |
| §10.1 Test layers | All Phase A/B/C/D/E tasks have bats or go tests |
| §10.2 Tracer-bullet slices | Phase A=S1, B=S2, C=S3, D=S4, E=S5 |
| §11 DoD | E11 checklist mirrors spec §11 |
| §12 Deferred items | Not implemented (correct) |

**Placeholder scan:**
- No `TODO`/`TBD` markers in code blocks.
- One `[Fill in after dogfood PR result]` in C6 — that's an intentional human-fill-in, not a plan defect.
- Task E3 has one explicit conditional comment ("If the rate-limit block above doesn't compile…") because the rate-limit middleware shape is project-specific and the plan can't pre-determine which branch applies. The conditional gives the engineer two complete code blocks to choose from, no guessing.

**Type consistency:**
- `delta.Delta` / `delta.GradeDelta` / `delta.Compute` consistent across tasks C1, C2, C3, C5.
- `prbot.Delta` retained for skillmoss-go callers (render.go); render.go untouched.
- `SCAN_EXIT_CODE` env var consistent: written by `scan.sh` (A5), consumed by Propagate step (A7).
- `SCAN_ACTION_DELTA_JSON` env var: written by `delta.sh` (D2), consumed by Render Comment step (D3).
- Action inputs naming consistent across `action.yml` and scripts (`INPUT_PATH`, `INPUT_FAIL_ON`, etc.).

**One gap fixed inline:** the spec §7 action.yml had an `outputs.grade` description matching the action; tasks A7 + B4 + D3 + E6 build that up across phases. Verified outputs are declared in A7 and never removed.

Plan complete and saved to `docs/superpowers/plans/2026-05-21-sp5-scan-action.md`.
