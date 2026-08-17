# Changelog

## [Unreleased]

### Added
- The sticky PR comment's footer now links to
  `skilltrust.app/ci?src=action`, the funnel page for the hosted App.

### Changed
- **The Action yields to the SkillTrust GitHub App.** If a PR already carries
  the App's comment (its own sticky marker), `report.sh`/`report.ps1` no
  longer post a second, competing grade: a fresh run stays quiet, and a run
  that had already posted its own comment replaces it with a short
  "superseded" note pointing at the App's comment instead. Running both the
  Action and the App on the same repository is now safe by design, not by
  accident.
- **README repositioned:** the Action is now introduced as the free,
  runner-local tier of SkillTrust, with a comparison table against the
  hosted GitHub App, rather than as a standalone wrapper around
  `skill-detector`. No input, output or scanning behavior changed.

## v1.3.0 — 2026-08-14

### Changed
- **Default `detector-version` is now `v0.6.0`** (was `v0.5.0`). Users pinned to
  `@v1` pick this up automatically.

### Why
- Engine v0.6.0 fixes two behaviors this action surfaces directly:
  - **`delta` no longer reports churn on line shifts** — inserting a line above
    a finding used to turn every finding below the edit into a `resolved` +
    `new` pair, so the PR comment listed phantom "New findings" (and a
    threshold check could fail) on whitespace-only changes. Line-shifted
    findings are now paired off and only real changes are reported.
  - **`delta` output is deterministic** — new/resolved lists follow scan order
    instead of map iteration order, so re-runs render identical comments.
  - Also upstream: capability inference covers ten more rules (the
    `permissions` block in scan JSON gets richer), triage verdict matching is
    collision-safe, and the registry checksum is **unchanged**
    (`589619b6386d2c41`) — no grading changes.

### Compatibility
- **No input or output changes.** Detection results change only via the engine
  bump; grading (axis letter) behavior is identical.

## v1.2.0 — 2026-08-05

### Changed
- **Default `detector-version` is now `v0.5.0`** (was `v0.4.0`). Users pinned to
  `@v1` pick this up automatically.

### Documented
- Engine v0.5.0 makes a **breaking change to the exit-code contract**: a new
  exit `3` (tool error — bad arguments, unreadable path, internal failure) is
  now distinct from `1` (findings below threshold) and `2` (findings at/above
  threshold). This action already passed every detector exit code through
  opaquely (`SCAN_EXIT_CODE`), so no script change was needed — `3` fails the
  job exactly as `1`/`2` do, which is correct: a scan that could not run is
  not a passing scan. Documented in `README.md`'s new "Exit codes" section and
  `docs/glossary.md`.

### Why
- Engine v0.5.0 adds `SD-024` (MCP auto-installed package execution — flags
  `npx`/`uvx`/`pipx`/`bunx` as an MCP server's `command`), extends several
  content rules to more agent harnesses (Codex, Gemini CLI, Cursor, Windsurf,
  Copilot), and fixes a gitignore-matching gap. See the `skill-detector`
  changelog for the full list, including scan-result changes (SD-018 rename,
  SD-023 severity downgrade, SD-001 fence-scoping fix).

### Compatibility
- **No input or output changes.** The exit-code *contract* changed upstream,
  but this action's behavior (opaque passthrough) did not — `3` was already
  propagated the same as any other non-zero code before this release, just
  untested and undocumented on this side.
- **Scan results can change** the same way any engine bump does: new rules may
  surface findings that previously passed.

---

## v1.1.0 — 2026-07-31

### Changed
- **Default `detector-version` is now `v0.4.0`** (was `v0.3.1`). Users pinned to
  `@v1` pick this up automatically.

### Fixed
- Release downloads now point at `github.com/skilltrust/skill-detector`. The
  previous URL used the pre-transfer `velzepooz` org and resolved only through
  GitHub's redirects, which expire — installs would eventually have 404'd.
- `action_version` reported in telemetry was hardcoded to `1.0.0`; it now
  matches the release tag.

### Why
- Two engine releases had shipped since the pinned version, so `@v1` users were
  missing two detection rules:
  - **`SD-022`** — DNS exfiltration / tunneling (`dig`, `nslookup`, `drill`
    combined with a dynamically built hostname). Added in engine v0.3.2 after it
    was the only miss in the SP-7 validation benchmark.
  - **`SD-023`** — unrestricted `"*"` permission grant in
    `.claude/settings.json`. Added in engine v0.3.3 after a wildcard grant was
    found to slip past `SD-017`/`SD-018`/`SD-019`.
- Engine v0.4.0 also adds an inert triage seam. It changes nothing for this
  action: with no verifier injected — which is every CLI invocation — the
  scanner behaves exactly as v0.3.x and emits the same JSON.

### Compatibility
- **No input, output or exit-code changes.** Nothing in the action's API moved.
- **Scan results can change.** A repository using DNS-based exfiltration or a
  wildcard permission grant will now be flagged where it previously passed. A
  build gated on `fail-on` may start failing — which is the point.

---

## v1.0.0 — 2026-05-21

Initial public release.

### Added
- Composite GitHub Action that downloads + verifies the `skill-detector` binary, scans the checked-out tree, and posts a sticky PR comment with a four-axis trust score.
- `delta: true` opt-in mode that fetches the base branch and shows ↑/↓ per axis + a "Why downgraded:" block.
- Multi-OS: `ubuntu-latest`, `macos-latest`, `windows-latest`.
- Fire-and-forget anonymous telemetry to `skilltrust.app` (opt-out via `telemetry: false`).
- Fork-PR graceful degradation (prints comment to job log + emits annotation).
