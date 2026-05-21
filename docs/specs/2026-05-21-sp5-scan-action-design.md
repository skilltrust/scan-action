# SP-5 — `skilltrust/scan-action@v1` GitHub Action — Design

**Date:** 2026-05-21
**Status:** Draft — pending user review
**Target repos:** `skilltrust/scan-action` (new), `skill-detector` (`pkg/delta` extraction), `skillmoss-go` (`/api/telemetry/action-run` endpoint + switch to library delta)
**Predecessors:** SP-1 (multi-axis engine, v0.2.x), SP-2 (hosted scanner), SP-3 (badge service, v0.3.0), SP-4 (GitHub App + PR-comment bot, v0.4.0)
**Successor:** SP-6 (launch surfaces)

## 1. Overview

Ship `skilltrust/scan-action@v1` — a composite GitHub Action installable into any repo via a workflow file (`.github/workflows/skilltrust.yml`). On each pull request or push, the runner downloads the pinned `skill-detector` binary, scans the checked-out tree, and posts a sticky PR comment plus a build-status check — all from inside the customer's CI runner using the workflow's `GITHUB_TOKEN`.

The Action is the customer-facing install vector that drives Phase 1's "100+ Action installs" gate (PRD §Phase 1 → P1 Wedge gate). It is the lightweight, low-trust-ask counterpart to SP-4's server-side App.

### 1.1 Why two surfaces (App + Action)

| Surface | Trust ask | Acquisition profile | Lives in |
|---|---|---|---|
| **App (SP-4)** | Install App, grant repo perms, allow our server to fetch tarballs | Enterprise-y, opt-in, deeper integration | `skillmoss-go` server |
| **Action (SP-5)** | Copy-paste a workflow YAML; nothing leaves the runner by default | OSS-friendly, low-friction, copy-paste install | Customer CI runner |

Different funnels, same scan engine. A repo may install one or both; comment markers are distinct so the surfaces never collide (§6.1).

### 1.2 Scope decision

- **In scope:** Composite Action with cross-OS support (ubuntu / macOS / windows), binary install + checksum verify, scan invocation with full CLI flag surface, opt-in base-branch delta, sticky PR comment via `gh api`, exit-code-driven job pass/fail, opt-out telemetry uplink, `.skilltrust.yml` consumption (already in the CLI), marketplace listing.
- **In scope (cross-repo):** Extract `pkg/delta` from `skillmoss-go/internal/prbot/` into `skill-detector` as a shared library + new `skill-detector delta` sub-command. Add `POST /api/telemetry/action-run` endpoint to `skillmoss-go`.
- **Out of scope (deferred):** suppression UX from comment (P2), Slack/Teams push (P2), Stripe gating on private-repo runs (P2), SARIF output for Code Scanning (P2), self-hosted runner air-gapped install guide (P3), Marketplace verified-creator badge (post-launch ops).

### 1.3 Requirements traceability

| Requirement | Covered by |
|---|---|
| FR21 (install Action that runs scanner on push/PR) | §2 composite Action, §4 scan execution |
| FR22 (PR comment with four-axis score + deltas + downgrade explanation) | §5 delta extraction, §6.1 comment rendering |
| FR23 (Check Run pass/fail driven by configurable threshold) | §6.2 job-conclusion check |
| FR24 (free for public; private under Free tier closed beta P1) | §2 standalone — no server gate; gate lives in App (SP-4) for SaaS-coupled flows only |
| FR27 (re-runs update comment in place) | §6.1 marker-based sticky update |
| NFR48 (ubuntu / macOS / windows runners) | §2 composite multi-OS, §10 matrix CI |

## 2. Architecture

### 2.1 Action format — composite

Three GitHub Action formats considered:

| Format | Cold-start | Distribution | Multi-OS | Decision |
|---|---|---|---|---|
| **Composite (shell)** | ~0s | Download binary at runtime | Yes (bash + pwsh variants) | ✅ chosen |
| Docker container | 5–15s pull | Build + push image | Linux only — fails NFR48 | rejected |
| JavaScript (Node) | ~1s | Ship `dist/index.js` checked into the action repo | Yes | rejected — no existing JS code, overkill |

