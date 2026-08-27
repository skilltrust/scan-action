# Changelog

## [1.8.0] — 2026-08-27

### The engine pin moves to `v0.8.0` — your grade may move with it

`detector-version` default: `v0.7.0` → `v0.8.0`.

**Any directory containing a `SKILL.md` is now a skill root, and its whole
subtree is scanned.** Before this, a payload sitting in `scripts/` beside a
manifest was never read in a repository checkout — only the manifest above it
was. That is the layout this Action actually sees, so the Action was the
surface losing most from it.

**A repository that graded A may now grade D.** That is the point of the
change, not a regression: the file was always there, the scanner just could
not see it. Nothing about your configuration changed.

`node_modules/`, `vendor/`, `dist/`, `build/`, `target/`, `.next/` and `.git/`
are still never scanned, and a `SKILL.md` inside them creates no scope root.
`.github/` and `.vscode/` are not pulled in wholesale either — only the
specific instruction and MCP files in them that were always in scope.

### The `fail-on: critical` default is re-measured, and it holds

The default was justified by a measurement, so widening the scope means
re-taking it. On engine `v0.8.0`, 300 benign and 300 malicious MalSkillBench
samples, raw layout:

| `fail-on` | Benign failed, of 300 | Malicious caught, of 300 | FPR |
|---|---|---|---|
| `medium` | 124 | 219 | 0.413 |
| `high` | 111 | 198 | 0.370 |
| `critical` (**the default**) | 20 | 70 | **0.067** |

Against `v0.7.0` the default now catches **70 malicious repositories instead
of 49**, for 20 benign failures instead of 13. One clean repository in fifteen
reds its build, against one in under three at `fail-on: high`. The default
stands, and it got materially more effective.

No input, output or behavior of the Action itself changed in this release.

## [1.7.0] — 2026-08-27

### Changed

**⚠️ Behaviour change for existing users: a build that fails today may pass
after upgrading.** `fail-on` now defaults to `critical` instead of `high`, and
`warn-on-below-threshold` now defaults to `true` instead of `false`. If your
workflow does not set those inputs, a HIGH finding that reddens your build on
`v1.6.0` becomes a `::warning::` annotation on `v1.7.0` and the job goes
green. Nothing is hidden — the finding still appears in the job log, and on
pull-request runs, in the sticky PR comment too.

**To keep the old behaviour, set both inputs explicitly:**

```yaml
- uses: skilltrust/scan-action@v1
  with:
    fail-on: high
    warn-on-below-threshold: false
```

**Why.** Measured on engine `v0.7.0` against 300 benign MalSkillBench samples
in the raw layout a repository scan actually sees, `fail-on: high` failed 75
of them — FPR 0.250, one clean repository in four — while `critical` failed
13, FPR 0.043. The benign pool is ClawHub's most-downloaded skills, so it is
approximately what an ordinary repository contains. A gate that is wrong one
time in four is switched off in week one, and that verdict is expensive to
reverse. Recall at `critical` is lower (0.150 against 0.453) and that trade is
deliberate: a missed finding is still in the comment, a false build failure
spends trust that does not come back.

No input or output was renamed or removed, so `@v1` keeps working — this is a
minor release, and consumers pinned to `@v1` receive it as soon as the tag
moves.

### Added

- `tests/fixtures/one-high-repo` and `tests/fixtures/critical-repo`, plus
  `tests/e2e/gate-defaults.sh` — the gate's behaviour under its defaults is
  now verified against the real engine in CI, not only against test fakes.

## [1.6.0] — 2026-08-26

**The engine pin moves to `v0.7.0`, and that is what makes this release
matter.** The `no-agent-surface` support below shipped in the previous commit
but was inert: `v0.6.0` never emits the field, so every branch added for it
was unreachable. From this release it is live.

### ⚠️ Detection results change for every consumer

`detector-version` goes `v0.6.0` → `v0.7.0`, a release carrying a
measurement-driven precision programme and a rework of the engine's
network-call demotion policy. Measured on a pinned 906-sample corpus at
`--fail-on-axis security=B`, malicious detection rises from 187/300 to
197/300 on an installed layout and from 113/300 to 127/300 on a raw one,
against three more benign flags per 300 on each.

**A build that passed on `v1.5.0` can fail on `v1.6.0` with no change to your
repository.** If it does, read the finding before pinning back — the engine
did not get noisier, it got better at the shapes it already looked for.

### ⚠️ A repository with no agent config now warns instead of passing silently

With the engine able to report it, the action stops rendering a trust score of
an em dash for a scan that examined nothing. It emits a `::warning::`
annotation and a PR comment headed `∅ SkillTrust — Nothing was checked`, and
still exits `0` by default. Set `fail-on-no-agent-surface: true` to make it
exit `2` instead.

If your workflow scans a path that has no agent configuration, this is the
release where you find out.

