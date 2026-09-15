# Status

## M3 — Free scan-action relaunch

ST-12, ST-13, and the locally implementable portion of ST-14 are complete on
the immutable M2 base `6bc299704c3680a553c3046f3d25b41c2ca5bfbe`.

- CI now has real `uses: ./` policy and supported-OS output matrices; synthetic
  legs disable telemetry/comments. Final policy is `always()`.
- Deterministic local matrices cover policy, delta, hostile rendering, delivery
  events/forks/App/pagination/API failures, and exact ten-field privacy capture.
- POSIX and Windows installer fixtures cover exact v0.10.0 assets, checksum,
  version, tamper, missing checksum, download failure, and unsupported arch.
- The README candidate is independently copied and parsed in a disposable
  harness. Complete raw JSON remains unchanged after expected report-only blocks.
- M1/M2 public inputs, outputs, defaults, detector pin, telemetry payload and
  default, safe rendering, and sticky markers remain intact.

Local acceptance commands and exact unavailable external requirements are in
`docs/release-readiness.md`. No hosted workflow, comment, Summary acceptance,
release, tag, Marketplace action, external private access, or live telemetry
was performed in M3.
