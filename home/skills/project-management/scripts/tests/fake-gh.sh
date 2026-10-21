# Body of a fake `gh`. Logs argv and answers from fixture files so the tests
# never touch the network.
set -euo pipefail
fx="${FAKE_GH_FIXTURES:?FAKE_GH_FIXTURES must be set}"
printf '%s\n' "$*" >>"$fx/calls.log"
case "${1:-} ${2:-}" in
  "issue list")
    if [[ "$*" == *"--label pm-epic"* ]]; then
      cat "$fx/epics.json"
    else
      cat "$fx/list.json"
    fi
    ;;
  "issue view") cat "$fx/view.json" ;;
  "issue create")
    cat >"$fx/created-body.txt" || true
    echo "https://github.com/owner/name/issues/99"
    ;;
  "issue edit")
    if [[ ${FAKE_GH_FAIL_EDIT:-} == 1 ]]; then
      echo "fake gh: edit failed" >&2
      exit 1
    fi
    if [[ "$*" == *"--body-file -"* ]]; then cat >"$fx/edited-body.txt"; fi
    ;;
  "issue close" | "issue reopen" | "issue comment")
    # With FAKE_GH_READ_STDIN=1 behave like a gh that swallows stdin, so a missing
    # </dev/null inside a `while read` loop shows up as lost rows.
    if [[ ${FAKE_GH_READ_STDIN:-} == 1 ]]; then cat >/dev/null; fi
    ;;
  "label create") ;;
  *)
    echo "fake gh: unhandled call: $*" >&2
    exit 2
    ;;
esac
