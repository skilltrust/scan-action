# scan-action — Glossary

Terms in the sense this repository uses them. Terms are alphabetical.

Engine terms — axis, grade, finding, severity, delta — belong to
`skill-detector` and are defined in that repository's own glossary. This page
defines only what is specific to the Action.

### Composite action

A GitHub Action defined entirely by `runs: using: composite` plus an ordered
list of steps that shell out. No compiled code, no container, no JavaScript
bundle. It is what this repository is, and the reason every behaviour here
lives in a shell script rather than in a program.

### Delta mode

`delta: true`. On pull-request triggers the Action also scans the base ref and
runs the engine's `delta` sub-command, so the comment shows per-axis movement,
a "Why downgraded" block and a resolved-findings block instead of a flat grade
table.

It **doubles runtime**, because it means two full scans. Off by default. It
also needs the base ref to be fetchable, which is why the documented workflow
checks out with `fetch-depth: 0`.

### Detector version

The `detector-version` input: which `skill-detector` release the install step
downloads. It defaults to a version pinned in `action.yml`, so a given Action
tag always installs the same engine and a repository's grade does not shift
underneath it when the engine releases.

### Fork degradation

A pull request from a fork gets a read-only `GITHUB_TOKEN`, so posting a
comment would fail. Rather than failing the build, `report.{sh,ps1}` detects
this from `INPUT_IS_FORK_PR`, prints the rendered comment into the job log
inside a `::group::`, emits a `::warning::` annotation and exits 0. The
maintainer sees the result in the job log; the pull request itself stays
comment-free.

### Gate defaults

The two inputs that decide whether a build nobody configured goes red:
`fail-on: critical` and `warn-on-below-threshold: 'true'`. Together they mean
only a CRITICAL finding fails the build. Everything below that is reported and
does not block the merge.

Each is written in more than one place — `action.yml` plus a fallback inside
the script that consumes it — and `action.yml` is the source of truth.
`tests/bats/gate-defaults.bats` reads `action.yml` and pins the copies to it.

### Floating `v1`

The tag consumers pin: `skilltrust/scan-action@v1`. It is not a release; it is
a pointer. `.github/workflows/release.yml` force-moves it to each new `v1.*`
tag, so a user pinning `@v1` picks up fixes without editing their workflow.
The immutable `v1.x.y` tags stay for anyone who wants an exact pin, and a
commit SHA is the strictest pin available.

Because `v1` moves, it may only move across changes that are compatible for
someone who never looked: a renamed or removed input or output needs a `v2`.

### No agent surface

The state a scan reports when it found no agent configuration files at all in
the scanned path — nothing to grade, so no grade was produced. Surfaced as the
`no-agent-surface` output.

It is **not** a passing scan, and the Action says so: the annotation and the
sticky comment both state that nothing was checked rather than showing a
trust score. The build still passes by default, because a repository that
genuinely has no agent configuration would otherwise be permanently red with
no fix available. `fail-on-no-agent-surface: true` opts into gating on it.

### `SCAN_EXIT_CODE`

The engine's exit code, captured by the scan step through `$GITHUB_ENV` and
deliberately **not** raised there. The final step re-raises it.

This deferral is what lets the delta, comment and telemetry steps run even
when the scan fails — without it, a failing scan would also be a silent one.

### Script pair

Every step's implementation exists twice: `scripts/foo.sh` for bash on POSIX
runners and `scripts/foo.ps1` for pwsh on Windows runners, selected by
`runner.os` in `action.yml`. The two must stay behaviourally identical; change
one and not the other and Windows diverges silently, because nothing compares
them.

The rule scopes to steps selected by `runner.os`. `run-tests.sh` never runs on
a runner and `propagate-exit.sh` is `shell: bash` on every OS, so neither has a
`.ps1` half and neither is a violation.

### Smoke job

A CI job that runs the **real** Action against a fixture repository on a real
runner, as opposed to the bats suites, which run the scripts against fakes.
Five exist. They are the only check that the composite wiring and the env
contract actually hold on a runner.

`smoke-malicious` asserts the Action *fails*. Asserting a failure rather than a
success is what keeps exit-code propagation verified: a job that only checked
for success would still pass if the final step were deleted.

### Sticky comment

The single pull-request comment the Action maintains, identified by the marker
`<!-- skilltrust:action:v1 -->` as the first line of the body. On each run
`report.{sh,ps1}` searches the PR's comments for that marker and **patches**
the one it finds, rather than posting a new one.

The marker string is a wire contract. Changing it orphans every comment
already posted — the next run cannot find them, so it posts a second comment
beside each one.

### Superseded comment

What the Action leaves behind when the SkillTrust GitHub App is also
commenting on a pull request. The two use different markers by design, so a
repository running both would otherwise carry two grade comments. On finding
the App's marker `<!-- skilltrust:bot:v1 -->`, the Action replaces its own
comment body with a short note and stops posting. It keeps running the checks;
it just stops duplicating the report.

Replacing rather than deleting is deliberate: leaving the old body would read
as a second, disagreeing bot, and deleting is irreversible and fails on a
read-only token.

### Telemetry payload

Ten anonymous fields POSTed once per run: the Action and engine versions, the
runner OS and architecture, the repository's visibility, a **hash** of the
repository URL, the grade, the finding count, the trigger, and whether delta
was enabled. No repository name, no paths, no branch, no commit, no finding
contents.

Fire-and-forget: the request is time-limited and its failure is swallowed, so
the build never breaks over it. Opt out with `telemetry: false`.
