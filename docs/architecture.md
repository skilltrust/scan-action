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
| 4 | Render report | any validated completed scan | `render-comment.{sh,ps1}` + shared `render.py` |
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

Resolves the release asset for `detector-version`, downloads it together with
the release's `checksums.txt` from the engine's GitHub releases, verifies the
asset's unique SHA-256 entry before extracting, verifies the installed binary
reports that exact version, then appends the extraction directory to
`$GITHUB_PATH` so later steps find `skill-detector` on `PATH`.

The two halves resolve the asset differently, because each already knows its
own platform:

| | `install.sh` | `install.ps1` |
|---|---|---|
| OS | maps `RUNNER_OS`: `Linux`→`linux`, `macOS`→`darwin`; throws on anything else | hardcodes `windows` — it only runs on Windows |
| Arch | maps `RUNNER_ARCH`: `X64`→`amd64`, `ARM64`→`arm64`; throws on anything else | the same mapping, and the same refusal |
| Asset | `skill-detector_<version>_<os>_<arch>.tar.gz` | `skill-detector_<version>_windows_<arch>.zip` |
| Verify | extracts exactly one asset checksum and compares `sha256sum`/`shasum` output | `Get-FileHash -Algorithm SHA256`, compared against the line for this asset; throws if the asset is absent from `checksums.txt` |
| Extract | `tar -xzf` | `Expand-Archive` |

Both execute the extracted binary's `version` command, require the requested
version, write the extraction directory to `$GITHUB_PATH`, and record it in
`SCAN_ACTION_DETECTOR_DIR`. The asset name embeds the version without its
leading `v`, on both sides.

### Step 2 — scan

Builds the engine's argument list from the inputs — always
`scan <path> --format json --fail-on <fail-on>`, plus one `--fail-on-axis`
argument per comma-separated spec, plus `--strict-mcp` and `--scan-all` when
those inputs are `'true'` — and writes the result to `$RUNNER_TEMP/scan.json`.

The engine's exit code is captured before parsing. Exits `0`/`1`/`2` require a
valid result: a findings array and either all four graded axes or the explicit
no-agent-surface shape. Every finding must be an object with the typed v0.10.0
fields consumed by reporting; additional fields remain allowed. Exit/result
disagreement is invalid. Valid raw JSON is not rewritten. Tool/nonstandard
exits and invalid results publish no public success-shaped outputs and remain
deferred failures.

`grade` is the raw `.axes.quality.grade`; `findings-count` is the validated
array length. No-agent-surface publishes an empty grade.

### Step 3 — delta

Fetches the base ref at depth 1, resolves `FETCH_HEAD`, adds a detached
worktree for that exact commit, and scans the matching `path`, `strict-mcp`,
and `scan-all` scope. Severity and axis thresholds remain head policy only.
Base exits `0`/`1`/`2` are accepted only with valid JSON. Delta is published
only after schema validation; stale values are cleared first. Any comparison
failure warns and leaves the head JSON and gate unchanged. Cleanup always runs.

### Steps 4 and 5 — render and post

Both OS wrappers invoke one `render.py`. It writes the marker-first
`$RUNNER_TEMP/comment.md` and appends the same safe body to
`$GITHUB_STEP_SUMMARY`; only fixed link attribution differs. Summary runs for
every validated scan on every trigger regardless of comment configuration,
token, fork, or App. Untrusted fields are flattened, escaped and bounded. Head findings use
effective severity CRITICAL→INFO plus deterministic rule/path/line/index
tie-breaks within new/existing groups, with new first and a shared cap of ten.
Fixed findings have a separate ten-item cap. The policy line mirrors final
exit handling; delta never gates. Grades follow the findings.

For available PR delta, the renderer subtracts `new_findings` as a multiset
from head findings. Identity uses the source fields of detector v0.10.0's
`pkg/delta.findingKey`: rule ID, file path, line, description (the detector
hashes description with FNV-1a). It does not recompute the diff or line-shift
pairing; those already happened in the detector. Remaining head occurrences
are existing. An unmatched new occurrence, malformed delta finding, or fixed
hard identity still present in head makes comparison unavailable.
Only Security, Permission hygiene, and Transparency
are public; raw Quality stays an output. Rendering failure writes a controlled
visible fallback, warns, and exits zero so it cannot replace scan policy.

`report` makes one paginated comment lookup and validates every page and
comment locally, including string bodies and numeric IDs. Lookup or schema
failure warns and exits without POST/PATCH, preventing duplicates. A marker
match is PATCHed; no match is POSTed. All API/native failures warn and preserve Summary
and policy. Before API access, head and base repository identities are compared:
a mismatch gets no token or Action comment and its inertly prefixed log copy is
App-delivery-only. If the App marker exists, the Action replaces its own old
comment with the controlled superseded note and yields.

### Step 6 — telemetry

POSTs a JSON heartbeat and cannot fail the build: `set +e` at the top,
`curl … || true`, `exit 0` at the bottom, and a hard `--max-time`. It exits 0
immediately if the scan JSON is missing.

### Step 7 — propagate exit

Requires and re-raises `SCAN_EXIT_CODE`, with these policy exceptions:

1. **No agent surface.** If the code is `0` and `no-agent-surface` is `true`,
   emits a `::warning::` saying nothing was checked, then exits `2` if
   `fail-on-no-agent-surface` is `'true'` and `0` otherwise. Guarded on code
   `0`: a breach (`2`) or a tool error (`3`) must never be reinterpreted as
   "nothing was checked".
2. **Report-only.** If enabled, validated finding exits `1` and `2` warn and
   succeed. Operational and unknown exits remain failures.