The `skill-detector` binary is already cross-platform via GoReleaser and already checksummed. Composite shell stays the simplest path.

### 2.2 Repository layout — `skilltrust/scan-action`

```
skilltrust/scan-action/
├── action.yml                # Public contract (inputs, outputs, steps)
├── scripts/
│   ├── install.sh            # Bash: download + verify binary (Linux/macOS)
│   ├── install.ps1           # PowerShell variant for Windows runners
│   ├── scan.sh / scan.ps1    # Run skill-detector + capture JSON
│   ├── report.sh / report.ps1 # Render markdown + post sticky comment via gh api
│   └── telemetry.sh          # Fire-and-forget POST to skillmoss-go
├── templates/
│   └── comment.md.tmpl       # Markdown template (envsubst-rendered)
├── tests/
│   ├── bats/                 # bats-core unit tests for install/scan/report scripts
│   └── fixtures/             # Tiny scan fixture repos (clean + malicious)
├── .github/workflows/
│   ├── ci.yml                # Test matrix: ubuntu / macOS / windows × fixture repos
│   └── release.yml           # Tag → marketplace publish + move `v1` tag
├── README.md                 # Quickstart, perms block, pinning guide, telemetry opt-out
├── LICENSE                   # MIT
└── CHANGELOG.md
```

### 2.3 Cross-repo deliverables

| Repo | Change | Reason |
|---|---|---|
| `skill-detector` | New `pkg/delta` package; new `skill-detector delta <base.json> <head.json>` sub-command | Shared between SP-4 worker and SP-5 Action — single source of truth |
| `skill-detector` | Tag `v0.3.0` after the above lands | Action pins to a specific detector release |
| `skillmoss-go` | Switch `internal/prbot.ComputeDelta` to call into `skill-detector/pkg/delta` (zero-behavior-change refactor; golden snapshots must remain identical) | Avoid drift between SP-4 and SP-5 delta semantics |
| `skillmoss-go` | New endpoint `POST /api/telemetry/action-run` (unauthenticated, rate-limited per-IP) | Phase 1 install-counting (§9) |

### 2.4 Topology

The Action runs entirely inside the customer's GitHub Actions runner. No skillmoss-go dependency for the standalone path. Optional fire-and-forget telemetry POST + optional SaaS uplink (`with: skilltrust-token: ...`) extend toward the SaaS but never block the check.

## 3. Standalone vs SaaS-coupled — standalone default, optional uplink

**Standalone (default):** Action runs entirely in the runner. PR comment posted via `gh api` with the workflow's `GITHUB_TOKEN`. No SaaS dependency. Works on any repo (public or private) without anything on our end.

**Optional uplink:** If user sets `with: skilltrust-token: ${{ secrets.SKILLTRUST_TOKEN }}`, the Action additionally POSTs the scan result to `https://skilltrust.io/api/scans/ingest` so the SaaS gets the result for cross-PR delta, team dashboards (P2), and central metrics rollup. Uplink is fire-and-forget (3s timeout, non-blocking). Failure to reach the SaaS never fails the check.

Trade-off accepted: SP-4 owns the rich server-side flow (base-scan cache, install state machine, `.skilltrust.yml` policy enforcement via Check Run conclusion). The Action's standalone path is intentionally a leaner subset — fast, no-account, copy-paste install. Users who want the deeper integration install the App.

## 4. Scan execution

