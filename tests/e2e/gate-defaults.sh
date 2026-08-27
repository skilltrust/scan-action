#!/usr/bin/env bash
set -euo pipefail

# Verification cases 2-4 of docs/specs/2026-08-27-gate-defaults-design.md,
# executed against the REAL engine and the REAL fixtures.
#
# bats runs against tests/bats/fixtures/fake-detector.sh, which returns
# whatever exit code the test hands it. It can prove the plumbing and never
# that tests/fixtures/one-high-repo yields exactly one HIGH finding, or that
# critical-repo yields a CRITICAL one. If the engine's severity assignments
# move, this file is what goes red -- STATUS.md has carried that risk as
# known debt since v1.5.0.
#
# The thresholds are READ OUT OF action.yml rather than written down here, so
# this fails if the default regresses, not just if the scripts do.
#
# Bash-only and deliberately NOT part of ./scripts/run-tests.sh: that
# entrypoint is hermetic (fakes only, no network), and this needs a real
# skill-detector. Same shape as tests/pwsh/*.sh -- its own CI job installs the
# pinned engine first.
#
# Usage: put skill-detector (the version action.yml pins) on PATH, then
#   ./tests/e2e/gate-defaults.sh
#
# The engine's version is enforced, not just echoed: a stale skill-detector on
# PATH would otherwise let this harness run to completion and report a
# confident wrong answer. Escape hatch: SKILL_DETECTOR_VERSION_CHECK=off skips
# the check, because a locally source-built engine reports a dev version
# string (e.g. "0.1.0-dev") while still carrying the pinned ruleset, and that
# is how this harness gets run outside CI. CI itself installs the pinned
# release before running this script (see .github/workflows/ci.yml), so it
# stays strict without ever needing the hatch.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ACTION_YML="$ROOT/action.yml"

for bin in skill-detector jq; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "gate-defaults.sh: $bin not on PATH" >&2
    exit 1
  }
done

# Prints the `default:` value of a named top-level input block in action.yml.
input_default() {
  awk -v name="$1" '
    $0 == "  " name ":" { inb = 1; next }
    inb && /^  [a-z][a-z0-9-]*:$/ { inb = 0 }
    inb && /^    default:/ { sub(/^    default:[ \t]*/, ""); print; exit }
  ' "$ACTION_YML" | tr -d "'\""
}

DEFAULT_FAIL_ON="$(input_default fail-on)"
DEFAULT_WARN="$(input_default warn-on-below-threshold)"
PINNED_ENGINE="$(input_default detector-version)"

[ -n "$DEFAULT_FAIL_ON" ] || { echo "gate-defaults.sh: could not read the fail-on default from action.yml" >&2; exit 1; }
[ -n "$DEFAULT_WARN" ]    || { echo "gate-defaults.sh: could not read the warn-on-below-threshold default from action.yml" >&2; exit 1; }

echo "gate-defaults.sh: action.yml defaults — fail-on=$DEFAULT_FAIL_ON warn-on-below-threshold=$DEFAULT_WARN"

FOUND_VERSION="$(skill-detector version)"
echo "gate-defaults.sh: action.yml pins engine $PINNED_ENGINE; PATH has $FOUND_VERSION"

# Compare with and without a leading "v" — action.yml's default carries one,
# `skill-detector version` output may or may not.
PINNED_BARE="${PINNED_ENGINE#v}"
if [[ "$FOUND_VERSION" != *"$PINNED_ENGINE"* && "$FOUND_VERSION" != *"$PINNED_BARE"* ]]; then
  if [ "${SKILL_DETECTOR_VERSION_CHECK:-}" = "off" ]; then
    echo "gate-defaults.sh: WARNING — SKILL_DETECTOR_VERSION_CHECK=off, ignoring the mismatch (pinned $PINNED_ENGINE, PATH has $FOUND_VERSION). This is expected for a local source build that carries the pinned ruleset but not the release version string; it is NOT expected in CI." >&2
  else
    echo "gate-defaults.sh: skill-detector on PATH ($FOUND_VERSION) does not match action.yml's pinned $PINNED_ENGINE." >&2
    echo "gate-defaults.sh: if this is a local source build with the pinned ruleset (which reports a dev version, not the release tag), set SKILL_DETECTOR_VERSION_CHECK=off and re-run." >&2
    exit 1
  fi
fi

FAILURES=0
fail() { echo "  FAIL: $*" >&2; FAILURES=$((FAILURES + 1)); }

