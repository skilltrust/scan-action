# Documentation map

Entry point for humans and agents working on `scan-action`. Each kind of
project knowledge has exactly one home; nothing here is documented twice.

| Location | What lives here |
|----------|-----------------|
| [`README.md`](README.md) | This map. |
| [`product-context.md`](product-context.md) | What this Action is for and who runs it. Start here if you are new. |
| [`architecture.md`](architecture.md) | **Single source of truth** for how the composite action is wired: the steps in order, the script pairs, and the env contract between them. |
| [`glossary.md`](glossary.md) | Terms specific to this repository: sticky comment, floating `v1`, fork degradation, delta mode, gate defaults, script pair. |
| [`cross-repo.md`](cross-repo.md) | The other two repositories, what this one depends on, and what a release has to move. |
| [`../README.md`](../README.md) | User-facing: inputs, outputs, exit codes, permissions, telemetry. What a Marketplace user reads. |
| [`../CHANGELOG.md`](../CHANGELOG.md) | Released behaviour, per version. Authoritative. |
| [`../action.yml`](../action.yml) | The Action definition itself: the inputs, the outputs, the steps and their conditions. |
| [`../AGENTS.md`](../AGENTS.md) | The coding contract: the script-pair rule, the env-only rule, what is settled. `CLAUDE.md` is a symlink to it. |

`AGENTS.md` also states **when** each artifact above should be written.

## What is not here

This project's internal engineering records are kept privately by the
maintainer and are not part of this repository. The doc set above is what this
repository carries, and it is complete as it stands. If something you need to
know is missing or looks wrong, open an issue rather than treating a gap as a
file that failed to land; a question in an issue is the supported route and
gets an answer.

## Conventions

- Everything here is written in English.
- `docs/` is allow-listed in `.gitignore`. A new file in this directory
  publishes nothing until it is named in that list, and it is named there only
  after it has been read for anything that should not be public. Adding a doc
  means adding a row above and a line to `.gitignore`, in the same change.
- `action.yml` is the source of truth for anything an input or output does.
  Where a doc and `action.yml` disagree, `action.yml` is right and the doc is
  what to fix.
