#!/usr/bin/env bash
# Summarizes outstanding GitHub PR review feedback in one pass, so polling
# doesn't rely on "check the latest review" (array order isn't chronological,
# and reviewers like Copilot often bury real findings as body-only prose —
# no comment id, no thread — in earlier reviews that a "just the latest one"
# check would never revisit). Reports two independent things:
#   - unresolved review-thread comments (GraphQL, has ids, repliable)
#   - suppressed/"previously missed" findings mentioned in ANY review's body
#     text, deduplicated — these have no thread or comment id at all
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
echo

# --- Unresolved review-thread comments: the authoritative, repliable set ---
echo "-- Unresolved review threads (repliable) --"
# Paginated: reviewThreads(first:100) alone would silently truncate a PR
# with more than 100 threads. Each page's jq output ends with a
# "__PAGEINFO__\t<hasNextPage>\t<endCursor>" sentinel row; loop until
# hasNextPage is false, capped at max_pages so a schema/API change that
# breaks pageInfo can't spin this forever.
threads_tsv=""
page_after=""
page_count=0
max_pages=20
while :; do
  page_count=$((page_count + 1))
  if [[ $page_count -gt $max_pages ]]; then
    echo "error: review threads pagination exceeded $max_pages pages ($((max_pages * 100)) threads); aborting rather than looping forever" >&2
    exit 1
  fi
  query_args=(-F owner="$owner" -F repo="$repo" -F pr="$pr_number")
  [[ -n "$page_after" ]] && query_args+=(-F after="$page_after")
  # Captured into a variable and checked explicitly rather than piped
  # straight into a while loop via process substitution: a process
  # substitution's exit status isn't checked by the enclosing command
  # under set -e, so a GraphQL auth/network failure would otherwise print
  # nothing and misreport "(none)" instead of failing loudly.
  # shellcheck disable=SC2016 # single-quoted on purpose: $owner/$repo/$pr/$after below are GraphQL variables, not shell ones
  if ! page_tsv="$(gh api graphql -f query='
    query($owner:String!,$repo:String!,$pr:Int!,$after:String){
      repository(owner:$owner,name:$repo){
        pullRequest(number:$pr){
          reviewThreads(first:100, after:$after){
            pageInfo{hasNextPage endCursor}
            nodes{
              id isResolved isOutdated path line
              comments(first:1){nodes{databaseId author{login} body}}}}}}}' \
    "${query_args[@]}" \
    --jq '.data.repository.pullRequest.reviewThreads as $rt
      | ($rt.nodes[]
        | select(.isResolved == false)
        | [.id, (.isOutdated|tostring), .path, (.line|tostring),
           (.comments.nodes[0].databaseId|tostring), .comments.nodes[0].author.login,
           .comments.nodes[0].body] | @tsv),
        ("__PAGEINFO__\t" + ($rt.pageInfo.hasNextPage|tostring) + "\t" + ($rt.pageInfo.endCursor // ""))')"; then
    echo "error: failed to fetch review threads via GraphQL (auth or network issue?)" >&2
    exit 1
  fi
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

# --- Fetch every review once; reused below for both the suppressed-findings
# scan and the verdict, instead of hitting the API twice for the same data.
reviews_json="$(gh api "repos/$owner/$repo/pulls/$pr_number/reviews" --paginate)"

# --- Suppressed / "previously missed" findings: body-only prose, no thread ---
# Copilot's review body wraps these as "**path:line**" headers followed by
# "* finding text" bullets inside a collapsed "Suppressed comments" section.
# They never get a comment id, so gh api .../comments will never show them —
# reading every review's raw body is the only way to see them at all.
echo "-- Suppressed/previously-missed findings across all reviews (dedup) --"
suppressed="$(jq -r '.[] | select(.body != "") | .body' <<<"$reviews_json" \
  | awk '
    /^\*\*[^*]+:[0-9]+\*\*$/ {
      loc = substr($0, 3, length($0) - 4)
      # getline returns 0 at EOF and -1 on error; unchecked, nextline
      # keeps its previous value, so a header at the very end of input
      # could wrongly inherit a bullet line from an earlier record.
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

# --- Latest review verdict (chronological, not array order) ---
echo "-- Latest review verdict --"
# shellcheck disable=SC2016 # single-quoted on purpose: $r below is a jq variable, not a shell one
jq -r 'sort_by(.submitted_at) | map(select(.body != "")) | last as $r
    | if $r == null then "(no review with a summary yet)"
      else "[\($r.submitted_at)] \($r.user.login) on \($r.commit_id[0:8]): " + ($r.body | split("\n")[0])
      end' <<<"$reviews_json"
