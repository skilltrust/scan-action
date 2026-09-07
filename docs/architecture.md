# scan-action — Architecture

Single source of truth for how the Action is wired: the steps, the script
pairs, and the contract between them. `AGENTS.md` carries the day-to-day rules
and does not repeat this.

Everything below is stated from `action.yml` and `scripts/`. When the two
disagree with this page, they are right and this page is stale — fix it.

## What it is

A **composite** GitHub Action. `action.yml` declares the inputs, the outputs
and an ordered list of steps; every step shells out to a script in `scripts/`.

There is no compiled code in this repository, and no code from the engine
either. The Action downloads a released `skill-detector` binary, runs it, and
reads its JSON and its exit code.

Each script whose step is selected by `runner.os` exists twice — `.sh` for
bash, `.ps1` for pwsh. Two scripts are bash-only and are deliberately not
pairs, because no `runner.os` condition picks them:

- `run-tests.sh` — the local test entrypoint. Never runs on a runner at all.
- `propagate-exit.sh` — its step is `shell: bash` on every OS and reaches
  Windows through Git Bash.

## Step pipeline

Seven logical steps, in `action.yml` order. Each appears twice there — a
POSIX branch gated on `runner.os != 'Windows'` and a Windows branch gated on
`runner.os == 'Windows'` — except the last, which is one step on every OS.

| # | Step | Runs when | Script |
|---|---|---|---|
| 1 | Install | always | `install.{sh,ps1}` |
| 2 | Scan | always | `scan.{sh,ps1}` |
| 3 | Compute delta | `delta == 'true'` **and** the event is `pull_request` | `delta.{sh,ps1}` |
| 4 | Render comment | the event is `pull_request` **and** `comment == 'true'` | `render-comment.{sh,ps1}` |
| 5 | Post sticky comment | the event is `pull_request` **and** `comment == 'true'` | `report.{sh,ps1}` |
| 6 | Send telemetry | `telemetry == 'true'` | `telemetry.{sh,ps1}` |
| 7 | Propagate exit code | always | `propagate-exit.sh` |

Note step 6's condition: telemetry is **not** gated on the event, so it runs on
a push build as well as a pull request.

**Step 7 is why steps 3–6 can run at all.** Step 2 captures the engine's exit
code instead of failing on it, and step 7 re-raises it at the very end — so a
failing scan still gets its comment posted and its telemetry sent. Delete step
7 and a failing scan becomes a silent one.

### Step 1 — install

Maps `RUNNER_OS` and `RUNNER_ARCH` to the release asset's OS/arch pair
(`Linux`→`linux`, `macOS`→`darwin`; `X64`→`amd64`, `ARM64`→`arm64`) and refuses
to continue on anything else. Downloads the tarball for
`detector-version` and the release's `checksums.txt` from the engine's GitHub
releases, **verifies the SHA-256 before extracting**, then appends the
extraction directory to `$GITHUB_PATH` so later steps find `skill-detector` on
`PATH`.

### Step 2 — scan

Builds the engine's argument list from the inputs — always
`scan <path> --format json --fail-on <fail-on>`, plus one `--fail-on-axis`
argument per comma-separated spec, plus `--strict-mcp` and `--scan-all` when
those inputs are `'true'` — and writes the result to `$RUNNER_TEMP/scan.json`.

The engine's exit code is captured, not raised. The step reads `grade`,
`findings-count` and `no-agent-surface` back out of the JSON with `jq`, so
`jq` must be present for those three outputs to be set; `scan-json-path` is
set regardless.

`grade` is the worst axis, computed as the lexicographically last grade letter
across `.axes` — `A` through `F` sort in severity order.

### Step 3 — delta

Fetches the base ref at depth 1, adds a detached worktree for it under
`$RUNNER_TEMP`, scans that tree, and runs `skill-detector delta base head` to
produce `$RUNNER_TEMP/delta.json`.

The base scan's exit code is discarded. `--fail-on` and `--fail-on-axis` are
therefore deliberately not threaded into it: they set an exit code and nothing
else, so threading them would change nothing.

`delta.{sh,ps1}` do read `INPUT_STRICT_MCP` and `INPUT_SCAN_ALL` and append
the matching flags when either is `'true'`. `action.yml` currently forwards
three variables to this step — `INPUT_BASE_REF`, `INPUT_HEAD_SCAN_JSON` and
`INPUT_PATH` — so under the composite action the base scan runs without those
two flags. `tests/bats/delta.bats` pins the script-level behaviour in both
directions, set and unset.

### Steps 4 and 5 — render and post

