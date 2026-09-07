# The other repositories

`scan-action` is one of three repositories. It is the only one that runs inside
a user's CI, and the only one of the three that contains no Go at all.

## The three repositories

| Repository | Role | Visibility |
|---|---|---|
| `skill-detector` | The detection engine. The file walk, the rules, the grading, and the CLI. Everything a scan concludes is decided there. | Public. |
| The hosted scanner, `skilltrust` | The web application at [skilltrust.app](https://skilltrust.app): the scan pages, the reports, the badge service and the GitHub App backend. Embeds the engine as a Go library. | Private. |
| `scan-action`, this repository | Wraps a scan so a repository can gate its pull requests on the result. Shell only. | Public. |

## This repository depends on the engine's CLI, not its library

**There is no Go code here, and nothing here imports the engine's `pkg/`.**
The install step downloads the released binary for the runner's platform —
the release named by `detector-version` in `action.yml` — invokes it, and reads
what comes back.

The dependency is therefore the **CLI surface**, and it breaks in ways no
compiler can catch. Three parts of it are load-bearing:

- **Flag names and semantics.** `scan.{sh,ps1}` builds `scan <path> --format json --fail-on <v>`, plus `--fail-on-axis`, `--strict-mcp` and `--scan-all`; `delta.{sh,ps1}` calls the `delta` sub-command with two JSON files. A renamed or removed flag, or one whose default moves, breaks this Action at runtime with no build failure anywhere.
- **Exit codes.** The Action turns the engine's exit code into the job's pass or fail. The `0` / `1` / `2` / `3` contract is what `propagate-exit.sh` implements, so it is load-bearing outside the engine's own repository.
- **The JSON output shape.** The scan, render and telemetry steps parse the result rather than embedding the engine's types. `.axes[].grade`, `.findings[]` with `severity`, `rule_id`, `axis`, `file_path`, `line` and `description`, `.no_agent_surface` and `.version` are all read by name. The delta JSON's `.per_axis`, `.axis_explanations` and `.resolved_findings` likewise.

The upside of not compiling against the engine is that this repository builds
and tests without it. The cost is that a breaking engine change shows up here
as a red smoke job or a wrong comment, not as a compile error — which is why
`tests/e2e/gate-defaults.sh` runs against the **real** engine at the pinned
version and refuses to run against any other.

## The engine pin is one of three, and none of them notices a release

`action.yml`'s `detector-version` default is one of three places that pin the
engine's version. The other two are in the hosted scanner: the version its
`go.mod` compiles against, and a separate pin used to clone the engine for CI
fixtures. **None of the three notices a new engine tag.**

Moving the pin here is necessary but not sufficient. A user pinning
`skilltrust/scan-action@v1` gets the engine version baked into whatever commit
`v1` points at, so the change reaches nobody until **this repository cuts its
own release** and the floating `v1` tag moves. An engine release that stops at
"the pin is updated on `main`" has not shipped to a single user of this Action.

Moving the pin is also a user-visible change on its own: a new engine version
can move a grade on a repository whose contents did not change. It belongs in
`CHANGELOG.md`, in the same pull request, with what moved.

An agent working only inside this repository cannot move the other two pins —
they live in a repository it cannot see. The correct ending is a handoff that
names them, not a claim that the engine release shipped.

## What this repository shares with the hosted scanner

Two contracts cross the boundary at runtime.

- **The comment markers.** This Action's sticky comment starts with
  `<!-- skilltrust:action:v1 -->`; the hosted scanner's GitHub App uses
  `<!-- skilltrust:bot:v1 -->`. Both strings appear in `report.{sh,ps1}`,
  because the Action looks for the App's marker in order to stand down when
  the App is already commenting on the pull request. Either string changing on
  either side breaks that arrangement silently — the two sides would simply
  stop seeing each other and post two comments.
- **The telemetry endpoint.** `telemetry.{sh,ps1}` POSTs its heartbeat to an
  ingest path on `skilltrust.app`. That endpoint is served by the hosted
  scanner, and the payload's field set is a shared shape. The coupling is
  deliberately weak in one direction only: the request is time-limited and its
  failure is swallowed, so the endpoint disappearing entirely cannot fail
  anyone's build.

Merging to the hosted scanner's default branch is a production deployment,
including a documentation-only merge. That is worth knowing from here mainly
because both contracts above have a live server on the other end.

## Coordination records

Records of how these repositories are coordinated — release history, downstream
state, and the reasoning behind the arrangement above — are kept privately by
the maintainer and are not part of this repository. If you need to know
something about another repository that this page does not answer, open an
issue.
