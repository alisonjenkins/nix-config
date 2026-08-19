# shellcheck shell=bash
# Sourced by audit.sh and checks/*.sh. Not executable on its own.
#
# Detects which forge a target repo lives on and dispatches the common
# interface (forge_get_*, forge_set_*) to the matching lib/<forge>.sh
# implementation. Unknown/unsupported forges get a clean "unsupported forge"
# report from callers instead of a crash — see each forge_* wrapper below.

SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./github.sh
source "$SCRIPT_LIB_DIR/github.sh"
# shellcheck source=./gitlab.sh
source "$SCRIPT_LIB_DIR/gitlab.sh"

# forge_detect <target> [--forge=<name>]
# Sets and exports FORGE (github|gitlab|unknown) and TARGET_REPO
# (owner/repo, forge API form) for subsequent forge_* calls.
forge_detect() {
    local target="$1"
    shift || true
    local override=""
    for arg in "$@"; do
        case "$arg" in
            --forge=*) override="${arg#--forge=}" ;;
        esac
    done

    if [[ -n "$override" ]]; then
        FORGE="$override"
    else
        local remote_url
        if git -C "$target" rev-parse --git-dir &>/dev/null; then
            remote_url="$(git -C "$target" remote get-url origin 2>/dev/null || true)"
        elif [[ "$target" == /* || "$target" == .* ]]; then
            # Looks like a filesystem path but isn't a git checkout (missing,
            # or a plain dir with no repo) — not a bare owner/repo shorthand.
            remote_url=""
        else
            # target wasn't a local checkout — treat it as owner/repo on the
            # default forge (github) unless a full URL was given.
            remote_url="$target"
        fi
        case "$remote_url" in
            *github.com*) FORGE=github ;;
            *gitlab.com*|*gitlab.*) FORGE=gitlab ;;
            git@*|https://*|http://*) FORGE=unknown ;;
            */*) FORGE=github ;; # bare owner/repo shorthand, assume github
            *) FORGE=unknown ;;
        esac
    fi
    export FORGE

    TARGET_REPO="$(forge_normalize_target "$target")"
    export TARGET_REPO
}

# forge_normalize_target <target> -> owner/repo
forge_normalize_target() {
    local target="$1"
    if git -C "$target" rev-parse --git-dir &>/dev/null; then
        local url
        url="$(git -C "$target" remote get-url origin 2>/dev/null || true)"
        case "$url" in
            git@*:*) echo "${url#*:}" | sed -E 's#\.git$##' ;;
            https://*|http://*) echo "$url" | sed -E 's#^https?://[^/]+/##; s#\.git$##' ;;
            *) basename "$target" ;;
        esac
    else
        echo "$target" | sed -E 's#^https?://[^/]+/##; s#\.git$##'
    fi
}

# Dispatchers: forge_<op> calls <forge>_<op> if defined, else reports
# unsupported. Every lib/<forge>.sh implements the same function names.
_forge_dispatch() {
    local op="$1"; shift
    local fn="${FORGE}_${op}"
    if declare -F "$fn" >/dev/null; then
        "$fn" "$@"
    else
        echo "unsupported-forge:${FORGE}:${op}"
        return 2
    fi
}

forge_get_branch_protection()        { _forge_dispatch get_branch_protection "$@"; }
forge_set_branch_protection()        { _forge_dispatch set_branch_protection "$@"; }
forge_get_secret_scanning_status()   { _forge_dispatch get_secret_scanning_status "$@"; }
forge_enable_secret_scanning()       { _forge_dispatch enable_secret_scanning "$@"; }
forge_get_default_branch()           { _forge_dispatch get_default_branch "$@"; }
forge_repo_settings()                { _forge_dispatch repo_settings "$@"; }
forge_list_workflow_files()          { _forge_dispatch list_workflow_files "$@"; }
forge_list_recent_commit_subjects()  { _forge_dispatch list_recent_commit_subjects "$@"; }
forge_list_releases()                { _forge_dispatch list_releases "$@"; }
