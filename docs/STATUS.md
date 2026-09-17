# Status

## ST-5 — Report UX candidate

The complete relaunch candidate is pushed to draft PR #22 at
`98ea7876bbb9d8b61e053b00bac6dfe324cf7aa2`. Fresh hosted
[CI 35232093627](https://github.com/skilltrust/scan-action/actions/runs/35232093627)
passed the full Linux/macOS/Windows matrix, and
[CodeQL 35232087915](https://github.com/skilltrust/scan-action/actions/runs/35232087915)
passed. No merge, release, tag, floating-v1 move or Marketplace change was
performed.

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
- Compatible v1.11.0 Action metadata is prepared in PR #22. The Pencil-approved
  site is in draft PR #157 with green hosted checks but remains unmerged, so
  production `/docs/action` is still unavailable. No release, tag, floating-v1
  move or Marketplace change was performed.
- Final relaunch review fixes fail closed on non-Boolean no-surface flags,
  malformed axis objects and non-string/non-uppercase PowerShell grades.
  No-surface telemetry now retains the empty grade and numeric zero count
  without changing its field set.
- Local verification: 119 Bats tests, including thirteen Python UX tests; all
  six native PowerShell harnesses (7.6.6 on Linux); real v0.10.0 gate-defaults
  and m1-policy; local composite-equivalent harness. Bash/PowerShell parity and
  the ten-field no-surface telemetry payload are pinned.
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
- Independent critical review found two report-boundary gaps: malformed or
  contradictory fixed delta entries could be presented as available, and an
  invalid boolean input could be described as passing before final policy
  rejected it. Both now fail closed. Scoped re-review passed after 13/13 Python
  UX tests, 52/52 focused renderer/policy/delivery Bats tests, malformed delta
  probes and direct parity checks against `propagate-exit.sh`.

Limits: local Markdown preview is not GitHub-hosted rendering; narrow Chromium
is not a physical phone. Native local PowerShell ran on Linux; hosted Windows
owns native evidence. Release requirements remain in
`docs/release-readiness.md`.
