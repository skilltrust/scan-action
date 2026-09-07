# AGENTS.md

Be extremely concise. Sacrifice grammar for the sake of concision.

This is the coding contract for `scan-action`. It applies to every agent and
every contributor working in this repo. `CLAUDE.md` is a symlink to this file.

`scan-action` is a GitHub Action wrapping the SkillTrust engine. **Composite
action, shell only — no JS, no Docker, no compiled code.** Published to the
Marketplace as `skilltrust/scan-action@v1`.

## Project knowledge

Docs map: [`docs/README.md`](docs/README.md). The committed doc set is:

| Artifact | Location | When to write |
|----------|----------|---------------|
| Docs map | [`docs/README.md`](docs/README.md) | A doc is added or removed. |
| Architecture | [`docs/architecture.md`](docs/architecture.md) | A step is added or removed, a script pair changes, or the env contract between steps changes. |
| Term / invariant | [`docs/glossary.md`](docs/glossary.md) | A new concept or contract appears. |
| What this Action is for | [`docs/product-context.md`](docs/product-context.md) | The intended use or audience changes. |
| The other repositories | [`docs/cross-repo.md`](docs/cross-repo.md) | The engine pin, the published input/output surface, or a consumer contract changes. |
| **User-facing change** | `README.md` + `CHANGELOG.md` | An input, an output, or a behaviour changes — in the same PR. |

Never document the same thing twice. The step wiring and the env contract live
only in `docs/architecture.md`; this file carries the behavioural contract.

`docs/` is allow-listed in `.gitignore`: a new file there publishes nothing
until it is named in that list. Not everything the maintainer keeps is in this
repo — when a rule below has no reason attached, that is deliberate. See
"Settled behaviour".

## Architecture

Composite action, seven logical steps in order: install → scan → delta →
render comment → post comment → telemetry → propagate exit. Step wiring, the
script pairs, and the env contract between them:
**[`docs/architecture.md`](docs/architecture.md)** (single source of truth —
do not duplicate the table here).

## Hard-won rules

- **Every script is a pair.** `scripts/foo.sh` (bash) and `scripts/foo.ps1` (pwsh) must stay behaviourally identical — Windows runners take the `.ps1` path. Change one, change both, or Windows silently diverges. The rule covers scripts whose step is selected by `runner.os`; `run-tests.sh` and `propagate-exit.sh` are bash-only on purpose and are not violations. Do not add a `.ps1` for either.
- **Scripts communicate only through env vars and `$GITHUB_ENV`/`$GITHUB_OUTPUT`.** No shared state, no assumptions about cwd. Each script's header comment lists its required env; the cross-step values are tabulated in `docs/architecture.md`. Adding a value that crosses a step boundary means adding it to `action.yml`, to both halves of the pair, and to that table.
- **Telemetry must never fail the build** — `set +e`, `curl … || true`, `exit 0`. Same for anything non-essential. A heartbeat that reddens a build is worse than no heartbeat.
- **The sticky-comment marker `<!-- skilltrust:action:v1 -->` is a wire contract.** It must be the first line of the comment body; `report.{sh,ps1}` finds the existing comment by matching on it. Changing it orphans every comment already posted and turns the next run into a duplicate.
- **Fork PRs cannot post comments.** GitHub hands a fork-origin PR a read-only token, so `report.{sh,ps1}` prints the rendered comment into the job log and emits a `::warning::` annotation instead of failing.
- **The Action yields to the GitHub App.** If a comment carrying the App's marker is already on the PR, `report.{sh,ps1}` replaces its own comment with a superseded note and exits, so a repository running both does not carry two disagreeing grade comments.
- **The scan step never fails.** It stashes the engine's exit code in `SCAN_EXIT_CODE`, and the final step re-raises it — that is what lets the comment, delta and telemetry steps run at all on a failing scan. Removing the final step makes a failing scan silent.
- Tests are `bats` against fake binaries in `tests/bats/fixtures/`, so they never reach the network or GitHub. Run `./scripts/run-tests.sh`.

## Changing an input or an output

The names in `action.yml` are the public API — `README.md` documents them and
Marketplace users depend on them. Adding one is a minor. Renaming or removing
one is a breaking change and needs a `v2`, not a `v1.x`.

A default is part of that surface too. Changing a gate default changes the
verdict on repositories nobody reconfigured, so it ships with its reasoning in
`CHANGELOG.md` in the same PR.

## Release

Tag `v1.*` → `.github/workflows/release.yml` force-moves the floating `v1` tag
to that commit. Consumers pinning `@v1` get the move automatically and without
editing their workflow; immutable `v1.x.y` tags stay for anyone pinning
exactly.

Two version strings must move with the tag: the `INPUT_ACTION_VERSION` literal
in `action.yml`'s telemetry steps, and the `CHANGELOG.md` entry. Neither is
derived from the tag, so neither notices one.

Released behaviour, per version: `CHANGELOG.md`. It is public and
authoritative; do not restate it here.

## Settled behaviour — confirm before changing

Some behaviour here looks like an oversight and is not. Do not change any of
the following on inference; ask the maintainer first and get a yes:

- **The sticky-comment marker `<!-- skilltrust:action:v1 -->`**, and its position as the first line of the body.
- **The input names** — `path`, `fail-on`, `fail-on-axis`, `strict-mcp`, `scan-all`, `comment`, `warn-on-below-threshold`, `fail-on-no-agent-surface`, `delta`, `telemetry`, `github-token`, `detector-version` — and **the output names** — `grade`, `scan-json-path`, `findings-count`, `no-agent-surface`.
- **The gate defaults**: `fail-on: critical` and `warn-on-below-threshold: 'true'`. Only a CRITICAL finding fails a build nobody configured. The default is written in three places that must agree — `action.yml`, the `FAIL_ON` fallback in `scan.{sh,ps1}`, and the `INPUT_WARN_ON_BELOW_THRESHOLD` fallback in `propagate-exit.sh`. `action.yml` is the source of truth and `tests/bats/gate-defaults.bats` reads it and pins all three.
- **The telemetry-never-fails rule**, and the payload's field set. Telemetry is on by default; it stays anonymous and it stays incapable of failing a build.
- **The exit-code mapping.** Only engine exit `1` is ever downgraded, and only under `warn-on-below-threshold: true`. `2` is a real threshold breach; `3` means the scan never ran, and a scan that could not run is not a passing scan. An unrecognised code is re-raised untouched rather than guessed at.
- **The `no-agent-surface` default.** A scan that read no agent configuration files produced no grade. It passes by default with the claim withdrawn loudly in the annotation and the comment, and gates only when `fail-on-no-agent-surface: true`. It is not a missing default to fill in.
- **The floating `v1` tag** and what it is allowed to move across.

The reasoning behind each of these is recorded outside this repo. Absence of a
reason in the codebase is not evidence that there isn't one.
