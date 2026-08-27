# skilltrust/scan-action

The free tier of [SkillTrust](https://skilltrust.app/ci?src=action) — agent-configuration
security, gated in your own CI. Scans `SKILL.md`, `CLAUDE.md`, `AGENTS.md`,
`.claude/`, `.mcp.json`, `.codex/`, `.opencode/` and the rest of the
agent-config surface for prompt injection, credential access, supply-chain and
permission problems, then posts a sticky pull-request comment with a four-axis
trust score and fails the build on CRITICAL findings by default — and on
whatever thresholds you set.

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

Out of the box the build fails only on a **CRITICAL** finding. Everything
below that is reported and does not block the merge — see
**What fails your build** for why, and for how to tighten it.

## Inputs

| Input | Default | Description |
|---|---|---|
| `path` | `.` | Path to scan |
| `fail-on` | `critical` | Severity threshold: `critical`/`high`/`medium`/`low`/`info`. See **What fails your build**. |
| `fail-on-axis` | `''` | Per-axis grades, e.g. `permission_hygiene=C,security=C` |
| `strict-mcp` | `false` | Raise MCP external-domain rule severity from medium to high |
| `scan-all` | `false` | Disable scope tightening and `.gitignore` filtering |
| `delta` | `false` | Compute delta vs base branch (PR triggers only). Doubles runtime. |
| `comment` | `true` | Post sticky PR comment |
| `warn-on-below-threshold` | `true` | Turn exit `1` (findings, all below threshold) into a warning annotation instead of a build failure. See **Exit codes**. |
| `fail-on-no-agent-surface` | `false` | Fail the build when the scan found no agent configuration files at all (default = warn only). See **When nothing was checked**. |
| `detector-version` | `v0.8.0` | Pin a specific `skill-detector` release |
| `telemetry` | `true` | Send anonymous install heartbeat. See **Telemetry** below. |
| `github-token` | `${{ github.token }}` | Token used to post PR comments |

## Outputs

| Output | Description |
|---|---|
| `grade` | Overall trust grade (worst axis): `A`/`B`/`C`/`D`/`F` |
| `scan-json-path` | Absolute path to scan result JSON in the runner |
| `findings-count` | Total finding count |
| `no-agent-surface` | `true` when the scan found no agent configuration files — no grade was produced |

## What fails your build

By default, only a **CRITICAL** finding does. HIGH, MEDIUM, LOW and INFO
findings are reported — in the sticky PR comment and as a `::warning::`
annotation — and the job stays green.

That default is a measurement, not a preference. On engine `v0.8.0`, against
300 benign samples from the MalSkillBench corpus in the raw layout a
repository scan actually sees:

| `fail-on` | Benign repos failed, of 300 | Malicious caught, of 300 | Precision | FPR |
|---|---|---|---|---|
| `high` (the default before v1.7.0) | 111 | 198 | 0.641 | **0.370** |
| `medium` | 124 | 219 | 0.638 | 0.413 |
| `critical` (**the default**) | 20 | 70 | 0.778 | **0.067** |

The benign pool is ClawHub's most-downloaded skills, so those are close to
what an ordinary repository contains. At `fail-on: high` one clean repository
in under three reds its build on the first run — and a gate that is wrong one
time in three gets switched off in week one, which costs more than the findings it
would have caught. The gate is not the only layer: the comment still shows
everything.

Want the stricter posture? Ask for it explicitly, and you know what you signed
up for:

```yaml
- uses: skilltrust/scan-action@v1
  with:
    fail-on: high
    warn-on-below-threshold: false
```

Recall at `critical` is genuinely lower (0.150 against 0.453). The trade is
deliberate: a missed finding is still visible in the comment, while a false
build failure is not recoverable once the team has decided the tool is noise.

## Exit codes

The final step re-raises the scanner's exit code (`SCAN_EXIT_CODE`), so the
job's pass/fail comes straight from `skill-detector`:

| Code | Meaning | Default (`warn-on-below-threshold: true`) | With `warn-on-below-threshold: false` |
|---|---|---|---|
| `0` | No findings | pass | pass |
| `1` | Findings, all below your `fail-on` / `fail-on-axis` threshold | pass, with a `::warning::` annotation | **fail** |
| `2` | Finding at or above threshold (worst of severity OR axis-grade) | **fail** | **fail** |
| `3` | Tool error (bad arguments, unreadable path, internal failure) | **fail** | **fail** |

### Below-threshold findings warn, they do not fail

The engine means exit `1` as "look, but I am not blocking you". Until v1.7.0
the action re-raised it anyway, so with `fail-on: high` a single MEDIUM
finding reddened the build exactly like a breach. Since v1.7.0
`warn-on-below-threshold` defaults to `true` and it does not.

The finding still appears in the job log as a warning annotation, and on
pull-request runs, in the sticky PR comment too; only the build result
changes. If you want the old behaviour back:

```yaml
- uses: skilltrust/scan-action@v1
  with:
    warn-on-below-threshold: false
```

Raising `fail-on` would hide the finding instead — this keeps it visible.

`2` and `3` are never downgraded, whatever the input is set to. `2` is a real
threshold breach. `3` means the scan did not run at all, and a scan that could
not run is not a passing scan — which is also why you should not reach for
`continue-on-error` or `|| true` to get warn-not-fail behavior.

### When nothing was checked

If the detector finds no `SKILL.md`, `CLAUDE.md`, `AGENTS.md`, `.claude/`,
`.agents/` or `.mcp.json` in the scanned path, there is nothing to grade —
`no-agent-surface` is `true`, the sticky PR comment says so instead of
showing a trust score, and the build **passes by default** with a
`::warning::` annotation. A repository that genuinely has no agent config
would otherwise go red permanently with no fix available, and a permanent
red gets deleted — so the default is to withdraw the claim loudly rather than
assert a false pass or a false fail.

Set `fail-on-no-agent-surface: true` if an empty agent surface should gate
your build (exit `2`):

```yaml
- uses: skilltrust/scan-action@v1
  with:
    fail-on-no-agent-surface: true
```

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
  "action_version":   "1.8.0",
  "detector_version": "v0.8.0",
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
