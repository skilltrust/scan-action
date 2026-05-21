# SP-5 Follow-Ups

What remains after code-complete on 2026-05-21. Ordered by blocker chain.

## 1. Push scan-action to a public GitHub repo

**Blocker:** `github.com/skilltrust` org does not exist yet.

```bash
# After creating the skilltrust org + empty scan-action repo on github.com:
cd "/Users/glibrulev/projects/saas/skil security/scan-action"
git remote add origin git@github.com:skilltrust/scan-action.git
git push -u origin main
# Watch CI: matrix on ubuntu/macos/windows × {clean,malicious} + smoke-pr-comment + smoke-pr-delta
gh run watch
# Once main CI green:
git push origin v1.0.0
# release.yml automatically moves the `v1` tag
```

**Why staged push (main first, then tag):** matches the [[execution-preferences]] convention — never tag without watching CI green first.

## 2. Validate scan-action end-to-end on a real PR

Open a no-op PR on the scan-action repo itself. Expect:

- ✅ `bats` job green (1 + matrix combos green)
- ✅ `smoke-clean` matrix green (3 OSes)
- ✅ `smoke-malicious` matrix green (3 OSes, action exits non-zero, assert step says so)
- ✅ `smoke-pr-comment` posts exactly 1 marker-tagged comment
- ✅ `smoke-pr-delta` posts a marker-tagged comment (with delta column)

If install.sh fails: check the asset URL — it's `skill-detector_${VERSION#v}_${OS}_${ARCH}.tar.gz` (post-fix). If it's the old `skill-detector_${OS}_${ARCH}.tar.gz` you're on an unfixed commit.

## 3. Submit GitHub Marketplace listing

Manual UI step at https://github.com/marketplace.

- Category: `Code quality` (primary), `Security` (secondary)
- Required: README, LICENSE, branding (icon: shield, color: green — both in action.yml already)
- Verified-creator badge follows after GitHub review (no SLA)

Capture screenshot of first real PR comment for the listing's "media" tab.

## 4. Install scan-action on `skill-detector` repo (dogfood)

```yaml
# skill-detector/.github/workflows/skilltrust.yml
name: skilltrust
on:
  pull_request:
permissions:
  contents: read
  pull-requests: write
jobs:
  skilltrust:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: skilltrust/scan-action@v1
        with:
          delta: true
          fail-on: high
```

Open a no-op PR on `skill-detector`. Comment should appear with all 4 axes graded A (no findings). Screenshot for SP-5 release notes.

## 5. Deploy skillmoss-go (separate from SP-5 but unblocks telemetry uplink)

Per [[skilltrust-status]], skillmoss-go has never been deployed. To make the telemetry endpoint reachable from CI runners:

1. `compose.prod.yaml` already exists. Deploy target needs DNS pointed at it.
2. Migration 0008 auto-runs on first store.Open (per existing `internal/store/migrate.go` pattern).
3. Confirm `/api/telemetry/action-run` reachable from the public internet (test with `curl -X POST https://skilltrust.io/api/telemetry/action-run -d '{...}'` from a non-runner host).
4. Hit `/internal/metrics` with `Authorization: Bearer $SKILLMOSS_INTERNAL_TOKEN`; expect `action_runs_24h` to increment after each scan-action run on any repo.

**Until deploy:** scan-action's telemetry POST goes to a black hole (curl times out, swallowed by `set +e`). Action still works fine — only the install-counting signal is missing.

## 6. Verify SP-4 PR-bot still renders identically (deferred from C5)

Golden-file snapshot already proves byte-identical render at the unit level (158 tests green). Real-PR verification needs the deploy in §5.

After deploy, open a no-op PR on `velzepooz/blog` (SP-4's dogfood target). The bot comment text should be byte-identical to whatever it produced pre-refactor.

If it differs: pre-refactor commit history exists at `skillmoss-go` `36d2be6` onward — comparison commit is `fcfac2f`.

## 7. Carry-overs not blocking SP-5 close

- **SP-4.1** ([[skilltrust-status]]): `installs.StateMachine.HandleInstallationRepositories` silently drops `installation_repos` rows when parent installation row missing (out-of-order webhook). Should upsert or log warning. Not blocking SP-5 because SP-5 doesn't touch installs.
- **scan-action smoke-pr-comment assertion** asserts "exactly 1" marker comment. If a future test run re-uses the same PR (PR not re-opened), the stale comment from the prior run would already exist → PATCH → still 1 → green. But if the assertion ever flakes to "2 found", it means the marker matching broke. Investigate `report.sh` regex before chasing GitHub-side ghosts.
- **`pull_request_target` workflow template** intentionally not shipped (security caveat documented in README). Add if a customer requests it WITH explicit acknowledgment of the supply-chain trade-off.

## 8. Phase 1 go/no-go gate signals to watch

Per PRD § Phase 1, SP-5 + SP-6 together feed the 4-of-4 gate at Wk 6-8:

| Signal | Source |
|---|---|
| 100+ Action installs | `/internal/metrics` → `action_installs_unique_7d` |
| 100+ PR comments/wk | existing SP-4 metric (post-deploy) |
| 1000+ free scans/wk | existing SP-2/3 metric |
| 3+ inbound enterprise inquiries | manual |
| HN front-page hit (one of) | SP-6 |
| Independent third-party write-up (one of) | SP-6 |
| Unprompted marketplace badge embed (one of) | SP-6 |

When the metric crosses 100 unique Action installs, that's the loudest "wedge is working" signal. Reassess Phase 2 monetization gate at that point.