```
1. actions/checkout@v4  (user's workflow does this before our action runs)
2. install.{sh|ps1}: download skill-detector binary for runner.os + runner.arch
   - URL: github.com/velzepooz/skill-detector/releases/download/v<VERSION>/skill-detector_<os>_<arch>.tar.gz
   - Verify against shipped checksums.txt (sha256, GoReleaser-emitted)
   - VERSION = pinned per action tag in scripts/install.sh; overridable via input
     `with: detector-version: <vX.Y.Z|latest>`
3. scan.{sh|ps1}: invoke detector
   skill-detector scan "$PATH" \
     --format json \
     --fail-on "$FAIL_ON" \
     [--fail-on-axis k=v ...] \
     [--strict-mcp] \
     [--scan-all] \
     > "$RUNNER_TEMP/scan.json"
   - `.skilltrust.yml` at repo root is consumed by the existing CLI cascading-config loader
4. (Optional) Delta path — see §5
5. report.{sh|ps1}: render markdown from scan.json (+ delta.json if present), post sticky comment
6. telemetry.{sh|ps1}: fire-and-forget POST (skipped if `with: telemetry: false`)
7. Exit with detector's exit code so the workflow step pass/fails naturally
```

### 4.1 Binary install detail (`install.sh`)

```bash
#!/usr/bin/env bash
set -euo pipefail
VERSION="${INPUT_DETECTOR_VERSION:-$DEFAULT_DETECTOR_VERSION}"
case "$RUNNER_OS" in
  Linux)   OS=linux;   EXT=tar.gz ;;
  macOS)   OS=darwin;  EXT=tar.gz ;;
  Windows) OS=windows; EXT=zip    ;;  # handled by install.ps1
esac
case "$RUNNER_ARCH" in
  X64)   ARCH=amd64 ;;
  ARM64) ARCH=arm64 ;;
esac
BASE="https://github.com/velzepooz/skill-detector/releases/download/${VERSION}"
ASSET="skill-detector_${OS}_${ARCH}.${EXT}"
curl -fsSL --retry 3 -o "$RUNNER_TEMP/$ASSET"        "$BASE/$ASSET"
curl -fsSL --retry 3 -o "$RUNNER_TEMP/checksums.txt" "$BASE/checksums.txt"
( cd "$RUNNER_TEMP" && sha256sum --check --ignore-missing checksums.txt )
tar -xzf "$RUNNER_TEMP/$ASSET" -C "$RUNNER_TEMP"
echo "$RUNNER_TEMP" >> "$GITHUB_PATH"
```

PowerShell variant (`install.ps1`) mirrors the same logic with `Invoke-WebRequest`, `Get-FileHash`, `Expand-Archive`.

## 5. Base-branch delta — opt-in, off by default

Computing delta means scanning *two* trees, doubling runtime. Most users want fast feedback first; delta is a nice-to-have. Off by default; turn on with `with: delta: true`.

### 5.1 Delta flow (when `delta: true` and trigger is `pull_request`)

```
1. base_ref="${{ github.event.pull_request.base.ref }}"
2. git fetch origin "$base_ref" --depth 1
3. git worktree add "$RUNNER_TEMP/base" FETCH_HEAD
4. skill-detector scan "$RUNNER_TEMP/base" --format json > "$RUNNER_TEMP/base-scan.json"
5. skill-detector delta "$RUNNER_TEMP/base-scan.json" "$RUNNER_TEMP/scan.json" \
     --format json > "$RUNNER_TEMP/delta.json"
6. Comment template includes the delta block when delta.json is present
```

On non-PR triggers (`push`), delta is auto-disabled (no base to compare against).

### 5.2 `pkg/delta` extraction

`skillmoss-go/internal/prbot/` currently owns the delta types and computation. SP-5 promotes this to a shared library so both the SP-4 worker and the SP-5 Action use one implementation.

Target package: `skill-detector/pkg/delta/`

```go
package delta

import (
    "github.com/velzepooz/skill-detector/pkg/axes"
    "github.com/velzepooz/skill-detector/pkg/model"
)

type GradeDelta struct {
    Old, New  model.Grade
    Direction string  // "up" | "down" | "same"
}

type Delta struct {
    PerAxis          map[axes.Axis]GradeDelta
    NewFindings      []model.Finding
    ResolvedFindings []model.Finding
    AxisExplanations map[axes.Axis]string
}

func Compute(base, head *model.ScanResult) Delta
```

Finding-match key (unchanged from SP-4): `(rule_id, file_path, line_no, message_hash)`.

