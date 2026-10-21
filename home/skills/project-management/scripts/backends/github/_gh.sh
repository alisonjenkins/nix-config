# shellcheck shell=bash
# Shared argument handling for the github backend verbs. Sourced.

# shellcheck disable=SC2034 # read by the verbs that source this file
GH_FIELDS="number,title,state,assignees,labels,milestone,updatedAt,body"
# shellcheck disable=SC2034 # read by sync-plan.sh
GH_TASK_LIMIT=500
GH_LIMIT=200

# gh_take_repo "$@": take -r/--repo out of the arguments.
# Sets GH_REPO and GH_REST (the other arguments).
gh_take_repo() {
  GH_REPO="${PM_REPO:-}"
  GH_REST=()
  while (($#)); do
    case "$1" in
      -r | --repo)
        pm_arg2 "$@"
        GH_REPO="$2"
        shift 2
        ;;
      --repo=*)
        GH_REPO="${1#--repo=}"
        shift
        ;;
      *)
        GH_REST+=("$1")
        shift
        ;;
    esac
  done
  [[ -n $GH_REPO ]] || pm_die "the github backend needs -r owner/name"
  [[ $GH_REPO =~ ^[^/]+/[^/]+$ ]] || pm_die "-r must be owner/name, got '$GH_REPO'"
  pm_need gh jq
}

# gh_warn_truncated <json>: warn on stderr when a list hit the cap.
gh_warn_truncated() {
  local n
  n="$(jq length <<<"$1")"
  if ((n >= GH_LIMIT)); then
    echo "# warning: results truncated at $GH_LIMIT issues" >&2
  fi
}

# gh_truncated <json> <limit>: true (0) when a lookup returned as many issues as
# its cap, so a missing issue may just be past the cap.
gh_truncated() {
  local n
  n="$(jq length <<<"$1")"
  ((n >= $2))
}