3. **Below threshold.** If the code is `1` and `warn-on-below-threshold` is
   `'true'` (the default), emits a `::warning::` naming the finding count and
   grade, and exits `0`.

Anything else is re-raised untouched. `2` is a real threshold breach; `3`
means the scan never ran. An unrecognised code is passed through rather than
guessed at. The composite marks this step `if: always()`, so an unexpected
earlier step outcome cannot skip the final policy decision.

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
| `scan-json-path` | step output | validated scan | delta (`INPUT_HEAD_SCAN_JSON`), render (`INPUT_SCAN_JSON`), telemetry (`INPUT_SCAN_JSON`), and callers |
| `grade`, `findings-count`, `no-agent-surface` | step outputs | scan | propagate-exit (`INPUT_GRADE`, `INPUT_FINDINGS_COUNT`, `INPUT_NO_AGENT_SURFACE`), and callers |
| `SCAN_EXIT_CODE` | `$GITHUB_ENV` | scan | propagate-exit, read straight from the environment |
| `SCAN_ACTION_DELTA_JSON` | `$GITHUB_ENV` | delta | render (`INPUT_DELTA_JSON`) |
| `delta-json-path` | step output | delta | nothing; `action.yml` uses the `$GITHUB_ENV` value instead |
| `$RUNNER_TEMP/comment.md` | a file at a conventional path | render | report |
| `$GITHUB_STEP_SUMMARY` | runner file | render | GitHub Job Summary |

Two details this table hides:

- **The Windows branches use different step IDs.** POSIX steps read
  `steps.scan.outputs.*`; Windows steps read `steps.scan-win.outputs.*`. Two
  IDs for the same logical step. All four Action outputs and propagate-exit
  bridge them with `a || b`. Invalid branches publish no success values.
  `SCAN_ACTION_DELTA_JSON` needs no bridging,
  because it travels through `$GITHUB_ENV` rather than a step output.
- **The rendered comment is the one handoff that is not a variable.** Both
  halves of render and report independently compute `$RUNNER_TEMP/comment.md`.
  The path is a convention shared by four scripts, so changing it means
  changing all four.

## Inputs and outputs

Inputs: `path`, `fail-on`, `fail-on-axis`, `strict-mcp`, `scan-all`,
`comment`, `warn-on-below-threshold`, `fail-on-no-agent-surface`, `delta`,
`report-only`, `telemetry`, `github-token`, `detector-version`.

Outputs: `grade`, `scan-json-path`, `findings-count`, `no-agent-surface`.

These names are the **public API**. `README.md` documents them and Marketplace
users depend on them; renaming or removing one is a breaking change requiring
a `v2`.

### The gate defaults

`fail-on: critical` and `warn-on-below-threshold: 'true'`. Together they mean
that in a build nobody configured, only a CRITICAL finding fails. Everything
below that is reported — in the job log as a `::warning::` annotation, and on a
pull request in the sticky comment — and the job stays green.

Between them the two defaults are written across three files that must agree —
`action.yml`, `scan.{sh,ps1}` and `propagate-exit.sh`:

| Default | Where it is written |
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

Ten fields, with no raw repository contents: `action_version`,
`detector_version`, `runner_os`, `runner_arch`, `repo_visibility`, `repo_hash`,
`grade`, `finding_count`, `trigger`, `delta_enabled`. `repo_hash` is a stable
pseudonymous SHA-256 of the repository URL, not a name. No paths, finding
contents, branch, commit, or token. Opt out with `telemetry: false`.

`action_version` is a literal in `action.yml`'s telemetry steps, not derived
from the tag, so it has to be moved by hand at release time.

## Testing

`tests/bats/` — suites driven by fakes in `tests/bats/fixtures/`
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
`detector-version` — otherwise a mismatched engine would give a confident wrong
answer. Setting `SKILL_DETECTOR_VERSION_CHECK=off` skips that check and is the
escape hatch for a local source build, which carries the pinned ruleset but
reports a development version string rather than the release tag. It is not
meant for CI, and the harness says so loudly when it is set.

`tests/pwsh/` — native PowerShell-side parse and execution harnesses. They
require `pwsh` on `PATH` and return skip code 77 when it is unavailable.

- `parse-all-ps1.sh` → `parse-all-ps1.ps1` parses every `scripts/*.ps1`. Files
  are discovered by glob, never listed; a parse error **and** a zero match both
  fail.
- `exec-delta-ps1.sh` executes `delta.ps1` for real against a fake
  `skill-detector` and a fake `git`, asserting the recorded argument list. Its
  scratch path deliberately contains a space — that is what catches wrong
  native argument splitting — and the harness refuses to run if the space is
  ever lost.
- `exec-scan-ps1.sh` executes clean, findings, no-surface, tool-error,
  malformed-result and repeated scan cases. It checks difficult native paths,
  exact raw JSON bytes, deferred exits and all public step outputs.
- `exec-reporting-ps1.sh` executes the shared renderer and PowerShell delivery
  path, including sticky update and inert fork logging.
- `exec-install-ps1.sh` verifies both Windows architecture assets, checksums,
  version matching, and adverse download/archive cases with local fixtures.
- `exec-telemetry-ps1.sh` captures the exact ten fields locally and covers
  malformed input and request timeout without network access.

`.github/workflows/ci.yml` adds a deterministic composite policy matrix, a
Linux composite-equivalent harness, and a real `uses: ./` Linux/macOS/Windows
output matrix to the existing Bats, PowerShell, real-engine, and PR-comment
smoke jobs.

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
