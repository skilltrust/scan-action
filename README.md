# skilltrust/scan-action

The free tier of [SkillTrust](https://skilltrust.app/ci?src=action) — agent-configuration
security, gated in your own CI. Scans `SKILL.md`, `CLAUDE.md`, `AGENTS.md`,
`.claude/`, `.mcp.json`, `.codex/`, `.opencode/` and the rest of the
agent-config surface for prompt injection, credential access, supply-chain and
permission problems, then posts a sticky pull-request comment with a four-axis
trust score and fails the build on the thresholds you set.

Everything runs inside your runner. Nothing leaves it, on public and private
repositories alike, and that is permanent.

## This, or the GitHub App

| | This Action | [The GitHub App](https://skilltrust.app/ci?src=action) |
|---|---|---|
| Where it runs | your runner | our servers |
| Private repositories | free, always | 3 free per account, by design — not yet gated in production |
| Sticky PR comment | yes | yes |
| Remembers last week's result | no | yes |
| Badge and a public `/r/` page | no | yes |
| LLM triage on the noise | no | yes |

Running both is fine — the Action detects the App's comment and stays quiet
rather than posting a second one.

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
| `detector-version` | `v0.6.0` | Pin a specific `skill-detector` release |
| `telemetry` | `true` | Send anonymous install heartbeat. See **Telemetry** below. |
| `github-token` | `${{ github.token }}` | Token used to post PR comments |

## Outputs

| Output | Description |
|---|---|
| `grade` | Overall trust grade (worst axis): `A`/`B`/`C`/`D`/`F` |
| `scan-json-path` | Absolute path to scan result JSON in the runner |
| `findings-count` | Total finding count |

## Exit codes

The final step re-raises the scanner's exit code (`SCAN_EXIT_CODE`), so the
job's pass/fail comes straight from `skill-detector`:

| Code | Meaning |
|---|---|
| `0` | No findings |
| `1` | Findings, all below your `fail-on` / `fail-on-axis` threshold |
| `2` | Finding at or above threshold (worst of severity OR axis-grade) |
| `3` | Tool error (bad arguments, unreadable path, internal failure) |

`3` fails the job the same as `1`/`2` — the action does not distinguish a
scanner crash from a threshold breach. A tool error failing CI is correct: a
scan that could not run is not a passing scan.

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
  "action_version":   "1.2.0",
  "detector_version": "v0.5.0",
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