### 5.3 `skill-detector delta` sub-command

```
skill-detector delta <base.json> <head.json> [--format json|markdown] [--no-color]
```

- Reads two `model.ScanResult` JSON files.
- Computes `delta.Delta`.
- Emits either machine-readable JSON (for the Action to template) or pre-rendered markdown (for ad-hoc CLI use).
- Pure function over JSON; no filesystem walking. Fast (<50ms typical).

### 5.4 `skillmoss-go` consumes the library

`skillmoss-go/internal/prbot/delta.go` shrinks to a thin shim that calls `delta.Compute`. Golden-file tests for `prbot.RenderComment` must remain byte-identical — this is the contract that proves the refactor is zero-behavior-change.

## 6. PR comment + check status

### 6.1 Sticky comment (PR triggers only)

Marker: `<!-- skilltrust:action:v1 -->` — distinct from SP-4's `<!-- skilltrust:bot:v1 -->` so the two surfaces never collide on a repo that has both installed.

Comment template (rendered by `report.sh` using `envsubst` over `templates/comment.md.tmpl`):

```markdown
<!-- skilltrust:action:v1 -->
## 🛡 SkillTrust — Trust Score: **${GRADE}**${DELTA_HEADER}

| Axis | Grade |${DELTA_COL_HEADER}
|------|-------|${DELTA_COL_SEP}
${AXIS_ROWS}

${WHY_DOWNGRADED_BLOCK}

${NEW_FINDINGS_BLOCK}

${RESOLVED_FINDINGS_BLOCK}

---
_Posted by [skilltrust/scan-action@v1](https://github.com/skilltrust/scan-action) · [Disable](https://github.com/skilltrust/scan-action#disable) · Detector ${DETECTOR_VERSION}_
```

When `delta: false` or trigger is `push`, the delta-shaped variables are empty strings and the template degrades to a no-delta layout.

Lifecycle via `gh api`:

```bash
existing=$(gh api "repos/$REPO/issues/$PR/comments" \
  --jq '.[] | select(.body | startswith("<!-- skilltrust:action:v1 -->")) | .id' \
  | head -1)
if [ -n "$existing" ]; then
  gh api -X PATCH "repos/$REPO/issues/comments/$existing" -F body=@"$RUNNER_TEMP/comment.md"
else
  gh api "repos/$REPO/issues/$PR/comments" -F body=@"$RUNNER_TEMP/comment.md"
fi
```

Required workflow perms (documented in README):

```yaml
permissions:
  contents: read
  pull-requests: write   # post sticky comment
```

### 6.2 Check status — job conclusion

GitHub already renders the workflow job in the PR's "Checks" tab with ✅/❌ derived from step exit codes. The Action's final step exits with the detector's exit code (`0` clean, `1` below-threshold findings, `2` at/above-threshold) — the workflow job inherits that conclusion. **No explicit `/check-runs` API call in v1.**

Trade-off: the check name is whatever the workflow `job:` is named. Users naming the job `skilltrust` (documented pattern in README) get a "skilltrust ✓" line in the PR UI. Explicit check-run creation deferred to v1.1 if branding feedback demands it.

### 6.3 Fork PRs

`pull_request` events from forked repos receive a read-only `GITHUB_TOKEN` — cannot post comments (standard GitHub limitation). v1 detects the fork case and degrades:

- Skip `gh api` POST/PATCH.
- Emit the comment markdown to the job log (visible in the Action run output).
- Emit a GitHub annotation summary: `::warning title=SkillTrust::Trust Score ${GRADE}; ${FINDING_COUNT} findings. See job log for details.`

README documents the `pull_request_target` workaround with its security caveat (it checks out the *base* tree by default — overriding to check out the PR head reintroduces the supply-chain risk that `pull_request` exists to prevent). v1 ships the safe default; users opting into `pull_request_target` accept the trade-off knowingly.

