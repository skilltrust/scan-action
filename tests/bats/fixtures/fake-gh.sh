#!/usr/bin/env bash
# Records invocations. FAKE_GH_COMMENTS is the already-slurped paginated JSON
# response (default: one empty page). FAKE_GH_FAIL may be lookup|patch|post.

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
        */issues/*/comments\?*)
          [[ "${FAKE_GH_FAIL:-}" == lookup* ]] && exit 1
          echo "${FAKE_GH_COMMENTS:-[[]]}"
          exit 0
          ;;
        */issues/comments/*)
          [[ "${FAKE_GH_FAIL:-}" == patch* ]] && exit 1
          echo '{"id":12345,"body":"(patched)"}'
          exit 0
          ;;
      esac
      shift
    done
    [[ "${FAKE_GH_FAIL:-}" == post* ]] && exit 1
    echo '{"id":12345,"body":"(created)"}'
    ;;
  *)
    echo "fake-gh: unknown subcommand $1" >&2
    exit 2
    ;;
esac
