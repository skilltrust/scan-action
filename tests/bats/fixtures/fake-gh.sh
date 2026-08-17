#!/usr/bin/env bash
# Records invocations to $FAKE_GH_LOG; honors $FAKE_GH_LIST_OUTPUT to
# simulate `gh api .../comments` listing results.
#
# --jq simulation gap: real gh would filter JSON via jq. The fake cannot.
# Instead, tests that need the jq-filtered ID set FAKE_GH_LIST_ID and/or
# FAKE_GH_BOT_ID; when the listing path is matched, the fake distinguishes
# the two listing call sites by looking for the App marker in its own
# arguments (since it cannot actually evaluate --jq):
#   FAKE_GH_BOT_ID  — echoed when the call's --jq expression mentions
#                      skilltrust:bot:v1 (the App-marker probe)
#   FAKE_GH_LIST_ID — echoed for the Action's own sticky-comment lookup

echo "GH_ARGS: $*" >> "${FAKE_GH_LOG:-/dev/null}"

case "$1" in
  api)
    ALL_ARGS="$*"
    shift
    # Find subcommand. Simulated subset:
    #   gh api repos/$repo/issues/$pr/comments  → returns JSON list (or filtered ID)
    #   gh api -X PATCH repos/$repo/issues/comments/$id -F body=@file → 200
    #   gh api repos/$repo/issues/$pr/comments -F body=@file → 201
    while [ $# -gt 0 ]; do
      case "$1" in
        */issues/*/comments)
          # GET listing. The real gh filters via --jq; the fake cannot, so it
          # distinguishes the two call sites by the marker in the jq
          # expression:
          #   args mention skilltrust:bot:v1 → the App-marker probe
          #                                    → echo FAKE_GH_BOT_ID
          #   otherwise                      → the Action's own sticky lookup
          #                                    → echo FAKE_GH_LIST_ID
          if echo "$ALL_ARGS" | grep -q "skilltrust:bot:v1"; then
            if [ -n "${FAKE_GH_BOT_ID:-}" ]; then echo "$FAKE_GH_BOT_ID"; fi
          elif [ -n "${FAKE_GH_LIST_ID:-}" ]; then
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
