#!/usr/bin/env bash
# Records invocations to $FAKE_GH_LOG; honors $FAKE_GH_LIST_OUTPUT to
# simulate `gh api .../comments` listing results.
#
# --jq simulation gap: real gh would filter JSON via jq. The fake cannot.
# Instead, tests that need the jq-filtered ID set FAKE_GH_LIST_ID; when
# present and the listing path is matched, the fake echoes just that ID
# (simulating the `--jq '.[] | select(...) | .id'` output).

echo "GH_ARGS: $*" >> "${FAKE_GH_LOG:-/dev/null}"

case "$1" in
  api)
    shift
    # Find subcommand. Simulated subset:
    #   gh api repos/$repo/issues/$pr/comments  → returns JSON list (or filtered ID)
    #   gh api -X PATCH repos/$repo/issues/comments/$id -F body=@file → 200
    #   gh api repos/$repo/issues/$pr/comments -F body=@file → 201
    while [ $# -gt 0 ]; do
      case "$1" in
        */issues/*/comments)
          # GET listing — simulate --jq filtering via FAKE_GH_LIST_ID.
          # real `gh api --jq` filters JSON; the fake cannot. Instead:
          #   FAKE_GH_LIST_ID set   → echo just the id (jq returned a match)
          #   FAKE_GH_LIST_ID unset → echo nothing (jq returned no matches / empty list)
          if [ -n "${FAKE_GH_LIST_ID:-}" ]; then
            echo "$FAKE_GH_LIST_ID"
          fi
          exit 0
          ;;
        */issues/comments/*)
          # PATCH
          echo '{"id":12345,"body":"(patched)"}'
          exit 0
          ;;
      esac
      shift
    done
    # Default POST new comment
    echo '{"id":12345,"body":"(created)"}'
    ;;
  *)
    echo "fake-gh: unknown subcommand $1" >&2
    exit 2
    ;;
esac
