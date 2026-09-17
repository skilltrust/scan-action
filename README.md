# skilltrust/scan-action

Free CI scanning for AI-agent configuration. The Action downloads the pinned
`skill-detector`, scans the checkout on the GitHub runner, writes every
valid completed scan to Job Summary, and can maintain one PR comment.

The public report shows Security, Permission hygiene, and Transparency.
`grade` remains the detector's raw Quality-axis output for compatibility.

## Quickstart: report only

Copy `.github/workflows/skilltrust.yml`:

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
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - id: skilltrust
        uses: skilltrust/scan-action@v1
        with:
          report-only: 'true'
          delta: 'true'
```

This configuration is **report-only: true; blocking: false for findings**.
Findings still appear. Install, integrity, invalid input, tool, and invalid
result failures still fail: report-only is not error suppression.

`pull-requests: write` is only for same-repository PR comments. Set
`comment: 'false'` and remove that permission if Job Summary is enough.

## Keep the complete JSON as an artifact

The Action never uploads scan results to SkillTrust. Raw JSON remains on the
runner at `scan-json-path`. Optional GitHub artifact retrieval:

```yaml
- id: skilltrust
  uses: skilltrust/scan-action@v1
  with:
    report-only: 'true'
    comment: 'false'
- if: always() && steps.skilltrust.outputs.scan-json-path != ''
  uses: actions/upload-artifact@v4
  with:
    name: skilltrust-scan-json
    path: ${{ steps.skilltrust.outputs.scan-json-path }}
