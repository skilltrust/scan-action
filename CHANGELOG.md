# Changelog

## v1.0.0 — 2026-05-21

Initial public release.

### Added
- Composite GitHub Action that downloads + verifies the `skill-detector` binary, scans the checked-out tree, and posts a sticky PR comment with a four-axis trust score.
- `delta: true` opt-in mode that fetches the base branch and shows ↑/↓ per axis + a "Why downgraded:" block.
- Multi-OS: `ubuntu-latest`, `macos-latest`, `windows-latest`.
- Fire-and-forget anonymous telemetry to `skilltrust.io` (opt-out via `telemetry: false`).
- Fork-PR graceful degradation (prints comment to job log + emits annotation).
