# shellcheck shell=bash
# Sourced by forge.sh. Implements the forge_* interface against `gh`.
# Requires: gh (authenticated), jq.

github_get_default_branch() {
    gh api "repos/$TARGET_REPO" --jq '.default_branch'
}

github_repo_settings() {
    gh api "repos/$TARGET_REPO"
}

# github_get_branch_protection [branch]
# Prints the protection JSON, or "{}" if none is configured (gh api 404s on
# an unprotected branch — treat that as "no protection", not an error).
github_get_branch_protection() {
    local branch="${1:-$(github_get_default_branch)}"
    gh api "repos/$TARGET_REPO/branches/$branch/protection" 2>/dev/null || echo '{}'
}

# github_set_branch_protection <branch> <json-payload-file>
github_set_branch_protection() {
    local branch="$1" payload_file="$2"
    gh api --method PUT "repos/$TARGET_REPO/branches/$branch/protection" \
        --input "$payload_file"
}

github_get_secret_scanning_status() {
    gh api "repos/$TARGET_REPO" --jq '.security_and_analysis // {}'
}

# github_enable_secret_scanning [push_protection]
github_enable_secret_scanning() {
    local with_push_protection="${1:-true}"
    local payload
    payload=$(jq -n --arg pp "$with_push_protection" '{
        security_and_analysis: {
            secret_scanning: {status: "enabled"},
            secret_scanning_push_protection: {status: (if $pp == "true" then "enabled" else "disabled" end)}
        }
    }')
    gh api --method PATCH "repos/$TARGET_REPO" --input - <<<"$payload"
}

github_collaborator_count() {
    gh api "repos/$TARGET_REPO/collaborators" --jq 'length' 2>/dev/null || echo 1
}

github_list_workflow_files() {
    gh api "repos/$TARGET_REPO/contents/.github/workflows" --jq '.[].name' 2>/dev/null || true
}

github_list_recent_commit_subjects() {
    local branch count
    branch="$(github_get_default_branch)"
    count="${1:-50}"
    gh api "repos/$TARGET_REPO/commits?sha=$branch&per_page=$count" \
        --jq '.[].commit.message | split("\n")[0]'
}

github_list_releases() {
    gh api "repos/$TARGET_REPO/releases" --jq '.[] | {tag: .tag_name, published_at: .published_at}' 2>/dev/null || true
}
