# skilltrust/scan-action

GitHub Action that scans AI-agent configuration files (`SKILL.md`, `CLAUDE.md`, `.claude/`, `.mcp.json`, `.codex/`, `.opencode/`) for security threats using [skill-detector](https://github.com/velzepooz/skill-detector). Posts a sticky PR comment with a four-axis trust score and a build status driven by configurable thresholds.

## Quickstart

Add `.github/workflows/skilltrust.yml` to your repo:

```yaml
name: skilltrust
on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read
  pull-requests: write

jobs:
  skilltrust:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0   # required for delta vs base branch
      - uses: skilltrust/scan-action@v1
        with:
          delta: true
```

That's it. Open a PR; you'll get a sticky comment with the four-axis grade.

## Inputs

| Input | Default | Description |
|---|---|---|
| `path` | `.` | Path to scan |
| `fail-on` | `high` | Severity threshold: `critical`/`high`/`medium`/`low`/`info` |
| `fail-on-axis` | `''` | Per-axis grades, e.g. `permission_hygiene=C,security=C` |
| `strict-mcp` | `false` | Raise MCP external-domain rule severity from medium to high |
| `scan-all` | `false` | Disable scope tightening and `.gitignore` filtering |
| `delta` | `false` | Compute delta vs base branch (PR triggers only). Doubles runtime. |
| `comment` | `true` | Post sticky PR comment |
| `detector-version` | `v0.3.1` | Pin a specific `skill-detector` release |
| `telemetry` | `true` | Send anonymous install heartbeat. See **Telemetry** below. |
| `github-token` | `${{ github.token }}` | Token used to post PR comments |

## Outputs

| Output | Description |
|---|---|
| `grade` | Overall trust grade (worst axis): `A`/`B`/`C`/`D`/`F` |
| `scan-json-path` | Absolute path to scan result JSON in the runner |
| `findings-count` | Total finding count |

## Pinning

Recommended:

```yaml
- uses: skilltrust/scan-action@v1     # moves with minor/patch in v1.x
```

Supply-chain-strict:

```yaml
- uses: skilltrust/scan-action@<full-sha>
```

## Permissions

```yaml
permissions:
  contents: read         # checkout
  pull-requests: write   # post sticky comment
```

No `actions: write`, no `id-token: write`, no `packages: write`.

## Fork PRs

GitHub gives fork-origin PRs a read-only `GITHUB_TOKEN`, so the action cannot post a comment. The Action detects this and falls back to printing the comment markdown to the job log + emitting a `::warning::` annotation. Maintainers see the result in the job summary; the PR itself stays comment-free.

If you want comments on fork PRs, the `pull_request_target` event grants write tokens — at the documented cost of running against the base tree by default. We do not ship a `pull_request_target` workflow template because the safe pattern requires explicit checkout of `${{ github.event.pull_request.head.sha }}`, which reintroduces the supply-chain risk that `pull_request` exists to prevent.

## Telemetry

By default the Action sends a 1KB JSON heartbeat to `https://skilltrust.app/api/telemetry/action-run` once per run:

```json
{
  "action_version":   "1.0.0",
  "detector_version": "v0.3.1",
  "runner_os":        "Linux",
  "runner_arch":      "X64",
  "repo_visibility":  "public",
  "repo_hash":        "<sha256(GITHUB_SERVER_URL + GITHUB_REPOSITORY)>",
  "grade":            "B",
  "finding_count":    4,
  "trigger":          "pull_request",
  "delta_enabled":    false
}
```

No commit SHAs. No branch names. No file paths. No finding details. No tokens. Just a coarse heartbeat so we know the install count.

Opt out by setting `telemetry: false`.

## License

MIT. See `LICENSE`.