`render-comment` fills `templates/comment.md.tmpl` from the scan JSON, and
from the delta JSON when there is one, writing `$RUNNER_TEMP/comment.md`. With
a delta it emits a three-column axis table with movement arrows, a "Why
downgraded" block and a resolved-findings block; without one, a two-column
axis table. Findings are sorted by severity then rule ID and **truncated to
the first ten**. When the scan reports no agent surface it swaps the heading
and drops the axis and findings blocks entirely.

`report` posts that file. It searches the PR's comments for a body starting
with the marker and **patches** the existing comment when it finds one, or
posts a new one when it does not — that is the whole of the stickiness
mechanism. Three branches come before the normal path:

- **Fork PR** (`INPUT_IS_FORK_PR == 'true'`): prints the rendered comment into
  the job log inside a `::group::`, emits a `::warning::` annotation, exits 0.
  A fork-origin PR gets a read-only token, so posting would fail.
- **The App is already commenting**: if a comment starting with the App's
  marker `<!-- skilltrust:bot:v1 -->` exists, the Action replaces its own
  comment with a superseded note and exits, rather than leaving a second,
  disagreeing grade on the PR.
- Otherwise, patch or post.

### Step 6 — telemetry

POSTs a JSON heartbeat and cannot fail the build: `set +e` at the top,
`curl … || true`, `exit 0` at the bottom, and a hard `--max-time`. It exits 0
immediately if the scan JSON is missing.

### Step 7 — propagate exit

Re-raises `SCAN_EXIT_CODE` unchanged, with two exceptions, in this order:

1. **No agent surface.** If the code is `0` and `no-agent-surface` is `true`,
   emits a `::warning::` saying nothing was checked, then exits `2` if
   `fail-on-no-agent-surface` is `'true'` and `0` otherwise. Guarded on code
   `0`: a breach (`2`) or a tool error (`3`) must never be reinterpreted as
   "nothing was checked".
2. **Below threshold.** If the code is `1` and `warn-on-below-threshold` is
   `'true'` (the default), emits a `::warning::` naming the finding count and
   grade, and exits `0`.

Anything else is re-raised untouched. `2` is a real threshold breach; `3`
means the scan never ran. An unrecognised code is passed through rather than
guessed at.

The annotation's tail is event-aware: the comment steps only run on
`pull_request`, so on any other trigger it points at the job log rather than at
a PR comment that does not exist. `GITHUB_EVENT_NAME` is read straight from the
runner environment — `action.yml` does not thread it.

The step reads the script path out of `GITHUB_ACTION_PATH` and normalises the
separators rather than interpolating `github.action_path` into the script body:
on Windows that path contains backslashes, which bash would eat as escapes.

## The env contract

Scripts never share state directly. Everything that crosses a step boundary
does so as an environment variable, a `$GITHUB_ENV` line, or a `$GITHUB_OUTPUT`
line. Each script's header comment lists what it requires. The cross-step
values are:

| Value | Channel | Set by | Consumed by |
|---|---|---|---|
| extraction dir | `$GITHUB_PATH` | install | scan, delta — puts `skill-detector` on `PATH` |
| `SCAN_ACTION_DETECTOR_DIR` | `$GITHUB_ENV` | install | nothing; recorded for debugging |
| `scan-json-path` | step output | scan | delta (`INPUT_HEAD_SCAN_JSON`), render (`INPUT_SCAN_JSON`), telemetry (`INPUT_SCAN_JSON`), and callers |
| `grade`, `findings-count`, `no-agent-surface` | step outputs | scan | propagate-exit (`INPUT_GRADE`, `INPUT_FINDINGS_COUNT`, `INPUT_NO_AGENT_SURFACE`), and callers |
| `SCAN_EXIT_CODE` | `$GITHUB_ENV` | scan | propagate-exit, read straight from the environment |
| `SCAN_ACTION_DELTA_JSON` | `$GITHUB_ENV` | delta | render (`INPUT_DELTA_JSON`) |
| `delta-json-path` | step output | delta | nothing; `action.yml` uses the `$GITHUB_ENV` value instead |
| `$RUNNER_TEMP/comment.md` | a file at a conventional path | render | report |

Two details this table hides:

- **The Windows branches use different step IDs.** POSIX steps read
  `steps.scan.outputs.*`; Windows steps read `steps.scan-win.outputs.*`. Two
  IDs for the same logical step. `action.yml`'s outputs and the propagate-exit
  step bridge them with `a || b`. `SCAN_ACTION_DELTA_JSON` needs no bridging,
  because it travels through `$GITHUB_ENV` rather than a step output.
- **The rendered comment is the one handoff that is not a variable.** Both
  halves of render and report independently compute `$RUNNER_TEMP/comment.md`.
  The path is a convention shared by four scripts, so changing it means
  changing all four.

## Inputs and outputs