## 7. `action.yml` — public contract

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
    description: 'Per-axis grade thresholds, comma-separated, e.g. "permission=C,network=C"'
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
  delta:
    description: Compute delta vs base branch (PR triggers only). Doubles runtime.
    required: false
    default: 'false'
  comment:
    description: Post sticky PR comment (PR triggers only)
    required: false
    default: 'true'
  detector-version:
    description: Pin a specific skill-detector release (default = version pinned to this action tag)
    required: false
    default: ''
  telemetry:
    description: Send anonymous install heartbeat to skilltrust.io (no findings, no paths)
    required: false
    default: 'true'
  skilltrust-token:
    description: Optional SaaS uplink token. If set, scan results are POSTed to skilltrust.io for SaaS dashboards.
    required: false
    default: ''
  github-token:
    description: Token for posting PR comments. Default = workflow GITHUB_TOKEN.
    required: false
    default: ${{ github.token }}

outputs:
  grade:
    description: 'Overall trust grade (worst axis): A|B|C|D|F'
  scan-json-path:
    description: Absolute path to the scan result JSON in the runner
  findings-count:
    description: Total finding count

runs:
  using: composite
  steps:
    - name: Install skill-detector
      shell: bash
      if: runner.os != 'Windows'
      run: ${{ github.action_path }}/scripts/install.sh
    - name: Install skill-detector (Windows)
      shell: pwsh
      if: runner.os == 'Windows'
      run: ${{ github.action_path }}/scripts/install.ps1
    - name: Run scan
      shell: bash
      if: runner.os != 'Windows'
      run: ${{ github.action_path }}/scripts/scan.sh
    - name: Run scan (Windows)
      shell: pwsh
      if: runner.os == 'Windows'
      run: ${{ github.action_path }}/scripts/scan.ps1
    - name: Compute delta
      shell: bash
      if: inputs.delta == 'true' && github.event_name == 'pull_request' && runner.os != 'Windows'
      run: ${{ github.action_path }}/scripts/delta.sh
    - name: Compute delta (Windows)
      shell: pwsh
      if: inputs.delta == 'true' && github.event_name == 'pull_request' && runner.os == 'Windows'
      run: ${{ github.action_path }}/scripts/delta.ps1
    - name: Post sticky comment
      shell: bash
      if: inputs.comment == 'true' && github.event_name == 'pull_request' && runner.os != 'Windows'
      run: ${{ github.action_path }}/scripts/report.sh
    - name: Post sticky comment (Windows)
      shell: pwsh
      if: inputs.comment == 'true' && github.event_name == 'pull_request' && runner.os == 'Windows'
      run: ${{ github.action_path }}/scripts/report.ps1
    - name: Send telemetry
      shell: bash
      if: inputs.telemetry == 'true' && runner.os != 'Windows'
      run: ${{ github.action_path }}/scripts/telemetry.sh
    - name: Send telemetry (Windows)
      shell: pwsh
      if: inputs.telemetry == 'true' && runner.os == 'Windows'
      run: ${{ github.action_path }}/scripts/telemetry.ps1
    - name: Propagate exit code
      shell: bash
      run: exit ${SCAN_EXIT_CODE:-0}
