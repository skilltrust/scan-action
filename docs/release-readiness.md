# M3 release readiness

M3 implements ST-12, ST-13, and the local/reproducible portion of ST-14. This
file separates local evidence from GitHub-hosted and live acceptance; the latter
must not be inferred from prepared workflow code.

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

## Prepared authorized GitHub acceptance

Run `.github/workflows/ci.yml` through the normal pull-request path only after
authorization. Required green evidence:

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

## Deliberately unavailable in M3 local execution

- No GitHub-hosted Linux/macOS/Windows workflow was dispatched.
- No live Job Summary or GitHub comment was created or visually accepted.
- No real fork token boundary, App comment coexistence, API pagination, or
  GitHub 403/429/5xx response was exercised; deterministic fakes cover them.
- No release, tag, Marketplace operation, external repository access, or live
  telemetry request was performed.
- macOS/Windows release assets were validated through exact local fixture paths,
  not executed on hosted native kernels. The prepared matrix owns that evidence.
