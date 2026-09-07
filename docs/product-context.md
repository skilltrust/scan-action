# What this Action is for

`scan-action` is the CI surface of **SkillTrust**, a product that scores the
trust and security of AI-agent configuration.

This repository is a wrapper and nothing else. It installs the detection
engine, runs it against the checked-out tree, presents the result on the pull
request, and turns the engine's exit code into a pass or a fail. **Nothing here
decides what a scan concludes** — every rule, every grade and every severity is
the engine's.

## The problem

A repository accumulates agent configuration the way it accumulates
dependencies: an instruction file at the root, another two levels down, a
settings file, a few hooks, an MCP server someone added for one task. Each
addition is small and reviewed on its own. Nobody has a picture of what all of
it permits, taken together.

The dangerous part is rarely a compiled artifact. It is text — sitting in a
manifest, an instruction file or a settings blob — that an agent will read and
act on, inside a checkout that already has the shell, the filesystem and the
credentials. Reading every line by hand does not scale, and skimming does not
work, because the interesting content is written to look ordinary.

Auditing that surface once and declaring it clean solves it for a day. The
surface changes on every pull request that touches it.

## The object this Action checks

The product is built around two questions, and this Action answers the second
of them.

**Check a skill** — *"Can I install this thing?"* The subject is one skill.
That is a question someone asks before a file reaches their machine, so it is
answered by the CLI and the hosted scanner, not from CI.

**Check a repository** — *"What can my agents do in this project?"* The subject
is a whole tree: every skill in it, plus the instruction files, the settings,
the hooks and the MCP configuration. That is this Action's object. The reader
is whoever is responsible for the project.

This shapes what belongs here. Anything that only makes sense for one skill in
isolation does not; anything that only makes sense once a repository has a
history — a stored result, a trend, a badge — belongs to the hosted scanner,
which has somewhere to keep it.

## Who runs it

Maintainers gating their own repositories, who want the agent surface checked
on every change rather than audited once and forgotten. They are the ones who
feel a false build failure, and they are the ones who switch a noisy gate off.

Two things follow from that, and they run through every design decision in this
repository:

- **Everything runs inside the runner.** The scan is a released binary
  executing on the user's own machine against the user's own checkout. Nothing
  about the repository's contents leaves it, on public and private
  repositories alike.
- **A gate that is wrong often gets deleted.** A finding that is reported but
  does not block is still a finding the team can see. A build that reddens on
  something the team disagrees with is gone by the end of the week, and it
  takes the true findings with it. So the default gate is narrow and the
  reporting is wide: only a CRITICAL finding fails a build nobody configured,
  and everything below that is shown in full.

## The three surfaces

The engine reaches users three ways, and they differ in where the scan runs
and what is remembered.

- **The `skill-detector` CLI.** Run locally against a directory or a file.
  Offline, deterministic, no account.
- **The hosted scanner at [skilltrust.app](https://skilltrust.app).** Point it
  at a skill or a repository in the browser and read the report there. It also
  backs a GitHub App, which comments on pull requests from the service side and
  can remember the last result, issue a badge and triage the noise.
- **This Action.** Runs the same scan in the user's CI and gates the build on
  it.

All three run the same rules and produce the same grades. See
[`cross-repo.md`](cross-repo.md) for how they are wired together.

The Action and the GitHub App overlap on purpose, and a repository may run
both. When it does, the App is the one that comments: it scanned on the
service side, it has history, and two grade comments on one pull request is
worse than either alone. The Action detects the App's comment and stands down
from reporting while continuing to run the checks. See "Superseded comment" in
[`glossary.md`](glossary.md).

## What a result means

A scan grades four axes on an A–F scale and reports the findings that drove
each letter. The Action shows all of them and gates on a threshold the user
sets.

The grades are a statement about the files the rules actually read. When a scan
finds no agent surface to inspect, it says so and issues no grades, rather than
reporting a clean result about a tree nothing looked at — which is why this
Action reports "nothing was checked" as its own outcome and never as a pass.

An `A` on an axis means nothing was counted against it. It is the absence of a
detection, not a certificate: a scanner reports what it can recognise, and a
clean result is evidence, not a guarantee. A green build here means the same
thing, and no more.
