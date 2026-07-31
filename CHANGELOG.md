# Changelog

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