```

Artifact retention and access then follow the repository's GitHub settings.

## Requirements

- A checkout must exist before the Action runs.
- `fetch-depth: 0` is required for reliable PR delta comparison.
- Supported runners: GitHub-hosted Linux, macOS, and Windows. Self-hosted
  runners need the standard runner tools, Python 3, and GitHub CLI for comments.
- Use `pull_request`, not `pull_request_target`. Never expose writable tokens or
  secrets to untrusted fork code.

## Inputs

| Input | Default | Contract |
|---|---|---|
| `path` | `.` | Checkout-relative scan scope. |
| `fail-on` | `critical` | Effective severity threshold: `critical`, `high`, `medium`, `low`, or `info`. |
| `fail-on-axis` | empty | Comma-separated grade gates, e.g. `security=C,permission_hygiene=C`. Equal passes; a strictly worse grade fails. |
| `strict-mcp` | `false` | Raise the MCP external-domain rule from MEDIUM to HIGH. |
| `scan-all` | `false` | Ignore `.gitignore` and scope tightening; hard skips still apply. |
| `comment` | `true` | Maintain one sticky same-repository PR comment. Summary is independent. |
| `warn-on-below-threshold` | `true` | Finding exit `1` warns instead of failing. |
| `fail-on-no-agent-surface` | `false` | Gate when nothing supported was checked. |
| `report-only` | `false` | Convert validated finding exits `1`/`2` to success. Operational failures remain failures. |
| `delta` | `false` | Compare PR head with base. Doubles scan runtime. |
| `telemetry` | `true` | Send the anonymous ten-field heartbeat below. |
| `github-token` | `${{ github.token }}` | Same-repository PR comment token. Not passed to fork delivery. |
| `detector-version` | `v0.10.0` | Exact detector release installed after checksum and reported-version verification. |

## Outputs

| Output | Contract |
|---|---|
| `grade` | Raw Quality-axis `A`/`B`/`C`/`D`/`F`; empty on no surface/failure. |
| `scan-json-path` | Absolute path to validated, unmodified, complete JSON; empty on failure. |
| `findings-count` | Total head finding count. |
| `no-agent-surface` | `true` when no supported agent file was checked and no grade exists. |

Job Summary and sticky PR comments lead with the current issue count, Action check
status, and next step. Grades and scan details follow the findings; a low
grade does not itself mean the job fails. “SkillTrust check will fail” describes
the Action policy, not branch protection. Only a required check blocks merging.
Current counts exclude fixed findings, which are counted separately.

Reports show at most ten head findings (new first, then existing), ordered
within each group by effective severity CRITICAL → INFO with a stable
tie-break, plus at most ten fixed findings. The JSON output is never truncated.

## Policy and delta

Detector exits are deferred until reporting completes:

| Exit | Meaning | Default | `report-only: 'true'` |
|---|---|---|---|
| `0` | Clean, or explicit no-agent-surface | pass; no surface warns | pass; no surface policy remains independent |
| `1` | Findings below configured gates | warn + pass | warn + pass |
| `2` | Severity/axis threshold reached | fail | warn + pass |
| `3` | Tool/input/result error | fail | fail |

An unknown nonzero exit remains nonzero. `fail-on-no-agent-surface: 'true'`
still gates under report-only.

The whole validated **head** result gates. `delta: 'true'` adds a base
comparison for PR presentation only. Fetch, worktree, base scan, or delta
failure is reported as **comparison unavailable**, never as zero change, and
never replaces the head policy or JSON.

With an available PR comparison, reports distinguish:

- **New in this PR:** detector delta's new findings, expanded first.
- **Already on base:** current head findings not counted as new, collapsed.
  The disclosure includes CRITICAL/HIGH counts even when details are truncated;
  these are effective severities, not claims about which findings triggered policy.
- **Fixed by this PR:** findings present on the current base but absent from
  the current head; locations refer to base. This can include removed files.

There is no memory of earlier runs. A finding introduced and removed within
the same PR is absent, not “fixed”. With delta off or unavailable, reports
show **current findings** without claiming new/existing/fixed status.

## What is scanned

Detector `v0.10.0` recognizes:

- skill roots (`SKILL.md`, `skill.yaml`) and their subtrees;
- `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.cursorrules`,
  `.cursor/rules/*.mdc`, `.github/copilot-instructions.md`, `.windsurfrules`;
- agent directories such as `.claude/`, `.agents/`, `.codex/`, `.opencode/`,
  `.cursor/`, `.gemini/`, `.windsurf/`;
- supported MCP/settings files, including `.mcp.json` and harness MCP paths.

Default discovery honors the root `.gitignore`. `scan-all: 'true'` disables
that filtering and broadens to known text/script extensions. It does **not**
override hard skips: `.git`, `node_modules`, `vendor`, `dist`, `build`,
`target`, and `.next` are never scanned.

Content rules work across supported harness instruction files. Harness-specific
structural parsing is not universal: v0.10.0 structurally understands Claude
settings/hooks/MCP, while Codex, OpenCode, Gemini, Cursor, Copilot, and Windsurf
formats have partial file/content coverage. This is a supported boundary, not a
claim that every harness setting or source file was reviewed.

No-agent-surface means no recognized file was checked. It has no grades and is
not rendered as clean.

## Comments, forks, and the GitHub App

The Action marker is the first comment line and repeated runs PATCH the same
comment. Lookup is paginated. If lookup fails, the Action warns and never risks
a duplicate POST. Comment API failures do not replace Job Summary or scan
policy.

A fork is detected by comparing head and base repository identity. The Action
does not pass its token or post a comment for a fork; it emits an inert log copy
and leaves PR delivery to an installed GitHub App. GitHub withholds normal
workflow secrets on fork PRs. Do not work around this with
`pull_request_target`.

If the SkillTrust App marker already exists, the Action yields its comment
surface while still scanning, summarizing, and enforcing the configured policy.

## Data flow and privacy

- Public and private repositories use the same runner-local scan path. Forks
  use the restricted delivery path above.
- **Runner-local:** checkout contents, findings, grades, and complete JSON.
- **Downloads:** the pinned detector archive and checksum come from its GitHub
  release; no `latest` detector lookup is used.
- **GitHub:** Job Summary always receives the bounded report for completed
  valid scans on any workflow trigger. If enabled and writable, the same
  bounded report becomes a PR comment. Optional artifact upload is explicitly
  user-configured.
- **SkillTrust:** no raw result, path, finding detail, repository name, branch,
  commit, user, or token is uploaded. The default heartbeat sends only the ten
  fields below, including aggregate grade/count and a stable repository hash.

Report links have fixed destinations and UTM values only. They contain no
repository or result data. Clicking a link is an ordinary browser navigation,
so the browser/site may receive the standard HTTP referrer allowed by browser
and GitHub policy.

### Default-on telemetry

Once per validated run, the Action sends exactly these ten fields to
`https://skilltrust.app/api/telemetry/action-run`:

```json
{
  "action_version": "1.11.0",
  "detector_version": "v0.10.0",
  "runner_os": "Linux",
  "runner_arch": "X64",
  "repo_visibility": "public",
  "repo_hash": "<sha256(GITHUB_SERVER_URL + '/' + GITHUB_REPOSITORY)>",
  "grade": "B",
  "finding_count": 4,
  "trigger": "pull_request",
  "delta_enabled": false
}
```

`repo_hash` is a stable pseudonymous identifier for the same GitHub repository;
it is not the repository name. Telemetry is time-limited and can never fail
the build.

**Opt out explicitly:**

```yaml
- uses: skilltrust/scan-action@v1
  with:
    report-only: 'true'
    telemetry: 'false'
```

## Pinning

`skilltrust/scan-action@v1` follows compatible v1 releases. For immutable
supply-chain pinning, use a reviewed full commit SHA. `detector-version` is
already exact (`v0.10.0`); its archive checksum and installed binary's reported
version are verified before use.

## License

MIT. See `LICENSE`.
