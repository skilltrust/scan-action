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
