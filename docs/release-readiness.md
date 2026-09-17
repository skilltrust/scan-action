# M3 release readiness

M3 implements ST-12, ST-13, and the local/reproducible portion of ST-14. This
file separates local evidence from GitHub-hosted and live acceptance; the latter
must not be inferred from prepared workflow code.

## Hosted checks completed

Post-merge fixes, 2026-09-17: PR
[#23](https://github.com/skilltrust/scan-action/pull/23) merged telemetry
visibility privacy and neutral checkout reporting after
[CI 35257679617](https://github.com/skilltrust/scan-action/actions/runs/35257679617)
passed the Linux/macOS/Windows matrix, PowerShell paths, policy matrix, PR
comment and delta jobs. [CodeQL 35257676188](https://github.com/skilltrust/scan-action/actions/runs/35257676188)
also passed. Current `main` is the accepted release candidate.

The production site deployment completed after one transient dependency-proxy
retry. `/action` and `/docs/action` return HTTP 200, `/ci` returns 404, and the
canonical, sitemap, llms.txt, desktop, narrow and open-menu checks pass.

Historical pre-merge evidence (not rerun by the post-merge review):

PR [#22](https://github.com/skilltrust/scan-action/pull/22) candidate
`2be9d833f3b3315a7defe0556c7483f6cebc1ce4` completed the prepared hosted
workflow on 2026-09-17. [CI run 35200736807](https://github.com/skilltrust/scan-action/actions/runs/35200736807)
passed the policy matrix, real detector installation, Linux/macOS/Windows
composite and smoke jobs, delta, sticky delivery and native Windows paths.
[CodeQL run 35200734100](https://github.com/skilltrust/scan-action/actions/runs/35200734100)
also passed. The PR comment was updated in place and inspected at DPR2.
Workflow success does not itself prove every Job Summary's visual body; item 4
below remains the acceptance boundary.

Compatible version v1.11.0 was released on 2026-09-17 at commit `38647dbc`.
[Release workflow 35260091823](https://github.com/skilltrust/scan-action/actions/runs/35260091823)
passed the live rule-page gate and moved floating `v1` to the same commit.
Downloaded `v1` and `v1.11.0` archives were identical; metadata and the
extracted composite policy/output matrix passed. The workflow does not create
a GitHub Release or publish/update a Marketplace listing.

## Release gate and owner operations

- Live read-only checks on 2026-09-17: `/docs/action` and `/action` return 200,
  `/ci` returns 404, and all 25 allowlisted rule pages pass
  `tests/release/check-published-rules.sh`.
- Immutable `v1.11.0` and floating `v1` both resolve to the accepted release
  commit. Changelog date, README and both telemetry version literals match it;
  detector remains v0.10.0.
- The visibility and checkout-label findings are merged with regression
  coverage and full hosted checks; see `STATUS.md`.
- Complete the remaining hosted acceptance below, particularly rendered
  Summary, real fork/App delivery, and artifact retrieval/retention.
- Separately verify authenticated Marketplace owner state. Public exact search
  did not expose a SkillTrust listing after release, so listing state must not
  be inferred from tags. Any Marketplace publication/update remains a separate
  owner operation.

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
