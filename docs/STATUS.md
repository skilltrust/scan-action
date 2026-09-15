# Status

## M2 — Free scan-action relaunch

ST-8 through ST-11 implemented locally on the M1 base.

- One bounded safe renderer owns Job Summary and PR comment presentation.
- Fixed attribution and a dated published-rule allowlist prevent URL data leak.
- Sticky delivery paginates, stands off for the App, avoids duplicate POSTs on
  lookup failure, and compares fork head/base repository identity before token
  delivery.
- README onboarding is report-only and documents raw JSON/artifacts, exact
  scope limits, forks, data flow, pinning, and default-on ten-field telemetry.
- Detector remains `v0.10.0`; raw Quality output and telemetry payload/default
  are unchanged.
- Critical review fixes enforce typed v0.10.0 finding entries, fail closed on
  malformed paginated comments, render Summary on every workflow trigger, and
  keep hostile scan paths out of delta annotations.
- Bash comment IDs are accepted only within jq's exact safe-integer range.

Local Bats, shell/Python checks, native PowerShell reporting/scan/delta checks,
real-engine policy fixtures, and the full local suite are phase acceptance
surfaces. Cross-OS composite CI and the live rule-page release gate remain
external release checks and were not triggered from this phase.
