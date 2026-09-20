#!/usr/bin/env bash
# One-call PR status for an unattended commit->PR->merge loop: checks
# rollup, review decision, mergeable state, unresolved threads, and
# suppressed findings, all from a single GraphQL query -- instead of the
# 5-6 separate gh calls (gh pr checks, gh pr view --json ..., a hand-typed
# reviewThreads query, gh api .../reviews twice) that sequence otherwise
# takes. For the narrower "watch for a human review and reply" loop, see
# poll-pr-review.sh instead -- this script is for the merge-gate decision.
set -euo pipefail

usage() {
  echo "usage: $0 <pr-number> [owner/repo]" >&2
  echo "  owner/repo defaults to the current repo (gh repo view)" >&2
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 1
fi

pr_number="$1"
if [[ -n "${2:-}" ]]; then
  if ! [[ "$2" =~ ^[^/]+/[^/]+$ ]]; then
    echo "error: [owner/repo] must be exactly 'owner/repo', got '$2'" >&2
    exit 1
  fi
  owner="${2%%/*}"
  repo="${2##*/}"
else
  name_with_owner="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
  owner="${name_with_owner%%/*}"
  repo="${name_with_owner##*/}"
fi

if ! [[ "$pr_number" =~ ^[0-9]+$ ]]; then
  echo "error: <pr-number> must be numeric, got '$pr_number'" >&2
  exit 1
fi

echo "== PR #$pr_number ($owner/$repo) =="

threads_tsv=""
page_after=""
page_count=0
max_pages=20
scalar_json=""
while :; do
  page_count=$((page_count + 1))
  if [[ $page_count -gt $max_pages ]]; then
    echo "error: review threads pagination exceeded $max_pages pages ($((max_pages * 100)) threads); aborting rather than looping forever" >&2
    exit 1
  fi
  query_args=(-F owner="$owner" -F repo="$repo" -F pr="$pr_number")
  [[ -n "$page_after" ]] && query_args+=(-F after="$page_after")
  # shellcheck disable=SC2016 # single-quoted on purpose: GraphQL variables, not shell ones
  if ! page_json="$(gh api graphql -f query='
    query($owner:String!,$repo:String!,$pr:Int!,$after:String){
      repository(owner:$owner,name:$repo){
        pullRequest(number:$pr){
          state isDraft headRefOid reviewDecision mergeable mergeStateStatus
          autoMergeRequest{enabledAt}
          commits(last:1){nodes{commit{statusCheckRollup{state}}}}
          reviewRequests(first:20){nodes{requestedReviewer{
            ... on User{login} ... on Bot{login}}}}
          latestReviews(first:20){nodes{author{login} state submittedAt commit{oid} body}}
          reviews(first:100){nodes{body}}
          reviewThreads(first:100, after:$after){
            pageInfo{hasNextPage endCursor}
            nodes{
              id isResolved isOutdated path line
              comments(first:1){nodes{databaseId author{login} body}}}}}}}' \
    "${query_args[@]}")"; then
    echo "error: failed to fetch PR status via GraphQL (auth or network issue?)" >&2
    exit 1
  fi
  if [[ $page_count -eq 1 ]]; then
    scalar_json="$page_json"
  fi
  page_tsv="$(jq -r '.data.repository.pullRequest.reviewThreads as $rt
    | ($rt.nodes[]
      | select(.isResolved == false)
      | [.id, (.isOutdated|tostring), .path, (.line|tostring),
         (.comments.nodes[0].databaseId|tostring), .comments.nodes[0].author.login,
         .comments.nodes[0].body] | @tsv),
      ("__PAGEINFO__\t" + ($rt.pageInfo.hasNextPage|tostring) + "\t" + ($rt.pageInfo.endCursor // ""))' \
    <<<"$page_json")"
  pageinfo_line="$(grep $'^__PAGEINFO__\t' <<<"$page_tsv")" || true
  page_rows="$(grep -v $'^__PAGEINFO__\t' <<<"$page_tsv")" || true
  threads_tsv+="$page_rows"$'\n'
  if [[ -z "$pageinfo_line" ]]; then
    echo "error: page $page_count of the reviewThreads query had no __PAGEINFO__ sentinel (API/jq output changed?); refusing to silently treat this as the last page" >&2
    exit 1
  fi
  hasnext=""
  cursor=""
  IFS=$'\t' read -r _ hasnext cursor <<<"$pageinfo_line"
  if [[ "$hasnext" == "true" && -z "$cursor" ]]; then
    echo "error: page $page_count reported hasNextPage=true with an empty endCursor; refusing to re-fetch the same page forever" >&2
    exit 1
  fi
  [[ "$hasnext" == "true" ]] || break
  page_after="$cursor"
done

# --- Compact status line ---
jq -r '.data.repository.pullRequest as $pr
  | "state=\($pr.state) draft=\($pr.isDraft) head=\($pr.headRefOid[0:8]) " +
    "reviewDecision=\($pr.reviewDecision // "null") mergeable=\($pr.mergeable) " +
    "mergeStateStatus=\($pr.mergeStateStatus) autoMerge=\($pr.autoMergeRequest != null) " +
    "checks=\($pr.commits.nodes[0].commit.statusCheckRollup.state // "NONE") " +
    "reviewRequests=" + ([$pr.reviewRequests.nodes[].requestedReviewer.login | select(. != null)] | join(","))' \
  <<<"$scalar_json"
echo

# --- Unresolved review threads ---
echo "-- Unresolved review threads (repliable) --"
thread_count=0
while IFS=$'\t' read -r thread_id is_outdated path line comment_id author body; do
  [[ -z "$thread_id" ]] && continue
  thread_count=$((thread_count + 1))
  outdated_note=""
  [[ "$is_outdated" == "true" ]] && outdated_note=" [outdated: code has changed since]"
  echo "[$comment_id] $path:$line (thread $thread_id)$outdated_note"
  echo "  $author: $(head -c 300 <<<"$body" | tr '\n' ' ')"
done <<<"$threads_tsv"
if [[ $thread_count -eq 0 ]]; then
  echo "(none)"
fi
echo

# --- Suppressed / "previously missed" findings ---
echo "-- Suppressed/previously-missed findings across all reviews (dedup) --"
suppressed="$(jq -r '.data.repository.pullRequest.reviews.nodes[] | select(.body != "") | .body' <<<"$scalar_json" \
  | awk '
    /^\*\*[^*]+:[0-9]+\*\*$/ {
      loc = substr($0, 3, length($0) - 4)
      got = (getline nextline)
      if (got > 0 && nextline ~ /^\* /) {
        text = substr(nextline, 3)
        key = loc "\x1f" text
        if (!(key in seen)) {
          seen[key] = 1
          print loc "\t" text
        }
      }
      next
    }
  ' | sort -u)"
if [[ -z "$suppressed" ]]; then
  echo "(none)"
else
  while IFS=$'\t' read -r loc text; do
    echo "$loc"
    echo "  $text"
  done <<<"$suppressed"
fi
echo

# --- Latest review with a summary body ---
# The body's literal first line is near-useless for bots like Copilot's
# reviewer — it's an HTML marker comment (<!-- ccr-overview-v2 -->), with
# the actual verdict ("### Needs a closer look", plus its explanation
# paragraph) several lines further down. `split("\n")[0]` alone silently
# hid every such verdict behind that comment; the awk filter below skips
# comment/heading noise and stops before the trailing metadata
# (**Review effort**, <details>) instead.
echo "-- Latest review verdict --"
latest_review_json="$(jq -c '.data.repository.pullRequest.latestReviews.nodes
    | map(select(.body != "")) | sort_by(.submittedAt) | last' <<<"$scalar_json")"
if [[ "$latest_review_json" == "null" ]]; then
  echo "(no review with a summary yet)"
else
  jq -r '"[\(.submittedAt)] \(.author.login) on \(.commit.oid[0:8]):"' <<<"$latest_review_json"
  jq -r '.body' <<<"$latest_review_json" | awk '
    /^<!--/ { next }
    /^##[^#]/ { next }
    /^\*\*Review effort/ { exit }
    /^<details/ { exit }
    /^$/ { if (started) print; next }
    { started = 1; print }
  '
fi