### Changed
- `detector-version` default: `v0.6.0` → `v0.7.0`.
- `INPUT_ACTION_VERSION` in the telemetry steps: `1.5.0` → `1.6.0`.

### Added
- **`no-agent-surface` output and `fail-on-no-agent-surface` input.** The
  engine can report that a scan read no agent-configuration files at all —
  nothing was checked, so there is no grade. Without this, the action
  rendered a trust score of em-dash, an axis table reading "no axes", and
  exited `0` — a green check on a repository where nothing was examined.

  The exit code is the machine-readable claim: with no grade asserted there
  is nothing to disbelieve, so the default stays `0` and the claim is
  withdrawn loudly instead — a `::warning::` annotation and a sticky PR
  comment headed "Nothing was checked" in place of the trust score. Set
  `fail-on-no-agent-surface: true` to turn it into exit `2` instead. Failing
  by default was rejected: a repository that genuinely has no agent files
  would go red permanently with no fix available, and a permanent red gets
  deleted.

  **Inert at the pinned detector version** (`v0.6.0`), which never emits the
  `no_agent_surface` field — every new branch activates only once the pin
  moves in a later release.


## [1.5.0] — 2026-08-17

### Added
- **`warn-on-below-threshold` input** (default `false`, so nothing changes for
  existing consumers). The engine distinguishes exit `1` — findings exist but
  all sit below your `fail-on` / `fail-on-axis` threshold — from exit `2`, a
  real breach. The action re-raised both identically, so with the default
  `fail-on: high` a single MEDIUM finding failed the build even though the
  README called that state "below your threshold". Set the input to `true` and
  exit `1` becomes a one-line `::warning::` annotation naming the finding count
  and grade, and the job passes. The finding still shows up in the sticky PR
  comment.

  **Exit `2` and exit `3` are never downgraded**, whatever the input says. `2`
  is a threshold breach; `3` is a tool error, which means the scan did not run,
  and a scan that could not run is not a passing scan. Unrecognized codes pass
  through unchanged rather than being mapped to anything.

### Changed
- The final `Propagate exit code` step moved out of an inline `run:` into
  `scripts/propagate-exit.sh` so the mapping is unit-tested (ten new bats
  cases: all four codes × the input on and off, plus unset and unknown-code
  passthrough). Behavior with the input left at its default is identical to
  v1.4.1. The script is deliberately bash-only — the step runs under `bash` on
  every OS, Git Bash included, so ADR-0002's script-pair rule does not apply.

### Internal
- `render-comment.ps1` and `report.ps1` now **execute** in CI, not just parse.
  A new `smoke-pr-comment-windows` job runs the action on `windows-latest` with
  `comment: 'true'`, chained behind `smoke-pr-delta` so the sticky marker is
  never driven concurrently, and asserts the comment it ends up with was
  rewritten by that run. Every `.ps1` half now has execution coverage.

## v1.4.1 — 2026-08-17

### Fixed
- **Delta PRs no longer show phantom axis drops or phantom new findings.**
  `delta.sh`/`delta.ps1` now scan the base branch with the same
  `strict-mcp`/`scan-all` inputs used for the head scan. Previously the base
  scan ignored both, so with `strict-mcp: true` an external MCP domain that
  hadn't changed could show up as a brand-new `permission_hygiene` grade
  drop, and with `scan-all: true` every finding in a path-gated file could
  read as newly introduced on a PR that never touched it.

## v1.4.0 — 2026-08-17

### Added
- The sticky PR comment's footer now links to
  `skilltrust.app/ci?src=action`, the funnel page for the hosted App.

### Changed
- **The Action yields to the SkillTrust GitHub App.** If a PR already carries
  the App's comment (its own sticky marker), `report.sh`/`report.ps1` no
  longer post a second, competing grade: a fresh run stays quiet, and a run
  that had already posted its own comment replaces it with a short
  "superseded" note pointing at the App's comment instead. Running both the
  Action and the App on the same repository is now safe by design, not by
  accident.
- **README repositioned:** the Action is now introduced as the free,
  runner-local tier of SkillTrust, with a comparison table against the
  hosted GitHub App, rather than as a standalone wrapper around
  `skill-detector`. No input, output or scanning behavior changed.

### Fixed
- **`scripts/report.ps1` never parsed.** In a PowerShell double-quoted string
  `\` is not an escape character and `""` is an escaped quote, so the
  `--jq "…startswith(\""+$marker+"\"")…"` pattern closed the string early and
  the file failed to parse before any line ran. Every Windows runner using
  `@v1` with `comment: true` therefore failed at the report step, and had since
  the pattern was introduced — it survived because the bats suite covers bash
  only and the Windows smoke job passes `comment: 'false'`. All three `--jq`
  sites are rebuilt as single-quoted literals, verified against a real
  PowerShell parser. macOS and Linux runners were never affected.

