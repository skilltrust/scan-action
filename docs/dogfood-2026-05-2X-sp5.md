# SP-5 scan-action dogfood log

Real-world verification of each tracer-bullet slice.

## S1 — Binary install + scan

**Date:** 2026-05-2X
**Target:** TBD after first remote push

_To be filled after first matrix run on GitHub-hosted runners._

## S2 — Sticky PR comment

**Date:** 2026-05-2X

_To be filled after opening a PR on the scan-action repo itself; expect a sticky comment with the worst axis grade D (from `malicious-repo` fixture)._

## S3 — pkg/delta extraction (skill-detector + skillmoss-go)

**Date:** 2026-05-21

- skill-detector v0.3.1 shipped (v0.3.0 had `crypto/sha1` lint issue; v0.3.1 uses `hash/fnv` for semantic correctness — see CHANGELOG)
- skillmoss-go `prbot.ComputeDelta` refactored to thin adapter over `pkg/delta`
- 158 tests green in skillmoss-go; render golden snapshot `internal/prbot/testdata/comment_golden.md` byte-identical pre/post

## S4 — Action delta input

**Date:** 2026-05-2X

_To be filled after opening a PR that intentionally downgrades an axis (e.g. add a wildcard bash perm). Verify comment shows ↓ B → D and a "Why downgraded:" line._

## S5 — Telemetry + Windows + release

**Date:** 2026-05-21 (local) — push pending user-created `skilltrust/scan-action` GitHub org

- skill-detector v0.3.1 tagged + binaries published (resolved gosec sha1 lint issue with hash/fnv switch)
- skillmoss-go v0.5.0-equivalent deployed-pending: migration 0008 + `POST /api/telemetry/action-run` + `/internal/metrics` extended with `action_installs_unique_7d` + `action_runs_24h`
- scan-action tagged v1.0.0 locally; CHANGELOG + release.yml in place to move `v1` tag on each `v1.*` push
- Matrix CI configured: ubuntu-latest + macos-latest + windows-latest × {clean, malicious} fixtures, plus smoke-pr-comment + smoke-pr-delta jobs for PR events
- Telemetry POST end-to-end ready: action calls `telemetry.sh` → posts to skillmoss-go endpoint → row lands in `action_telemetry_pings` → surfaces in `/internal/metrics`
- Marketplace listing submission: manual step on GitHub UI after the first remote push lands (https://github.com/marketplace/actions/skilltrust-scan)