Inputs: `path`, `fail-on`, `fail-on-axis`, `strict-mcp`, `scan-all`,
`comment`, `warn-on-below-threshold`, `fail-on-no-agent-surface`, `delta`,
`telemetry`, `github-token`, `detector-version`.

Outputs: `grade`, `scan-json-path`, `findings-count`, `no-agent-surface`.

These names are the **public API**. `README.md` documents them and Marketplace
users depend on them; renaming or removing one is a breaking change requiring
a `v2`.

### The gate defaults

`fail-on: critical` and `warn-on-below-threshold: 'true'`. Together they mean
that in a build nobody configured, only a CRITICAL finding fails. Everything
below that is reported — in the job log as a `::warning::` annotation, and on a
pull request in the sticky comment — and the job stays green.

Each default is written in three places that must agree:

| Default | Places |
|---|---|
| `fail-on` | `action.yml`, and the `FAIL_ON` fallback in each half of `scan.{sh,ps1}` |
| `warn-on-below-threshold` | `action.yml`, and the `INPUT_WARN_ON_BELOW_THRESHOLD` fallback in `propagate-exit.sh` |

`action.yml` is the source of truth; the script fallbacks exist only for a
direct invocation with no env. `tests/bats/gate-defaults.bats` reads
`action.yml` and pins them together so they cannot drift — including the
PowerShell half, which it checks as text, because bats cannot execute pwsh.

## The engine's exit codes

The Action does not define these; it consumes them.

| Code | Meaning |
|---|---|
| `0` | No findings |
| `1` | Findings, all below the `--fail-on` / `--fail-on-axis` threshold |
| `2` | A finding at or above the threshold |
| `3` | Tool error — the scan did not run |

## Telemetry payload

Ten fields, none identifying: `action_version`, `detector_version`,
`runner_os`, `runner_arch`, `repo_visibility`, `repo_hash`, `grade`,
`finding_count`, `trigger`, `delta_enabled`. `repo_hash` is a SHA-256 of the
repository URL, not a name. No paths, no finding contents, no branch, no commit,
no token. Opt out with `telemetry: false`.

`action_version` is a literal in `action.yml`'s telemetry steps, not derived
from the tag, so it has to be moved by hand at release time.

## Testing

`tests/bats/` — nine suites driven by fakes in `tests/bats/fixtures/`
(`fake-detector.sh`, `fake-gh.sh`), so they never reach the network or GitHub.
Run with `./scripts/run-tests.sh`, which clones a pinned `bats-core` into
`.bats-tmp/` on first use.

`tests/e2e/gate-defaults.sh` — bash-only, and deliberately **not** run by
`run-tests.sh`. It exercises the gate defaults against the **real** engine and
the real fixtures under `tests/fixtures/`, which bats structurally cannot do:
bats runs against a fake detector, so it cannot prove that a given fixture
yields a finding of a given severity. It reads the thresholds out of
`action.yml`, so a changed default fails it and not only a changed script, and
it aborts unless the `skill-detector` on `PATH` matches the pinned
`detector-version`.

`tests/pwsh/` — PowerShell-side harnesses. Each picks its runtime at startup —
`pwsh` on `PATH` if present, otherwise a PowerShell container — and prints
which it chose.

- `parse-all-ps1.sh` → `parse-all-ps1.ps1` parses every `scripts/*.ps1`. Files
  are discovered by glob, never listed; a parse error **and** a zero match both
  fail.
- `exec-delta-ps1.sh` executes `delta.ps1` for real against a fake
  `skill-detector` and a fake `git`, asserting the recorded argument list. Its
  scratch path deliberately contains a space — that is what catches wrong
  native argument splitting — and the harness refuses to run if the space is
  ever lost.

`.github/workflows/ci.yml` has nine jobs: `bats`, `pwsh-parse`,
`pwsh-exec-delta`, `e2e-gate-defaults`, and five smoke jobs that run the real
Action on real runners — `smoke-clean`, `smoke-malicious`,
`smoke-pr-comment`, `smoke-pr-delta` and `smoke-pr-comment-windows`.

Two things about the smoke jobs are load-bearing:

- `smoke-malicious` asserts the Action **fails**. That is the check that
  exit-code propagation still works; a job that only asserted success would
  pass with step 7 deleted.
- The three comment jobs form a deliberate chain. They drive the same sticky
  marker, so running two concurrently would make "exactly one marker comment
  exists" a coin flip. Adding a fourth means extending the chain, not forking
  it.

The bats suites cover logic. The smoke jobs cover what bats cannot: that the
composite wiring, the env contract and the real runners agree.

## Release

Pushing a `v1.*` tag triggers `.github/workflows/release.yml`, which
force-moves the floating `v1` tag to that commit. Consumers pinning
`@v1` get the move without editing their workflow; the immutable `v1.x.y` tags
stay for anyone pinning exactly.