## v1.3.0 — 2026-08-14

### Changed
- **Default `detector-version` is now `v0.6.0`** (was `v0.5.0`). Users pinned to
  `@v1` pick this up automatically.

### Why
- Engine v0.6.0 fixes two behaviors this action surfaces directly:
  - **`delta` no longer reports churn on line shifts** — inserting a line above
    a finding used to turn every finding below the edit into a `resolved` +
    `new` pair, so the PR comment listed phantom "New findings" (and a
    threshold check could fail) on whitespace-only changes. Line-shifted
    findings are now paired off and only real changes are reported.
  - **`delta` output is deterministic** — new/resolved lists follow scan order
    instead of map iteration order, so re-runs render identical comments.
  - Also upstream: capability inference covers ten more rules (the
    `permissions` block in scan JSON gets richer), triage verdict matching is
    collision-safe, and the registry checksum is **unchanged**
    (`589619b6386d2c41`) — no grading changes.

### Compatibility
- **No input or output changes.** Detection results change only via the engine
  bump; grading (axis letter) behavior is identical.

## v1.2.0 — 2026-08-05

### Changed
- **Default `detector-version` is now `v0.5.0`** (was `v0.4.0`). Users pinned to
  `@v1` pick this up automatically.

### Documented
- Engine v0.5.0 makes a **breaking change to the exit-code contract**: a new
  exit `3` (tool error — bad arguments, unreadable path, internal failure) is
  now distinct from `1` (findings below threshold) and `2` (findings at/above
  threshold). This action already passed every detector exit code through
  opaquely (`SCAN_EXIT_CODE`), so no script change was needed — `3` fails the
  job exactly as `1`/`2` do, which is correct: a scan that could not run is
  not a passing scan. Documented in `README.md`'s new "Exit codes" section and
  `docs/glossary.md`.

### Why
- Engine v0.5.0 adds `SD-024` (MCP auto-installed package execution — flags
  `npx`/`uvx`/`pipx`/`bunx` as an MCP server's `command`), extends several
  content rules to more agent harnesses (Codex, Gemini CLI, Cursor, Windsurf,
  Copilot), and fixes a gitignore-matching gap. See the `skill-detector`
  changelog for the full list, including scan-result changes (SD-018 rename,
  SD-023 severity downgrade, SD-001 fence-scoping fix).

### Compatibility
- **No input or output changes.** The exit-code *contract* changed upstream,
  but this action's behavior (opaque passthrough) did not — `3` was already
  propagated the same as any other non-zero code before this release, just
  untested and undocumented on this side.
- **Scan results can change** the same way any engine bump does: new rules may
  surface findings that previously passed.

---

## v1.1.0 — 2026-07-31

### Changed
- **Default `detector-version` is now `v0.4.0`** (was `v0.3.1`). Users pinned to
  `@v1` pick this up automatically.

### Fixed
- Release downloads now point at `github.com/skilltrust/skill-detector`. The
  previous URL used the pre-transfer `velzepooz` org and resolved only through
  GitHub's redirects, which expire — installs would eventually have 404'd.
- `action_version` reported in telemetry was hardcoded to `1.0.0`; it now
  matches the release tag.

### Why
- Two engine releases had shipped since the pinned version, so `@v1` users were
  missing two detection rules:
  - **`SD-022`** — DNS exfiltration / tunneling (`dig`, `nslookup`, `drill`
    combined with a dynamically built hostname). Added in engine v0.3.2 after it
    was the only miss in the SP-7 validation benchmark.
  - **`SD-023`** — unrestricted `"*"` permission grant in
    `.claude/settings.json`. Added in engine v0.3.3 after a wildcard grant was
    found to slip past `SD-017`/`SD-018`/`SD-019`.
- Engine v0.4.0 also adds an inert triage seam. It changes nothing for this
  action: with no verifier injected — which is every CLI invocation — the
  scanner behaves exactly as v0.3.x and emits the same JSON.

### Compatibility
- **No input, output or exit-code changes.** Nothing in the action's API moved.
- **Scan results can change.** A repository using DNS-based exfiltration or a
  wildcard permission grant will now be flagged where it previously passed. A
  build gated on `fail-on` may start failing — which is the point.

---

## v1.0.0 — 2026-05-21

Initial public release.

### Added
- Composite GitHub Action that downloads + verifies the `skill-detector` binary, scans the checked-out tree, and posts a sticky PR comment with a four-axis trust score.
- `delta: true` opt-in mode that fetches the base branch and shows ↑/↓ per axis + a "Why downgraded:" block.
- Multi-OS: `ubuntu-latest`, `macos-latest`, `windows-latest`.
- Fire-and-forget anonymous telemetry to `skilltrust.app` (opt-out via `telemetry: false`).
- Fork-PR graceful degradation (prints comment to job log + emits annotation).