# Runs scan.sh then propagate-exit.sh exactly as action.yml chains them, and
# echoes "<final-exit>\t<propagate-exit stdout>\t<scan json path>".
run_action() {
  local fixture="$1" fail_on="$2" warn="$3"
  local work; work="$(mktemp -d)"
  : > "$work/env"; : > "$work/out"

  RUNNER_TEMP="$work" GITHUB_ENV="$work/env" GITHUB_OUTPUT="$work/out" \
    INPUT_PATH="$ROOT/tests/fixtures/$fixture" \
    INPUT_FAIL_ON="$fail_on" INPUT_FAIL_ON_AXIS="" \
    INPUT_STRICT_MCP="false" INPUT_SCAN_ALL="false" \
    bash "$ROOT/scripts/scan.sh" > "$work/scan.log" 2>&1

  local code grade findings surface
  code="$(sed -n 's/^SCAN_EXIT_CODE=//p' "$work/env")"
  grade="$(sed -n 's/^grade=//p' "$work/out")"
  findings="$(sed -n 's/^findings-count=//p' "$work/out")"
  surface="$(sed -n 's/^no-agent-surface=//p' "$work/out")"

  set +e
  SCAN_EXIT_CODE="$code" \
    INPUT_WARN_ON_BELOW_THRESHOLD="$warn" \
    INPUT_GRADE="$grade" INPUT_FINDINGS_COUNT="$findings" \
    INPUT_NO_AGENT_SURFACE="$surface" INPUT_FAIL_ON_NO_AGENT_SURFACE="false" \
    bash "$ROOT/scripts/propagate-exit.sh" > "$work/propagate.log" 2>&1
  local final=$?
  set -e

  LAST_FINAL="$final"
  LAST_OUTPUT="$(cat "$work/propagate.log")"
  LAST_JSON="$work/scan.json"
  LAST_ENGINE_EXIT="$code"
}

echo
echo "case 2: one HIGH finding, action.yml defaults — must pass with a warning annotation"
run_action one-high-repo "$DEFAULT_FAIL_ON" "$DEFAULT_WARN"
sev="$(jq -r '[.findings[].severity] | sort | join(",")' "$LAST_JSON")"
[ "$sev" = "HIGH" ] || fail "expected exactly one HIGH finding, got [$sev]"
[ "$LAST_ENGINE_EXIT" = "1" ] || fail "expected engine exit 1, got $LAST_ENGINE_EXIT"
[ "$LAST_FINAL" -eq 0 ] || fail "expected the action to exit 0, got $LAST_FINAL"
case "$LAST_OUTPUT" in
  *"::warning title=SkillTrust::"*) ;;
  *) fail "expected a ::warning:: annotation, got: $LAST_OUTPUT" ;;
esac

echo "case 3: the same fixture with an explicit fail-on: high — must fail"
run_action one-high-repo high "$DEFAULT_WARN"
[ "$LAST_FINAL" -ne 0 ] || fail "expected a non-zero exit with fail-on: high, got 0"
[ "$LAST_FINAL" -eq 2 ] || fail "expected exit 2 (threshold breach), got $LAST_FINAL"

echo "case 4: a CRITICAL finding, action.yml defaults — must fail"
run_action critical-repo "$DEFAULT_FAIL_ON" "$DEFAULT_WARN"
jq -e '[.findings[].severity] | index("CRITICAL")' "$LAST_JSON" >/dev/null \
  || fail "expected a CRITICAL finding in the fixture, got $(jq -c '[.findings[].severity]' "$LAST_JSON")"
[ "$LAST_FINAL" -ne 0 ] || fail "expected a non-zero exit on a CRITICAL finding, got 0"
[ "$LAST_FINAL" -eq 2 ] || fail "expected exit 2, got $LAST_FINAL"

echo "case 5 (sanity): a clean repository under the defaults — must pass silently"
run_action clean-repo "$DEFAULT_FAIL_ON" "$DEFAULT_WARN"
[ "$LAST_FINAL" -eq 0 ] || fail "expected exit 0 on clean-repo, got $LAST_FINAL"
case "$LAST_OUTPUT" in
  *"::warning"*) fail "expected no ::warning annotation on clean-repo (that would make \"silently\" false), got: $LAST_OUTPUT" ;;
esac

echo
if [ "$FAILURES" -ne 0 ]; then
  echo "gate-defaults.sh: $FAILURES assertion(s) failed" >&2
  exit 1
fi
echo "gate-defaults.sh: all cases passed"
