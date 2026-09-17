# Status

## Post-merge behavior fixes — 2026-09-17

Based on the same current `origin/main` merge commit linked below. The prior
documentation commit is preserved; both behavior findings are now fixed.

- Both telemetry steps pass event repository visibility explicitly. Exact
  `public` sends public, `private`/`internal` send private; absent, unknown or
  differently cased values send no heartbeat. No new payload fields or raw data.
- Reports use "Workflow checkout" on every trigger. They do not infer actual
  checkout identity from PR event metadata. README still selects PR head
  explicitly; synthetic merge and custom checkouts get the same honest label.
- Regression-first: new visibility and checkout tests failed on old POSIX
  behavior; the new wiring test failed; native PowerShell failed with
  `telemetry value mismatch`. All pass after the fixes.
- Verification: 122/122 Bats tests; native PowerShell 7.6.6 on Linux (all six
  parse/execution harnesses); pinned real detector v0.10.0 installer, gate
  defaults and m1-policy; local composite-equivalent and README contracts.
  No live telemetry or GitHub writes. Native Windows/macOS and hosted acceptance
  for these follow-up commits still require owner-authorized CI.

Release remains NO-GO for the site `/docs/action` 404 and outstanding hosted
acceptance. This repository does not deploy the site. See release-readiness.

## Historical post-merge documentation review — before behavior fixes

The following records the initial findings and checks, not unresolved runtime
defects or the current local tool availability.

Reviewed exact current `origin/main`, PR #22's
[merge commit](https://github.com/skilltrust/scan-action/commit/2c847f0de7193ab818d2965ec3df5ad9f1cd4de4).
GitHub reports this repository PUBLIC. Fresh read-only inspection confirmed
[CI 35254445155](https://github.com/skilltrust/scan-action/actions/runs/35254445155)
and [CodeQL 35254457527](https://github.com/skilltrust/scan-action/actions/runs/35254457527)
success on that commit; PR-only comment/delta jobs were skipped on push.

Documentation corrections: report-only precedence, Python renderer/runtime,
validated-result step guards and internal output, pseudonymous telemetry,
output retention on policy failure, GitHub report lifetimes, explicit PR-head
checkout and candidate/released-version separation. No runtime logic changed.
The README contract test now rejects a default synthetic-merge checkout.

Local checks: 119/119 Bats tests passed, including the Python report UX suite.
The local composite-equivalent and copied README contract harnesses passed.
Native PowerShell is unavailable in this orb; hosted checks above are separate
evidence, not a local rerun. No new hosted workflow or delivery was triggered.

Remaining behavior findings (not fixed by this documentation-only review):

- **Medium, pre-existing:** `telemetry.{sh,ps1}` derives `repo_visibility`
  from `GITHUB_REPOSITORY_VISIBILITY`, which is not a GitHub default variable;
  `action.yml` does not supply it. Absent that variable, a private repository
  is labelled public. Both telemetry tests inject it explicitly, masking the
  missing production wiring. Fix needs a separately approved behavior change.
- **Medium:** `render.py` labels every `pull_request` checkout "Pull request
  head", even when the caller selected GitHub's default synthetic merge ref
  or another ref. The corrected quickstart selects head explicitly; custom
  workflows remain subject to this presentation mismatch. The scan itself
  uses the actual checkout, not the label.

Release remains NO-GO: live `/docs/action` returned 404 while all 25 rule pages
passed. `v1` still points to v1.10.0 without report-only. See
`release-readiness.md` for owner acceptance and Marketplace operations.
No push, PR write, release/tag move, Marketplace mutation or live telemetry.

## Historical ST-5 candidate record — before merge

The following is retained history, not current branch/release status or fresh
verification by the post-merge reviewer.

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
