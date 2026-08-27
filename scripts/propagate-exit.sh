#!/usr/bin/env bash
set -euo pipefail

# Final step of the action: re-raise the exit code scan.sh/scan.ps1 deferred
# into SCAN_EXIT_CODE, so the intervening comment/delta/telemetry steps got to
# run first.
#
# NOT a script pair, deliberately. ADR-0002's "change one, change both" rule
# covers scripts selected by `runner.os`; this step is `shell: bash` on every
# OS and reaches Windows through Git Bash, exactly like the inline `run:` it
# replaced. Precedent: `run-tests.sh` is bash-only too. Do not add a `.ps1`.
#
# Required env:
#   SCAN_EXIT_CODE                 deferred scanner exit code (unset = 0)
# Optional env:
#   INPUT_WARN_ON_BELOW_THRESHOLD    "true" | "false" (default "true", mirroring action.yml)
#   INPUT_GRADE                      scan step `grade` output, for the annotation
#   INPUT_FINDINGS_COUNT             scan step `findings-count` output, ditto
#   INPUT_NO_AGENT_SURFACE           scan step `no-agent-surface` output, "true" | "false"
#   INPUT_FAIL_ON_NO_AGENT_SURFACE   `fail-on-no-agent-surface` input (default "false")
#   GITHUB_EVENT_NAME                set natively by the runner. The below-threshold
#                                    annotation points at the PR comment only when this is
#                                    "pull_request" — the comment steps in action.yml are
#                                    themselves gated on that event, so on any other trigger
#                                    (e.g. a push build) there is no comment to point at, and
#                                    the annotation points at the job log and scan JSON instead.
#
# Engine exit codes (skill-detector ADR-0006):
#   0  no findings
#   1  findings, all below the fail-on / fail-on-axis threshold
#   2  a finding at or above the threshold
#   3  tool error — the scan did not run
#
# Only 1 is ever downgraded, and only when asked. 2 is a real breach; 3 means
# there is no scan result at all, and a scan that could not run is not a
# passing scan. Anything else is a code this version does not know about and
# is re-raised untouched rather than guessed at.

CODE="${SCAN_EXIT_CODE:-0}"

# A scan that read no agent surface produced no grade. The exit code is the
# machine-readable claim, and with no grade asserted there is nothing to
# disbelieve — so the default is 0 WITH the claim withdrawn loudly, in the
# annotation and in the PR comment. Failing by default was rejected: a repo
# that genuinely has no agent files would go red permanently with no fix
# available, and the first thing anyone does with a permanent red is delete
# the gate. Teams for whom this is a real gate opt in. ADR-0020 (skilltrust).
#
# Guarded on CODE = 0: no agent surface means no findings, which today only
# ever means exit 0. But a tool error (3) or a real breach (2) must never be
# reinterpreted as "nothing was checked" just because the flag also happens
# to be set — those fall through untouched to the final `exit "$CODE"` below,
# same as any other code this block doesn't recognize.
if [ "$CODE" = "0" ] && [ "${INPUT_NO_AGENT_SURFACE:-false}" = "true" ]; then
  echo "::warning title=SkillTrust::no agent configuration files were found — nothing was checked. This is NOT a passing scan. Check the 'path' input, or set fail-on-no-agent-surface: true to gate on it."
  if [ "${INPUT_FAIL_ON_NO_AGENT_SURFACE:-false}" = "true" ]; then
    exit 2
  fi
  exit 0
fi

if [ "$CODE" = "1" ] && [ "${INPUT_WARN_ON_BELOW_THRESHOLD:-true}" = "true" ]; then
  DETAIL="grade ${INPUT_GRADE:-?}"
  if [ -n "${INPUT_FINDINGS_COUNT:-}" ]; then
    DETAIL="${INPUT_FINDINGS_COUNT} finding(s), $DETAIL"
  fi
  # The PR comment steps only run on `github.event_name == 'pull_request'`
  # (action.yml); on any other trigger there is no comment to send anyone to.
  if [ "${GITHUB_EVENT_NAME:-}" = "pull_request" ]; then
    WHERE="review the PR comment"
  else
    WHERE="review the job log and the scan JSON"
  fi
  echo "::warning title=SkillTrust::${DETAIL} — all below your fail-on threshold, so the build is not failed (warn-on-below-threshold is on); ${WHERE}, or set warn-on-below-threshold: false to gate on them."
  exit 0
fi

exit "$CODE"