```

The detector's exit code is captured into `$SCAN_EXIT_CODE` (`$GITHUB_ENV`) by `scan.sh` so subsequent steps still run (telemetry + comment) but the final step fails the job correctly.

## 8. Distribution + versioning

- **Repo:** `github.com/skilltrust/scan-action` (new GitHub org `skilltrust`, new public repo). MIT-licensed.
- **Tags:**
  - `v1.0.0` — immutable per-release tag.
  - `v1` — moving tag, auto-bumped on each patch + minor release in v1.x.
  - No `latest` tag (well-documented anti-pattern for Actions).
- **Marketplace listing:** required for Marketplace discovery + the "✓ verified" badge in search UI. Submit after first user-installable release.
- **Pinning recommendation in README:** `uses: skilltrust/scan-action@v1` for convenience; `uses: skilltrust/scan-action@<sha>` for supply-chain-strict users.

## 9. Telemetry — Phase 1 install counting

Phase 1's go/no-go gate requires "100+ GitHub Action installs". Three counting sources considered:

| Source | Pros | Cons |
|---|---|---|
| **A. Fire-and-forget POST to `/api/telemetry/action-run`** | Real-time, captures runner OS + visibility + grade | Customer can disable; visible in runner network logs |
| **B. GitHub Marketplace install count** | Authoritative, GitHub-counted | Available only post-Marketplace listing; lag time; coarse |
| **C. Server-side weekly GitHub code-search** | No customer participation needed | Misses private repos; rate-limited; lossy |

**Chosen: A + C.** Default-on telemetry POST with documented opt-out (`with: telemetry: false`). C runs server-side weekly as a cross-check / belt-and-suspenders. B comes online when Marketplace listing lands.

### 9.1 Payload (1KB JSON, GDPR-conscious)

```json
{
  "action_version": "1.0.0",
  "detector_version": "0.3.0",
  "runner_os": "Linux",
  "runner_arch": "X64",
  "repo_visibility": "public",
  "repo_hash": "<sha256(GITHUB_SERVER_URL + GITHUB_REPOSITORY)>",
  "grade": "B",
  "finding_count": 4,
  "trigger": "pull_request",
  "delta_enabled": false
}
```

Excluded: commit SHAs, branch names, file paths, finding details, repo full name, user identifiers. Just a coarse heartbeat.

### 9.2 Endpoint — `POST /api/telemetry/action-run` (in `skillmoss-go`)

- Unauthenticated. Rate-limited per-IP (`internal/web/ratelimit.go` already provides this) — 60 req/min/IP.
- Body cap 4KB.
- Schema-validated (reject unknown fields).
- Stored in new table `action_telemetry_pings(id, received_at, payload JSONB, src_ip_hash)`.
- Aggregated by daily job into `action_install_counts(date, unique_repo_hashes_24h, runs_24h)`.
- Surfaced via the existing `/internal/metrics` endpoint (SP-4 §8.2) — new keys `action_installs_unique_7d`, `action_runs_24h`.

## 10. Testing strategy + tracer-bullet slices

### 10.1 Test layers

| Layer | Location | What |
|---|---|---|
| Go unit | `skill-detector/pkg/delta/` | Table-driven `Compute` tests; golden-file fixtures for representative deltas (clean→clean, clean→downgrade, downgrade→clean, mixed) |
| Go unit | `skill-detector/cmd/skill-detector/delta_test.go` | CLI sub-command: stdin-or-file input, format flag, exit code |
| Go integration | `skillmoss-go/internal/prbot/render_test.go` | Existing golden-file snapshots — assert byte-identical output after switching to `pkg/delta` |
| Shell unit | `scan-action/tests/bats/` | bats-core tests for `install.sh`, `scan.sh`, `report.sh`, `delta.sh`, `telemetry.sh` with mocked `gh` and `curl` (bats-mock) |
| Action integration | `scan-action/.github/workflows/ci.yml` | Matrix: `{ubuntu-latest, macos-latest, windows-latest}` × `{clean-fixture, malicious-fixture, downgrade-pr-fixture}`. Asserts exit code, comment presence on PR fixture, JSON output well-formed |
| Dogfood | manual | Install action on `skill-detector` and `skillmoss-go` repos; open a real PR; capture screenshot |

Run skill-detector + skillmoss-go suites per existing project conventions:
- `skill-detector`: `go test ./...`
- `skillmoss-go`: `go test ./... -p 1` with `TEST_DATABASE_URL=postgres://skillmoss:skillmoss@localhost:5432/skillmoss_test?sslmode=disable` ([[test-db-isolation]])

### 10.2 Tracer-bullet slices

Each slice ends with a demoable behavior and a real-repo dogfood entry in `scan-action/docs/dogfood-2026-05-2X-sp5.md` (mirrors SP-1, SP-3, SP-4 dogfood pattern).

