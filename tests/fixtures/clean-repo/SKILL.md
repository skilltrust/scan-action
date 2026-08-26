---
name: clean-example
description: A benign skill package used as the clean-repo smoke fixture.
---

# Clean example

This fixture exists so the smoke matrix can assert what a **scanned and clean**
repository renders. It must contain real agent configuration: before engine
`v0.7.0`, a directory with none at all was graded `A` across every axis, and the
Windows comment smoke test asserted that `A` — which meant it was pinning the
empty-scan bug rather than a clean result. `v0.7.0` reports "nothing was
checked" for an empty tree instead, and the assertion correctly stopped holding.

Keep this file free of anything a rule fires on: no URLs, no credential paths,
no shell invocations, no encoded blobs. If a rule ever legitimately fires here,
fix the fixture rather than the assertion — the whole point is that a clean
grade is earned by being read, not by being absent.

## Usage

Ask the assistant to summarise a paragraph of text. It performs no I/O.
