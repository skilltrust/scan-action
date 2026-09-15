# Status

## M1 — Free scan-action relaunch

Implementation complete locally for ST-5, ST-6, and ST-7.

- `report-only` is opt-in; findings remain visible, operational failures fail.
- POSIX and Windows scans validate results and publish all four public outputs
  from the branch that ran.
- Delta uses equivalent scope controls and degrades explicitly to unavailable
  without changing the head result.
- Detector remains pinned to `v0.10.0`; telemetry defaults and payload unchanged.

Local Bats, shell syntax, PowerShell parse/execute when available, real Git
delta fixtures, and real-engine gate checks are the acceptance surfaces.
Cross-OS composite CI remains a release gate and was not run for this
local-only implementation.