| Slice | Demoable | Key tests | Dogfood target |
|---|---|---|---|
| **S1 — Binary install + scan** | Composite action scaffold; downloads detector, runs scan, prints text to job log, exits with detector exit code. No comment yet. | install.sh checksum verify (positive + tampered); scan.sh exit-code passthrough; matrix CI green on 3 OSes | Open a no-op PR on a fixture repo in `skilltrust/scan-action-test-fixture`; ✅ check appears |
| **S2 — Sticky PR comment** | `report.sh` posts a marker-tagged comment via `gh api`; re-runs update in place. No delta yet. | comment.md template render; gh api mock (POST + PATCH paths); fork-PR fork-detection + log fallback | Open a PR on `skill-detector` repo with a known finding; comment appears with current grade. Re-push → same comment updates. |
| **S3 — `pkg/delta` extraction (skill-detector + skillmoss-go)** | New `pkg/delta` library + `skill-detector delta` sub-command. `skillmoss-go/internal/prbot` switches to the library. **Zero-behavior-change refactor.** | Golden-file snapshots in `skillmoss-go/internal/prbot/testdata/` byte-identical pre/post; new CLI sub-command tests | Tag `skill-detector v0.3.0`; rebuild + redeploy `skillmoss-go`; verify SP-4 PR comments still render identically on a real PR |
| **S4 — Action delta input** | Action gets `with: delta: true`. Fetches base via `git fetch --depth 1`, scans both trees, calls `skill-detector delta`, renders comment with ↑/↓ column + WHY block | delta.sh path; comment.md template delta branch | Open PR on `skill-detector` that downgrades an axis; comment shows the delta + WHY line |
| **S5 — Telemetry + multi-OS + Marketplace submit** | Fire-and-forget POST live (with skillmoss-go endpoint). Full matrix green. Tag `v1.0.0` + `v1`. Marketplace listing submitted. | telemetry.sh smoke against staging endpoint; opt-out asserts no POST; rate-limit test on the server endpoint | Action installed on `skill-detector` and `skillmoss-go` repos in production; 3 OSes confirmed via separate matrix run; telemetry pings visible in `/internal/metrics` |

## 11. Definition of done

- `skilltrust/scan-action` repo public, tagged `v1.0.0` + moving `v1`.
- `action.yml` published with full input/output surface (§7).
- Matrix CI green: `ubuntu-latest` × `macos-latest` × `windows-latest` × `{X64, ARM64 where available}` × `{clean, malicious, downgrade}` fixtures.
- `skill-detector v0.3.0` cut with `pkg/delta` + `skill-detector delta` sub-command. GoReleaser release published with checksums.
- `skillmoss-go` updated to consume `pkg/delta`; existing `prbot` golden snapshots byte-identical (proves zero-behavior-change refactor).
- `skillmoss-go` exposes `POST /api/telemetry/action-run` (unauthenticated, rate-limited, schema-validated). New `action_telemetry_pings` table migration applied.
- README in `scan-action`: quickstart YAML, `permissions:` block, pinning guide (sha vs `v1`), telemetry opt-out, fork-PR caveat.
- Marketplace listing submitted (verified badge follows after GitHub review).
- Action installed on `skill-detector` repo itself; one real PR comment + green check screenshot captured for SP-5 release notes.
- Dogfood log committed at `scan-action/docs/dogfood-2026-05-2X-sp5.md`.

## 12. Open questions

None at design time. Deliberate deferrals (not open questions):

- **Explicit Check Run via API (vs job-conclusion check):** deferred to v1.1 if branding feedback demands "SkillTrust" as the check name regardless of workflow job naming.
- **SARIF output for GitHub Code Scanning:** deferred to P2 — high-value cross-promotion surface, but separable scope.
- **Suppression UX from the Action's comment:** deferred to P2, same scope decision as SP-4 FR26.
- **Self-hosted runner air-gapped install guide:** deferred to P3.

---

_See also: [[skilltrust-status]] for SP-1..SP-6 sequencing; [[docs-locations]] for prior specs + plans; [[substrate-stack]] for which repo holds which code; [[execution-preferences]] for the subagent-driven execution style this project uses._
