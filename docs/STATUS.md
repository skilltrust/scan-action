# Status

## ST-5 — Report UX, local candidate

Base: remote `epic/ST-5-free-scan-action-relaunch`, verified at
`e6c7832b8cb9df8237f819e2f98182578c86eb61`. Local branch:
`feat/ST-5-report-ux`. No push, release, tag, or hosted workflow triggered.

- Shared Summary/comment renderer now leads with count, actual check policy,
  PR comparison and next action. New findings expand first; existing findings
  collapse; fixed findings name base locations. Grades and metadata come last.
- Review follow-up: title explicitly counts current issues; fixed count is a
  separate line. Status describes the SkillTrust check, never an unconditional
  merge block. Base disclosures expose effective CRITICAL/HIGH counts across
  all existing findings, even when the shared detail budget is exhausted.
- Detector v0.10.0 delta identity inspected at its release tag. New occurrences
  are subtracted from head using the same identity fields, preserving counts.
  Off/unavailable delta never claims new/existing/fixed counts. No run history.
- Full-head gating, raw JSON, public API/defaults, telemetry, fixed links/UTM,
  sticky marker, fork/App handling and pagination unchanged. Detail budgets
  remain ten head plus ten fixed findings.
- Local verification: 116 Bats tests, including eleven Python UX tests; all six
  native PowerShell harnesses (7.4.6 on Linux); real v0.10.0 gate-defaults and
  m1-policy; local composite-equivalent harness. Bash/PowerShell reports match.
- Real detector delta verified a shifted existing finding alongside two new,
  two existing and one fixed. Fake API checks prove repeat PATCH to one comment
  and independent lookup/POST for another PR; no GitHub writes performed.
- Local GitHub-like GFM preview: Chromium at 1280 and 390 CSS px, DPR 2;
  blocking, report-only/delta, unavailable, clean, no-surface and hostile data.
  No page overflow with disclosures closed/open; existing disclosure click and
  safe-link/hostile-markup DOM checks pass. Representative screenshots inspected.
- Review follow-up rerenders additionally cover base-only CRITICAL, singular,
  unknown policy and below-threshold states. Top copy is shorter; no additional
  finding details or policy-cause attribution are introduced.

Limits: local Markdown preview is not GitHub-hosted rendering; narrow Chromium
is not a physical phone. Native PowerShell ran on Linux, not Windows. Hosted
acceptance and release requirements remain in `docs/release-readiness.md`.
