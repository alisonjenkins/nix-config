# shellcheck shell=bash
# Sourced by forge.sh. GitLab stub for v1 — proves the forge abstraction has
# two real call sites without doing full GitLab support yet. Every function
# here mirrors github.sh's interface; forge.sh's dispatcher falls back to
# "unsupported-forge" for anything not implemented below.
#
# When GitLab support lands, implement these against `glab api` the same way
# github.sh uses `gh api`, and forge_detect already routes *.gitlab.* here.

gitlab_get_default_branch() {
    echo "unsupported-forge:gitlab:get_default_branch" >&2
    return 2
}

gitlab_repo_settings() {
    echo "unsupported-forge:gitlab:repo_settings" >&2
    return 2
}

gitlab_get_branch_protection() {
    echo "unsupported-forge:gitlab:get_branch_protection" >&2
    return 2
}

gitlab_set_branch_protection() {
    echo "unsupported-forge:gitlab:set_branch_protection" >&2
    return 2
}

gitlab_get_secret_scanning_status() {
    echo "unsupported-forge:gitlab:get_secret_scanning_status" >&2
    return 2
}

gitlab_enable_secret_scanning() {
    echo "unsupported-forge:gitlab:enable_secret_scanning" >&2
    return 2
}

gitlab_list_workflow_files() {
    echo "unsupported-forge:gitlab:list_workflow_files" >&2
    return 2
}

gitlab_collaborator_count() {
    echo "unsupported-forge:gitlab:collaborator_count" >&2
    return 2
}

gitlab_list_recent_commit_subjects() {
    echo "unsupported-forge:gitlab:list_recent_commit_subjects" >&2
    return 2
}

gitlab_list_releases() {
    echo "unsupported-forge:gitlab:list_releases" >&2
    return 2
}
