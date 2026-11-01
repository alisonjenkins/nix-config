#!/usr/bin/env bash
# Opens, updates, or closes a GitHub issue summarising check-currency.sh findings.
# Usage: raise-currency-issue.sh [--repo OWNER/REPO] [--dry-run] [--registry FILE] [--today YYYY-MM-DD] [--offline]
# Prints action and issue body on stdout, passes check-currency summary to stderr.
# Exit 0 on success, 1 on gh failure, 2 on bad usage. Needs bash, jq, gh.
set -euo pipefail

TITLE="Skill guidance sources need review"
repo="${GITHUB_REPOSITORY:-}"
dry_run=0
today=""
passthrough=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)
            [[ $# -ge 2 ]] || { echo "error: --repo requires an argument" >&2; exit 2; }
            repo="$2"
            shift 2
            ;;
        --dry-run)
            dry_run=1
            shift
            ;;
        --registry)
            [[ $# -ge 2 ]] || { echo "error: --registry requires a file" >&2; exit 2; }
            passthrough+=("--registry" "$2")
            shift 2
            ;;
        --today)
            [[ $# -ge 2 ]] || { echo "error: --today requires a date" >&2; exit 2; }
            today="$2"
            passthrough+=("--today" "$2")
            shift 2
            ;;
        --offline)
            passthrough+=("--offline")
            shift
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

if [[ -z "$today" ]]; then
    today="$(date -u +%Y-%m-%d)"
fi

if [[ -z "$repo" && $dry_run -eq 0 ]]; then
    echo "error: --repo is required" >&2
    exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check_currency="$script_dir/check-currency.sh"
if [[ ! -x "$check_currency" ]]; then
    echo "error: check-currency.sh not executable at: $check_currency" >&2
    exit 2
fi

# Exit 1 (findings) and 2 (INVALID lines) both print findings on stdout. A failure with
# nothing on stdout is a crash, and must not read as "clean" and close an open issue.
check_status=0
# The ${arr[@]+...} form keeps an empty array legal under set -u on bash 3.2.
findings="$("$check_currency" ${passthrough[@]+"${passthrough[@]}"})" || check_status=$?
if (( check_status != 0 )) && [[ -z "$findings" ]]; then
    echo "error: check-currency.sh failed (exit ${check_status}) with no findings; leaving issues untouched" >&2
    exit 1
fi

issue_number=""
if [[ -n "$repo" ]]; then
    # In --dry-run without --repo, skip lookup and treat as no existing issue.
    issue_json="$(gh issue list --repo "$repo" --state open --search "$TITLE in:title" --json number,title)"
    issue_number="$(jq -r --arg title "$TITLE" 'if type == "array" then [.[] | select(.title == $title)] | .[0].number // empty else empty end' <<< "$issue_json")"
fi

body_file=""
cleanup() {
    if [[ -n "$body_file" && -f "$body_file" ]]; then
        rm -f "$body_file"
    fi
}
trap cleanup EXIT

if [[ -n "$findings" ]]; then
    body_file="$(mktemp)"
    {
        printf 'The monthly check found sources to review:\n\n```\n'
        printf '%s\n' "$findings"
        # shellcheck disable=SC2016 # Markdown uses literal backticks.
        printf '```\n\nRun `/skill-currency` (or `just skill-currency`); procedure in `home/skills/skill-authoring/currency.md`.\n'
    } > "$body_file"

    if [[ -n "$issue_number" ]]; then
        if (( dry_run )); then
            echo "would edit #$issue_number"
            cat "$body_file"
        else
            gh issue edit "$issue_number" --repo "$repo" --body-file "$body_file"
            echo "edited #$issue_number"
        fi
    else
        if (( dry_run )); then
            echo "would create"
            cat "$body_file"
        else
            gh issue create --repo "$repo" --title "$TITLE" --body-file "$body_file"
            echo "created"
        fi
    fi
else
    if [[ -n "$issue_number" ]]; then
        if (( dry_run )); then
            echo "would close #$issue_number"
        else
            gh issue comment "$issue_number" --repo "$repo" --body "All guidance sources are current as of ${today}."
            gh issue close "$issue_number" --repo "$repo"
            echo "closed #$issue_number"
        fi
    else
        echo "nothing to do"
    fi
fi
