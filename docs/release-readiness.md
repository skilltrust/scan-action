# M3 release readiness

M3 implements ST-12, ST-13, and the local/reproducible portion of ST-14. This
file separates local evidence from GitHub-hosted and live acceptance; the latter
must not be inferred from prepared workflow code.

## Hosted checks completed

PR [#22](https://github.com/skilltrust/scan-action/pull/22) candidate
`2be9d833f3b3315a7defe0556c7483f6cebc1ce4` completed the prepared hosted
workflow on 2026-09-17. [CI run 35200736807](https://github.com/skilltrust/scan-action/actions/runs/35200736807)
passed the policy matrix, real detector installation, Linux/macOS/Windows
composite and smoke jobs, delta, sticky delivery and native Windows paths.
[CodeQL run 35200734100](https://github.com/skilltrust/scan-action/actions/runs/35200734100)
also passed. The PR comment was updated in place and inspected at DPR2.
Workflow success does not itself prove every Job Summary's visual body; item 4
below remains the acceptance boundary.

This does not authorize or prove a merge, release, tag or Marketplace change.
Release metadata still needs the selected version bump, and the site must ship
`/docs/action` before the release link gate can pass.

## Local acceptance surface

- `./scripts/run-tests.sh`: script policy, delta, delivery, rendering, privacy,
  install fixtures, action wiring, and README contracts.
- `./tests/e2e/local-composite-equivalent.sh`: exact Linux scripts in composite
  order; exits 0/1/2/3/42, report-only and legacy policy, strict-worse axis,
  both no-surface modes, all outputs, complete JSON, difficult path, and repeat
  invocation.
- `./tests/e2e/m1-policy.sh` and `./tests/e2e/gate-defaults.sh`: pinned detector
  v0.10.0 severity/default/axis gates.
- `./tests/pwsh/parse-all-ps1.sh` plus every `exec-*.sh`: native PowerShell parse
  and execution for scan, delta, render/delivery, install, and telemetry.
- `./tests/e2e/readme-candidate.sh`: independently copies the README candidate
  to a disposable file, parses its YAML, and checks report-only, history,
  detector pin, input names, and bridged outputs.

All synthetic delivery and telemetry checks use local fakes. They make no API,
comment, or telemetry request.

## GitHub acceptance contract

`.github/workflows/ci.yml` ran through the authorized normal pull-request path.
The acceptance surface remains:

1. `m3-composite-policy`: every synthetic case invokes `uses: ./`; verify all
   matrix legs, outputs, complete JSON, report-only/error distinction, and exit
   42 behavior.
2. `m3-composite-supported`: Linux, macOS, and Windows each install detector
   v0.10.0 and complete clean/findings/empty/error invocations while consumers
   open JSON and read every output.
3. Existing real-engine and smoke jobs: default/strict-axis gates, delta,
   sticky POST then repeat PATCH, Windows render/delivery, and below-threshold
   behavior.
4. Inspect each valid invocation's Job Summary for clean, critical, empty,
   truncated, and delta-unavailable presentation. Workflow success alone does
   not prove this visual surface.
5. On a real fork PR, confirm token withholding, inert log rendering, no Action
   comment, and App coexistence. On a same-repository PR in a forked repository,
   confirm normal sticky delivery.
6. Confirm optional artifact upload retains complete JSON when report-only
   converts an expected findings block to success.
7. Run the release rule-page gate only when live network acceptance is
   authorized.

## Local-only boundaries

- Local execution creates no GitHub-hosted workflow, Summary, comment or
  artifact; the hosted evidence above owns those claims.
- No real fork token boundary, App comment coexistence, API pagination, or
  GitHub 403/429/5xx response was exercised; deterministic fakes cover them.
- No release, tag, Marketplace operation, external repository access, or live
  telemetry request was performed.
- Local macOS/Windows release assets use exact fixture paths; the hosted matrix
  owns native-kernel evidence.
